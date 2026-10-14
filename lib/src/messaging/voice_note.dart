import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../widgets.dart';
import 'chat_models.dart';

String voiceTime(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Lazily allocates the native player. A page has only one active voice note.
class VoicePlayback extends ChangeNotifier with WidgetsBindingObserver {
  VoicePlayback() {
    WidgetsBinding.instance.addObserver(this);
  }
  AudioPlayer? player;
  StreamSubscription<PlayerState>? stateSub;
  StreamSubscription<Duration>? positionSub;
  String? activeId, error;
  int positionMs = 0, durationMs = 0, generation = 0;
  bool playing = false, busy = false, disposed = false;
  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> toggle(
    String id,
    Future<Uri?> Function() source, {
    required int duration,
  }) async {
    if (disposed || busy) return;
    if (activeId == id && playing) {
      await player?.pause();
      return;
    }
    final gen = ++generation;
    busy = true;
    error = null;
    notify();
    try {
      final uri = await source();
      if (disposed || gen != generation) return;
      if (uri == null) throw StateError('Unavailable voice');
      final previous = activeId == id ? positionMs : 0;
      player ??= AudioPlayer();
      stateSub ??= player!.playerStateStream.listen((s) {
        playing = s.playing && s.processingState != ProcessingState.completed;
        if (s.processingState == ProcessingState.completed)
          positionMs = durationMs;
        notify();
      });
      positionSub ??= player!.positionStream.listen((p) {
        positionMs = p.inMilliseconds;
        notify();
      });
      await player!.stop();
      if (disposed || gen != generation) return;
      activeId = id;
      positionMs = 0;
      durationMs = duration;
      final actual = await player!.setAudioSource(AudioSource.uri(uri));
      if (disposed || gen != generation) return;
      durationMs = actual?.inMilliseconds ?? duration;
      if (previous > 0 && previous < durationMs)
        await player!.seek(Duration(milliseconds: previous));
      if (disposed || gen != generation) return;
      unawaited(
        player!.play().catchError((Object _) {
          if (!disposed && gen == generation) {
            playing = false;
            error = 'تعذّر تشغيل التسجيل؛ جرّب مرة ثانية.';
            notify();
          }
        }),
      );
    } catch (_) {
      if (!disposed && gen == generation) {
        playing = false;
        error = 'تعذّر تشغيل التسجيل؛ جرّب مرة ثانية.';
      }
    } finally {
      if (!disposed && gen == generation) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> stop() async {
    generation++;
    busy = false;
    playing = false;
    await player?.stop();
    notify();
  }

  Future<void> seek(double value) async {
    if (!busy) await player?.seek(Duration(milliseconds: value.round()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stop());
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stateSub?.cancel());
    unawaited(positionSub?.cancel());
    unawaited(player?.dispose());
    super.dispose();
  }
}

class VoicePlayer extends StatelessWidget {
  const VoicePlayer({
    super.key,
    required this.playback,
    required this.id,
    required this.durationMs,
    required this.source,
  });
  final VoicePlayback playback;
  final String id;
  final int durationMs;
  final Future<Uri?> Function() source;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: playback,
    builder: (context, _) {
      final active = playback.activeId == id,
          position = active ? playback.positionMs : 0,
          duration = active ? playback.durationMs : durationMs;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: ValueKey('voice-play-$id'),
                tooltip: active && playback.playing
                    ? 'إيقاف مؤقت'
                    : 'تشغيل التسجيل',
                onPressed: playback.busy
                    ? null
                    : () => playback.toggle(id, source, duration: durationMs),
                icon: Icon(
                  active && playback.playing
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  color: TomiColors.accent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('رسالة صوتية'),
                    Text(
                      '${voiceTime(position)} / ${voiceTime(duration)}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TomiColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active && duration > 0)
            Slider(
              value: position.clamp(0, duration).toDouble(),
              max: duration.toDouble(),
              onChanged: playback.busy ? null : playback.seek,
            ),
          if (active && playback.error != null)
            Text(
              playback.error!,
              style: const TextStyle(color: TomiColors.pink, fontSize: 12),
            ),
        ],
      );
    },
  );
}

class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({super.key});
  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet>
    with WidgetsBindingObserver {
  final recorder = AudioRecorder(),
      playback = VoicePlayback(),
      clock = Stopwatch();
  Timer? timer;
  String? path, error;
  bool recording = false, busy = false;
  int durationMs = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> start() async {
    if (busy || recording) return;
    final gen = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await playback.stop();
      if (!await recorder.hasPermission()) {
        if (mounted)
          setState(
            () => error = 'اسمح لـTOMI باستخدام المايك من إعدادات الهاتف.',
          );
        return;
      }
      if (!mounted || gen != generation) return;
      await removeFile();
      final directory = await getTemporaryDirectory();
      if (!mounted || gen != generation) return;
      path =
          '${directory.path}/tomi-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 160000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path!,
      );
      if (!mounted || gen != generation) {
        await recorder.cancel();
        return;
      }
      clock.reset();
      clock.start();
      setState(() => recording = true);
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => durationMs = clock.elapsedMilliseconds);
        if (durationMs >= 300000) unawaited(stop());
      });
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر بدء التسجيل؛ تأكد من صلاحية المايك.');
    } finally {
      if (mounted && gen == generation) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    if (!recording || busy) return;
    setState(() => busy = true);
    timer?.cancel();
    clock.stop();
    try {
      path = await recorder.stop();
      durationMs = clock.elapsedMilliseconds.clamp(100, 300000);
      if (mounted) setState(() => recording = false);
      if (path == null || durationMs < 500) {
        await removeFile();
        if (mounted) setState(() => error = 'سجّل نصف ثانية على الأقل.');
      }
    } catch (_) {
      if (mounted)
        setState(() {
          recording = false;
          error = 'تعذّر حفظ التسجيل؛ سجّله مرة ثانية.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> removeFile() async {
    final old = path;
    path = null;
    if (old != null)
      try {
        await File(old).delete();
      } catch (_) {}
  }

  Future<void> confirm() async {
    if (path == null || recording || busy) return;
    setState(() => busy = true);
    try {
      await playback.stop();
      final file = File(path!);
      if (await file.length() > 6 * 1024 * 1024) throw StateError('Too large');
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.pop(context, AudioDraft(bytes, durationMs));
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر تجهيز التسجيل، أو حجمه يتجاوز 6 MB.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (recording && state != AppLifecycleState.resumed) unawaited(stop());
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      generation++;
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    clock.stop();
    WidgetsBinding.instance.removeObserver(this);
    playback.dispose();
    unawaited(recorder.dispose());
    unawaited(removeFile());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'رسالة صوتية',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('سجّل، اسمع التسجيل، وبعدها أرسله. الحد 5 دقائق.'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                error!,
                style: const TextStyle(color: TomiColors.pink),
              ),
            ),
          if (recording)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '🔴 ${voiceTime(durationMs)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26),
              ),
            ),
          if (path != null && !recording && durationMs >= 500)
            VoicePlayer(
              playback: playback,
              id: 'draft',
              durationMs: durationMs,
              source: () async => path == null ? null : Uri.file(path!),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('voice-start'),
                onPressed: busy || recording ? null : start,
                icon: const Icon(Icons.mic),
                label: Text(path == null ? 'بدء التسجيل' : 'تسجيل من جديد'),
              ),
              if (recording)
                FilledButton.icon(
                  key: const Key('voice-stop'),
                  onPressed: busy ? null : stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('إيقاف التسجيل'),
                ),
              if (path != null && !recording && durationMs >= 500)
                FilledButton.icon(
                  key: const Key('voice-confirm'),
                  onPressed: busy ? null : confirm,
                  icon: const Icon(Icons.send),
                  label: const Text('إرسال التسجيل'),
                ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
