// Only live voice-note owners register here; their dispose removes the callback.
// A call waits for recording/playback to release native audio before getUserMedia.
final voiceMediaStops = <Object, Future<void> Function()>{};

Future<void> stopVoiceForCall({Object? except}) async {
  for (final owner in List<Object>.of(voiceMediaStops.keys)) {
    if (owner == except) continue;
    await voiceMediaStops[owner]?.call();
  }
}
