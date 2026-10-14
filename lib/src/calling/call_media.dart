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
  Widget view({required bool local});
  Future<void> dispose();
}

class NativeCallMedia implements CallMedia {
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  final stream = StreamController<Map<String, dynamic>>.broadcast();
  MediaStream? localStream, remoteStream;
  RTCPeerConnection? peer;
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
    await Helper.setSpeakerphoneOn(video);
  }

  @override
  Future<void> connect(Map<String, dynamic> configuration) =>
      connecting ??= _connect(configuration);
  Future<void> _connect(Map<String, dynamic> configuration) async {
    if (disposed || localStream == null) throw StateError('Call disposed');
    peer = await createPeerConnection({
      ...configuration,
      'sdpSemantics': 'unified-plan',
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
        emit({'type': 'media'});
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
      await peer!.addTrack(t, localStream!);
    }
  }

  Future<String> description(bool isOffer) async {
    final p = peer;
    if (disposed || p == null) throw StateError('No peer');
    final d = isOffer ? await p.createOffer() : await p.createAnswer();
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
  Future<void> speaker(bool value) => Helper.setSpeakerphoneOn(value);
  @override
  Future<void> camera(bool value) async {
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
  Widget view({required bool local}) => RTCVideoView(
    local ? this.local : remote,
    mirror: local && front,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
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
