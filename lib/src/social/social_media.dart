import 'dart:async';
import '../preferences/media_preferences.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../messaging/audio_focus.dart';
import 'social_models.dart';

/// Allocates a player only for a visible tile. Feed playback starts muted.
class InlineSocialVideo extends StatefulWidget {
  const InlineSocialVideo({
    super.key,
    required this.video,
    required this.source,
    this.active = true,
    this.preview = false,
  });
  final PostVideo video;
  final Future<Uri?> Function() source;
  final bool active, preview;
  @override
  State<InlineSocialVideo> createState() => _InlineSocialVideoState();
}

class _InlineSocialVideoState extends State<InlineSocialVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? player;
  ScrollPosition? scroll;
  Timer? eviction;
  bool loading = false,
      visible = false,
      foreground = true,
      muted = true,
      userPaused = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voiceMediaStops[this] = pauseForAudio;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (next != scroll) {
      scroll?.removeListener(check);
      scroll = next;
      scroll?.addListener(check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  @override
  void didUpdateWidget(covariant InlineSocialVideo old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) check();
  }

  bool get canPlay =>
      widget.active &&
      visible &&
      foreground &&
      ModalRoute.of(context)?.isCurrent != false;
  void check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    bool next = false;
    if (box is RenderBox && box.hasSize) {
      final y = box.localToGlobal(Offset.zero).dy,
          h = box.size.height,
          screen = MediaQuery.sizeOf(context).height;
      final shown = (math.min(screen, y + h) - math.max(0.0, y)).clamp(0.0, h);
      next = h > 0 && shown / h > .55;
    }
    visible = next;
    if (canPlay) {
      eviction?.cancel();
      eviction = null;
      if (player == null && !loading && error == null) {
        unawaited(load());
      } else if (!widget.preview && !userPaused) {
        unawaited(player?.play());
      }
    } else {
      unawaited(player?.pause());
      eviction ??= Timer(const Duration(seconds: 10), () {
        eviction = null;
        if (!canPlay) unawaited(release());
      });
    }
  }

  Future<void> pauseForAudio() async {
    userPaused = true;
    await player?.pause();
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    if (loading) return;
    final gen = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    VideoPlayerController? candidate;
    try {
      if (!await MediaPreferences.instance.allowNetworkMedia())
        throw StateError('Wi-Fi required');
      final uri = await widget.source();
      if (uri == null) throw StateError('missing video');
      if (!mounted || gen != generation) return;
      candidate = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await candidate.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || gen != generation) {
        await candidate.dispose();
        return;
      }
      player = candidate;
      candidate = null;
      await player!.setLooping(true);
      await player!.setVolume(muted ? 0 : 1);
      player!.addListener(changed);
      if (canPlay && !widget.preview && !userPaused) await player!.play();
    } catch (_) {
      await candidate?.dispose();
      if (mounted && gen == generation) error = 'تعذّر تشغيل الفيديو';
    } finally {
      if (mounted && gen == generation) setState(() => loading = false);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> toggle() async {
    if (player == null) {
      await load();
      return;
    }
    final p = player!;
    if (p.value.isPlaying) {
      userPaused = true;
      await p.pause();
    } else {
      await stopVoiceForCall(except: this);
      userPaused = false;
      if (mounted && canPlay) await p.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> release() async {
    generation++;
    final p = player;
    player = null;
    p?.removeListener(changed);
    await p?.dispose();
    if (mounted) setState(() => loading = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    check();
  }

  @override
  void dispose() {
    generation++;
    eviction?.cancel();
    scroll?.removeListener(check);
    WidgetsBinding.instance.removeObserver(this);
    voiceMediaStops.remove(this);
    player?.removeListener(changed);
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (widget.video.width / widget.video.height)
        .clamp(9 / 16, 1.91)
        .toDouble();
    return AspectRatio(
      aspectRatio: widget.preview ? 1 : ratio,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (player?.value.isInitialized == true)
              FittedBox(
                fit: widget.preview ? BoxFit.cover : BoxFit.contain,
                child: SizedBox(
                  width: player!.value.size.width,
                  height: player!.value.size.height,
                  child: VideoPlayer(player!),
                ),
              ),
            if (loading && !widget.preview)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (widget.preview)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              )
            else ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  onDoubleTap: toggle,
                  child: Center(
                    child: error != null
                        ? TextButton(
                            onPressed: load,
                            child: Text('$error • إعادة المحاولة'),
                          )
                        : player?.value.isPlaying == true
                        ? const SizedBox.shrink()
                        : const Icon(
                            Icons.play_circle_outline,
                            color: Colors.white,
                            size: 54,
                          ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  tooltip: muted ? 'تشغيل صوت الفيديو' : 'كتم الفيديو',
                  onPressed: () async {
                    if (muted) await stopVoiceForCall(except: this);
                    if (!mounted) return;
                    setState(() => muted = !muted);
                    await player?.setVolume(muted ? 0 : 1);
                  },
                  icon: Icon(
                    muted ? Icons.volume_off : Icons.volume_up,
                    size: 18,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
