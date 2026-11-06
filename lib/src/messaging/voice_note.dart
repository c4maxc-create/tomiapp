import '../preferences/media_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../widgets.dart';
import 'chat_models.dart';
import 'audio_focus.dart';

Future<void> prepareVoiceAudio({required bool recording}) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await const MethodChannel(
      'tomi/mobile',
    ).invokeMethod('prepareVoiceAudio', {'recording': recording});
  } on MissingPluginException {
    /* Older APKs have no route repair bridge. */
  }
}

String voiceTime(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Lazily allocates the native player. A page has only one active voice note.
class VoicePlayback extends ChangeNotifier with WidgetsBindingObserver {
  VoicePlayback() {
    voiceMediaStops[this] = stop;
    WidgetsBinding.instance.addObserver(this);
  }
  AudioPlayer? player;
  StreamSubscription<PlayerState>? stateSub;
  StreamSubscription<Duration>? positionSub;
  String? activeId, error;
  int positionMs = 0, durationMs = 0, generation = 0;
  bool playing = false, busy = false, disposed = false;
  double speed = 1;
  Future<void> cycleSpeed() async {
    speed = speed == 1
        ? 2
        : speed == 2
        ? 3
        : 1;
    try {
      await player?.setSpeed(speed);
    } catch (_) {
      speed = 1;
      error = 'تعذّر تغيير السرعة؛ أعد تشغيل التسجيل وحاول مجددًا.';
    }
    notify();
  }

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
      await stopVoiceForCall(except: this);
      if (disposed || gen != generation) return;
      final uri = await source();
      if (disposed || gen != generation) return;
      if (uri == null) throw StateError('Unavailable voice');
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          !await MediaPreferences.instance.allowNetworkMedia()) {
        error =
            'تشغيل الصوت متوقف: فعّلت الوسائط عبر Wi-Fi فقط. اتصل بالواي فاي أو غيّر الإعداد.';
        return;
      }
      final previous = activeId == id ? positionMs : 0;
      await prepareVoiceAudio(recording: false);
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
      await player!.setVolume(1);
      await player!.setSpeed(speed);
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
    voiceMediaStops.remove(this);
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
              TextButton(
                key: ValueKey('voice-speed-$id'),
                onPressed: playback.cycleSpeed,
                child: Text('${playback.speed.toInt()}×'),
              ),
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
  const VoiceRecorderSheet({
    super.key,
    this.autoStart = false,
    this.diagnostic = false,
    this.onRecording,
    this.cancel,
  });
  final bool autoStart, diagnostic;
  final ValueChanged<bool>? onRecording;
  final ValueNotifier<bool>? cancel;
  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet>
    with WidgetsBindingObserver {
  final recorder = AudioRecorder(),
      playback = VoicePlayback(),
      clock = Stopwatch();
  Timer? timer;
  StreamSubscription<Amplitude>? amplitudes;
  double peakDb = -160, levelDb = -160;
  int amplitudeSamples = 0;
  bool silent = false, allowSilent = false;
  String? path, error;
  bool recording = false, busy = false;
  int durationMs = 0, generation = 0;
  bool starting = false;
  double cancelDrag = 0;
  Future<void>? startWork, stopWork, callStop;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voiceMediaStops[this] = stopForCall;
    widget.cancel?.addListener(cancelRequested);
    if (widget.autoStart)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.cancel?.value == true) {
          cancelRequested();
        } else {
          unawaited(start());
        }
      });
  }

  void cancelRequested() {
    if (widget.cancel?.value == true && mounted) {
      generation++;
      widget.onRecording?.call(false);
      Navigator.pop(context);
    }
  }

  Future<void> stopForCall() => callStop ??= _stopForCall();
  Future<void> _stopForCall() async {
    final wasStarting = starting;
    generation++;
    try {
      await startWork;
    } catch (_) {}
    if (!mounted) return;
    setState(() => busy = false);
    await playback.stop();
    if (recording)
      await stop();
    else if (wasStarting)
      await removeFile();
  }

  Future<void> start() {
    if (busy || recording) return Future.value();
    callStop = null;
    stopWork = null;
    starting = true;
    return startWork = _start().whenComplete(() => starting = false);
  }

  Future<void> _start() async {
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
      await prepareVoiceAudio(recording: true);
      await removeFile();
      peakDb = -160;
      levelDb = -160;
      amplitudeSamples = 0;
      silent = false;
      allowSilent = false;
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
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.mic,
            audioManagerMode: AudioManagerMode.modeNormal,
          ),
        ),
        path: path!,
      );
      if (!mounted || gen != generation) {
        await recorder.cancel();
        return;
      }
      await amplitudes?.cancel();
      amplitudes = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 150))
          .listen((value) {
            if (!mounted || !recording || !value.current.isFinite) return;
            amplitudeSamples++;
            if (value.current > peakDb) peakDb = value.current;
            setState(() => levelDb = value.current);
          }, onError: (Object _) {});
      clock.reset();
      clock.start();
      setState(() => recording = true);
      widget.onRecording?.call(true);
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => durationMs = clock.elapsedMilliseconds);
        if (durationMs >= 300000) unawaited(stop());
      });
    } on PlatformException catch (e) {
      if (mounted)
        setState(
          () => error = ['MIC_MUTED', 'AUDIO_BUSY'].contains(e.code)
              ? e.message
              : 'تعذّر بدء التسجيل؛ تأكد من صلاحية المايك.',
        );
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر بدء التسجيل؛ تأكد من صلاحية المايك.');
    } finally {
      if (mounted && gen == generation) setState(() => busy = false);
    }
  }

  Future<void> stop() => stopWork ??= _stop();
  Future<void> _stop() async {
    if (!recording || busy) return;
    setState(() => busy = true);
    timer?.cancel();
    clock.stop();
    try {
      await amplitudes?.cancel();
      amplitudes = null;
      path = await recorder.stop();
      silent = amplitudeSamples >= 3 && peakDb < -80;
      durationMs = clock.elapsedMilliseconds.clamp(100, 300000);
      if (mounted) setState(() => recording = false);
      widget.onRecording?.call(false);
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
    if (path == null || recording || busy || (silent && !allowSilent)) return;
    setState(() => busy = true);
    try {
      await playback.stop();
      if (widget.diagnostic) {
        if (mounted) Navigator.pop(context);
        return;
      }
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
    voiceMediaStops.remove(this);
    widget.cancel?.removeListener(cancelRequested);
    widget.onRecording?.call(false);
    generation++;
    timer?.cancel();
    clock.stop();
    WidgetsBinding.instance.removeObserver(this);
    playback.dispose();
    unawaited(amplitudes?.cancel());
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
          Text(
            widget.diagnostic ? 'فحص المايك على جهازك' : 'رسالة صوتية',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            widget.diagnostic
                ? 'اضغط بدء التسجيل، احچي كم كلمة، أوقفه واسمع المعاينة. التسجيل لا يُرسل وينحذف عند إغلاق الفحص.'
                : 'التسجيل يبدأ فورًا. اسحب لليسار للإلغاء، أو أوقفه وراجعه قبل الإرسال. الحد 5 دقائق.',
          ),
          GestureDetector(
            onHorizontalDragStart: (_) => cancelDrag = 0,
            onHorizontalDragUpdate: (d) {
              cancelDrag += d.delta.dx;
              if (cancelDrag < -64) {
                widget.onRecording?.call(false);
                Navigator.pop(context);
              }
            },
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.arrow_back), Text('اسحب لليسار للإلغاء')],
              ),
            ),
          ),
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
          if (recording)
            LinearProgressIndicator(
              value: ((levelDb + 80) / 80).clamp(0.0, 1.0),
            ),
          if (silent && !recording)
            CheckboxListTile(
              value: allowSilent,
              onChanged: (v) => setState(() => allowSilent = v == true),
              title: const Text(
                'لم نرصد صوتًا واضحًا. راجع المايك أو أعد التسجيل.',
              ),
              subtitle: Text(
                widget.diagnostic
                    ? 'إنهاء الفحص رغم التنبيه'
                    : 'إرسال رغم التنبيه',
              ),
              controlAffinity: ListTileControlAffinity.leading,
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
                  onPressed: busy || (silent && !allowSilent) ? null : confirm,
                  icon: const Icon(Icons.send),
                  label: Text(
                    widget.diagnostic ? 'إنهاء الفحص' : 'إرسال التسجيل',
                  ),
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
