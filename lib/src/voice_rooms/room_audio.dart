import 'dart:async';
import 'package:livekit_client/livekit_client.dart' as lk;

abstract class RoomAudio {
  Stream<Map<String, dynamic>> get events;
  bool get canPublish;
  bool get micEnabled;
  Set<String> get speakers;
  Set<String> get liveIdentities;
  Set<String> get openMics;
  Future<void> connect(Map<String, dynamic> connection);
  Future<void> microphone(bool enabled);
  Future<void> speaker(bool enabled);
  Future<void> dispose();
}

class LiveKitRoomAudio implements RoomAudio {
  final lk.Room room = lk.Room(
    roomOptions: const lk.RoomOptions(
      defaultAudioCaptureOptions: lk.AudioCaptureOptions(
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        stopAudioCaptureOnMute: true,
      ),
      stopLocalTrackOnUnpublish: true,
    ),
  );
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  lk.EventsListener<lk.RoomEvent>? listener;
  bool disposed = false;
  Future<void> work = Future.value(), connectionWork = Future.value();
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  bool get canPublish => room.localParticipant?.permissions.canPublish == true;
  @override
  bool get micEnabled => room.localParticipant?.isMicrophoneEnabled() == true;
  @override
  Set<String> get speakers =>
      room.activeSpeakers.map((p) => p.identity).toSet();
  @override
  Set<String> get liveIdentities => {
    if (room.localParticipant != null) room.localParticipant!.identity,
    ...room.remoteParticipants.values.map((p) => p.identity),
  };
  @override
  Set<String> get openMics => {
    if (micEnabled && room.localParticipant != null)
      room.localParticipant!.identity,
    ...room.remoteParticipants.values
        .where((p) => !p.isMuted)
        .map((p) => p.identity),
  };
  void emit(String type) {
    if (!disposed && !bus.isClosed) bus.add({'type': type});
  }

  @override
  Future<void> connect(Map<String, dynamic> connection) {
    connectionWork = () async {
      if (disposed) return;
      listener = room.createListener()
        ..on<lk.RoomEvent>((e) {
          if (e is lk.RoomDisconnectedEvent)
            emit('disconnected');
          else if (e is lk.ReconnectingEvent)
            emit('reconnecting');
          else if (e is lk.RoomReconnectedEvent)
            emit('reconnected');
          else
            emit('changed');
        });
      // No pre-created tracks or fast-connect microphone: every join is muted.
      await room.connect(
        connection['url'] as String,
        connection['token'] as String,
      );
      if (!disposed) {
        await lk.AudioManager.instance.setSpeakerOutputPreferred(true);
        emit('connected');
      }
    }();
    return connectionWork;
  }

  @override
  Future<void> microphone(bool enabled) {
    final result = work.catchError((Object _) {}).then((_) async {
      if (disposed) return;
      if (enabled && !canPublish)
        throw StateError('microphone permission not ready');
      await room.localParticipant?.setMicrophoneEnabled(enabled);
      if (disposed && enabled)
        await room.localParticipant?.setMicrophoneEnabled(false);
      emit('changed');
    });
    work = result;
    return result;
  }

  @override
  Future<void> speaker(bool enabled) =>
      lk.AudioManager.instance.setSpeakerOutputPreferred(enabled);
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await listener?.dispose();
    try {
      await connectionWork;
    } catch (_) {}
    try {
      await work;
    } catch (_) {}
    try {
      await room.disconnect();
    } finally {
      await room.dispose();
      await bus.close();
    }
  }
}
