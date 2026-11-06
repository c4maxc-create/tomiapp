import 'audio_focus.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../social/social_models.dart';
import '../accounts/account_api.dart';
import 'video_media.dart';
import 'video_preparation.dart';
import 'voice_note.dart' show voiceTime;

Future<VideoDraft?> editPickedVideo(
  BuildContext context,
  XFile file, {
  int maxSeconds = 180,
  bool Function()? audioBusy,
}) => Navigator.push<VideoDraft>(
  context,
  MaterialPageRoute(
    builder: (_) => VideoEditorPage(
      file: file,
      maxSeconds: maxSeconds,
      audioBusy: audioBusy,
    ),
  ),
);

class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({
    super.key,
    required this.file,
    this.maxSeconds = 180,
    this.audioBusy,
  });
  final XFile file;
  final int maxSeconds;
  final bool Function()? audioBusy;
  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage>
    with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool busy = false, ready = false;
  String? error;
  double total = 1, start = 0, end = 1, poster = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voiceMediaStops[this] = () async {
      await player?.pause();
    };
    unawaited(load());
  }

  Future<void> load() async {
    try {
      if (await widget.file.length() > 512 * 1024 * 1024)
        throw StateError('large');
      final p = VideoPlayerController.file(File(widget.file.path));
      player = p;
      await p.initialize().timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final ms = p.value.duration.inMilliseconds;
      if (ms < 100 || ms > 3600000) throw StateError('duration');
      total = ms / 1000;
      end = math.min(total, widget.maxSeconds.toDouble());
      p.addListener(changed);
      setState(() => ready = true);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'تعذّر فتح الفيديو. اختَر ملفًا صالحًا حتى512MB ومدته أقل من ساعة.',
        );
    }
  }

  void changed() {
    final p = player;
    if (p != null &&
        p.value.isPlaying &&
        p.value.position.inMilliseconds >= end * 1000)
      unawaited(p.pause());
    if (mounted) setState(() {});
  }

  void range(RangeValues values) {
    var s = values.start.floorToDouble(),
        e = values.end.ceilToDouble().clamp(0.0, total).toDouble();
    if (e - s > widget.maxSeconds) {
      if (s != start)
        e = math.min(total, s + widget.maxSeconds);
      else
        s = math.max(0.0, e - widget.maxSeconds);
    }
    if (e - s < math.min(1, total)) return;
    setState(() {
      start = s;
      end = e;
      poster = poster.clamp(start, end);
    });
  }

  Future<void> seek(double second) async {
    await player?.seekTo(Duration(milliseconds: (second * 1000).round()));
  }

  Future<void> save() async {
    if (!ready || busy) return;
    setState(() => busy = true);
    try {
      await player?.pause();
      final duration = (end - start).ceil().clamp(1, widget.maxSeconds);
      final draft = await readPickedVideo(
        widget.file,
        edit: VideoEditOptions(
          startSeconds: start.floor(),
          durationSeconds: duration,
          posterMillis: ((poster - start) * 1000).round(),
        ),
      );
      if (mounted) Navigator.pop(context, draft);
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'تعذّر تجهيز الفيديو؛ جرّب مرة ثانية أو اختَر مقطعاً آخر.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(player?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voiceMediaStops.remove(this);
    player?.removeListener(changed);
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('تجهيز الفيديو'),
        actions: [
          TextButton(
            onPressed: ready && !busy ? save : null,
            child: const Text('استخدام المقطع'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (player?.value.isInitialized == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: player!.value.aspectRatio.clamp(.65, 1.8),
                  child: VideoPlayer(player!),
                ),
              )
            else
              const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            if (ready) ...[
              const SizedBox(height: 16),
              Text(
                'حدد الجزء المطلوب • حتى ${widget.maxSeconds} ثانية',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RangeSlider(
                key: const Key('video-trim-range'),
                values: RangeValues(start, end),
                min: 0,
                max: total,
                divisions: math.max(1, total.ceil()),
                labels: RangeLabels(
                  voiceTime((start * 1000).round()),
                  voiceTime((end * 1000).round()),
                ),
                onChanged: busy ? null : range,
                onChangeEnd: (_) => seek(start),
              ),
              Text(
                '${voiceTime((start * 1000).round())} — ${voiceTime((end * 1000).round())}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final p = player!;
                        if (p.value.isPlaying) {
                          await p.pause();
                        } else {
                          await stopVoiceForCall(except: this);
                          await p.setVolume(
                            widget.audioBusy?.call() == true ? 0 : 1,
                          );
                          await seek(start);
                          await p.play();
                        }
                      },
                icon: Icon(
                  player!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                label: const Text('معاينة الجزء المختار'),
              ),
              const SizedBox(height: 16),
              const Text('اختَر صورة الغلاف'),
              Slider(
                key: const Key('video-cover-frame'),
                value: poster.clamp(start, end),
                min: start,
                max: math.max(start + .01, end),
                label: voiceTime((poster * 1000).round()),
                onChanged: busy ? null : (v) => setState(() => poster = v),
                onChangeEnd: seek,
              ),
              const Text(
                'المقطع الأصلي يبقى في الاستوديو. تظهر هذه الصورة قبل تشغيل الفيديو.',
              ),
            ],
            if (busy) ...[
              const LinearProgressIndicator(),
              const Text(
                'جارٍ قص المقطع وتجهيزه للرفع…',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
