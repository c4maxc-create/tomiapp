// Only live voice-note owners register here; their dispose removes the callback.
// A call waits for recording/playback to release native audio before getUserMedia.
final voiceMediaStops = <Object, Future<void> Function()>{};

Future<void> stopVoiceForCall() async {
  for (final stop in List<Future<void> Function()>.of(voiceMediaStops.values)) {
    await stop();
  }
}
