import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class CallMedia {
  Stream<Map<String, dynamic>> get events;
  Future<void> prepare(bool video);
  Future<void> connect(Map<String, dynamic> configuration);
  Future<String> offer();
  Future<String> answer();
  Future<void> remoteDescription(String type, String sdp);
  Future<void> candidate(Map<String, dynamic> data);
  Future<void> mute(bool value);
  Future<void> speaker(bool value);
  Future<void> camera(bool enabled);
  Future<void> switchCamera();
  Future<void> setVideo(bool enabled);
  Future<void> rollback();
  Widget view({required bool local});
  Future<void> dispose();
}

class NativeCallMedia implements CallMedia {
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  final stream = StreamController<Map<String, dynamic>>.broadcast();
  MediaStream? localStream, remoteStream;
  RTCPeerConnection? peer;
  RTCRtpSender? videoSender;
  MediaStream? cameraStream;
  Future<void> videoWork = Future.value();
  bool videoEnabled = false;
  Future<void>? preparing, connecting, closing;
  bool disposed = false, localReady = false, remoteReady = false, front = true;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  void emit(Map<String, dynamic> e) {
    if (!disposed && !stream.isClosed) stream.add(e);
  }

  @override
  Future<void> prepare(bool video) => preparing ??= _prepare(video);
  Future<void> _prepare(bool video) async {
    videoEnabled = video;
    await Helper.setAndroidAudioConfiguration(
      AndroidAudioConfiguration.communication,
    );
    if (disposed) return;
    await local.initialize();
    localReady = true;
    if (disposed) return;
    await remote.initialize();
    remoteReady = true;
    if (disposed) return;
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    });
    if (disposed) return;
    local.srcObject = localStream;
    if (WebRTC.platformIsIOS) await Helper.ensureAudioSession();
    if (video)
      await Helper.setSpeakerphoneOnButPreferBluetooth();
    else
      await Helper.setSpeakerphoneOn(false);
  }

  @override
  Future<void> connect(Map<String, dynamic> configuration) =>
      connecting ??= _connect(configuration);
  Future<void> _connect(Map<String, dynamic> configuration) async {
    if (disposed || localStream == null) throw StateError('Call disposed');
    peer = await createPeerConnection({
      ...configuration,
      'sdpSemantics': 'unified-plan',
      'continualGatheringPolicy': 'gather_continually',
    });
    if (disposed) return;
    peer!.onIceCandidate = (c) {
      if (c.candidate?.isNotEmpty == true)
        emit({
          'type': 'candidate',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
    };
    peer!.onTrack = (e) {
      if (!disposed && e.streams.isNotEmpty) {
        remoteStream = e.streams.first;
        remote.srcObject = remoteStream;
        emit({
          'type': 'media',
          'remoteVideo': remoteStream!.getVideoTracks().isNotEmpty,
        });
      }
    };
    peer!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected)
        emit({'type': 'connected'});
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected)
        emit({'type': 'disconnected'});
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed)
        emit({'type': 'failed'});
    };
    for (final t in localStream!.getTracks()) {
      if (disposed) return;
      final sender = await peer!.addTrack(t, localStream!);
      if (t.kind == 'video') videoSender = sender;
    }
  }

  Future<String> description(bool isOffer) async {
    final p = peer;
    if (disposed || p == null) throw StateError('No peer');
    // The plugin defaults OfferToReceiveVideo to true, even for audio-only
    // streams. That adds a video m-line and the audio-call API rejects it.
    final constraints = <String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': videoEnabled,
      },
      'optional': <dynamic>[],
    };
    final d = isOffer
        ? await p.createOffer(constraints)
        : await p.createAnswer(constraints);
    if (disposed) throw StateError('Call disposed');
    await p.setLocalDescription(d);
    return d.sdp!;
  }

  @override
  Future<String> offer() => description(true);
  @override
  Future<String> answer() => description(false);
  @override
  Future<void> remoteDescription(String type, String sdp) async =>
      peer!.setRemoteDescription(RTCSessionDescription(sdp, type));
  @override
  Future<void> candidate(Map<String, dynamic> d) async => peer!.addCandidate(
    RTCIceCandidate(
      d['candidate'] as String?,
      d['sdpMid'] as String?,
      (d['sdpMLineIndex'] as num?)?.toInt(),
    ),
  );
  @override
  Future<void> mute(bool value) async {
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[])
      await Helper.setMicrophoneMute(value, t);
  }

  @override
  Future<void> speaker(bool value) => value
      ? Helper.setSpeakerphoneOnButPreferBluetooth()
      : Helper.setSpeakerphoneOn(false);
  @override
  Future<void> camera(bool value) async {
    if (value && localStream?.getVideoTracks().isEmpty == true) {
      await setVideo(true);
      return;
    }
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[])
      t.enabled = value;
  }

  @override
  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks();
    if (tracks?.isNotEmpty == true) {
      await Helper.switchCamera(tracks!.first);
      front = !front;
    }
  }

  @override
  Future<void> setVideo(bool enabled) {
    final work = videoWork.then((_) => _setVideo(enabled));
    videoWork = work.catchError((Object _) {});
    return work;
  }

  Future<void> _setVideo(bool enabled) async {
    if (disposed || localStream == null || peer == null) return;
    if (!enabled) {
      videoEnabled = false;
      // Stopping the capture must still happen if a platform cannot detach
      // the sender. An ended video track cannot keep transmitting frames.
      try {
        await videoSender?.replaceTrack(null);
      } catch (_) {}
      for (final track in localStream!.getVideoTracks().toList()) {
        track.enabled = false;
        try {
          await localStream!.removeTrack(track);
        } catch (_) {}
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await cameraStream?.dispose();
      } catch (_) {}
      cameraStream = null;
      local.srcObject = localStream;
      emit({'type': 'media'});
      return;
    }
    if (localStream!.getVideoTracks().isNotEmpty) {
      videoEnabled = true;
      await camera(true);
      return;
    }
    // Called only after the server confirms both users consented to video.
    final captured = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': front ? 'user' : 'environment',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 24, 'max': 30},
      },
    });
    if (disposed) {
      for (final track in captured.getTracks()) {
        await track.stop();
      }
      await captured.dispose();
      return;
    }
    cameraStream = captured;
    final track = captured.getVideoTracks().first;
    await localStream!.addTrack(track);
    if (videoSender == null) {
      videoSender = await peer!.addTrack(track, localStream!);
    } else {
      await videoSender!.replaceTrack(track);
    }
    videoEnabled = true;
    local.srcObject = localStream;
    emit({'type': 'media'});
  }

  @override
  Future<void> rollback() async {
    final p = peer;
    if (disposed || p == null) return;
    final state = await p.getSignalingState();
    if (state != null &&
        state != RTCSignalingState.RTCSignalingStateStable &&
        state != RTCSignalingState.RTCSignalingStateClosed) {
      await p.setLocalDescription(RTCSessionDescription('', 'rollback'));
    }
  }

  @override
  Widget view({required bool local}) => RTCVideoView(
    local ? this.local : remote,
    mirror: local && front,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );
  @override
  Future<void> dispose() => closing ??= _dispose();
  Future<void> _dispose() async {
    disposed = true;
    try {
      await preparing;
    } catch (_) {}
    try {
      await connecting;
    } catch (_) {}
    try {
      await videoWork;
    } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await peer?.close();
      await peer?.dispose();
    } catch (_) {}
    try {
      await localStream?.dispose();
      await cameraStream?.dispose();
      await remoteStream?.dispose();
    } catch (_) {}
    if (localReady) {
      try {
        local.srcObject = null;
        await local.dispose();
      } catch (_) {}
    }
    if (remoteReady) {
      try {
        remote.srcObject = null;
        await remote.dispose();
      } catch (_) {}
    }
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    await stream.close();
  }
}
