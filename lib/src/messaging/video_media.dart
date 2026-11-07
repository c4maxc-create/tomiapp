import 'dart:convert';
import 'dart:ui' as ui;
import 'package:video_compress/video_compress.dart';
import '../preferences/media_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../accounts/account_api.dart';
import '../social/social_models.dart';
import 'audio_focus.dart';
import 'video_preparation.dart';
import 'voice_note.dart' show voiceTime;

Future<VideoDraft> readPickedVideo(
  XFile original, {
  VideoEditOptions? edit,
  int maxSeconds = 180,
  bool forceConversion = false,
}) async {
  final file = await VideoPreparation.prepare(
    original,
    edit: edit,
    maxSeconds: maxSeconds,
    forceConversion: forceConversion,
  );
  if (await file.length() > 25 * 1024 * 1024)
    throw const AccountFailure(
      'INVALID_VIDEO',
      'الفيديو يجب أن يكون حتى25 MB وثلاث دقائق و1080p.',
    );
  final player = VideoPlayerController.file(File(file.path));
  try {
    await player.initialize().timeout(const Duration(seconds: 20));
    final v = player.value,
        w = v.size.width.round(),
        h = v.size.height.round(),
        ms = v.duration.inMilliseconds;
    if (ms < 100 ||
        ms > maxSeconds * 1000 ||
        w < 1 ||
        h < 1 ||
        w * h > 1920 * 1080 ||
        w > 1920 ||
        h > 1920)
      throw AccountFailure(
        'INVALID_VIDEO',
        maxSeconds == 60
            ? 'فيديو الستوري حتى60 ثانية.'
            : 'اختَر فيديو حتى1080p وثلاث دقائق.',
      );
    final parts = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (parts.length + chunk.length > 25 * 1024 * 1024)
        throw const AccountFailure('INVALID_VIDEO', 'الفيديو أكبر من25 MB.');
      parts.add(chunk);
    }
    final b = parts.takeBytes();
    if (b.length < 16 ||
        b.length > 25 * 1024 * 1024 ||
        String.fromCharCodes(b.sublist(4, 8)) != 'ftyp')
      throw const AccountFailure(
        'INVALID_VIDEO',
        'اختَر MP4 بترميز H.264 وصوت AAC.',
      );
    String? poster;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final bytes = await VideoCompress.getByteThumbnail(
          edit == null ? original.path : file.path,
          quality: 40,
          position:
              (edit?.posterMillis ?? 0).clamp(0, (ms > 100 ? ms - 100 : 0)) *
              1000,
        );
        if (bytes != null) {
          for (final side in [160, 96]) {
            final codec = await ui.instantiateImageCodec(
              bytes,
              targetWidth: (w >= h ? side : side * w / h).round().clamp(
                1,
                side,
              ),
              targetHeight: (h >= w ? side : side * h / w).round().clamp(
                1,
                side,
              ),
            );
            final frame = await codec.getNextFrame();
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            frame.image.dispose();
            codec.dispose();
            if (png != null && png.lengthInBytes <= 32768) {
              poster =
                  'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
              break;
            }
          }
        }
      } catch (_) {
        /* Preview is optional; video remains usable. */
      }
    }
    return VideoDraft(b, durationMs: ms, width: w, height: h, poster: poster);
  } finally {
    await player.dispose();
    if (file.path != original.path)
      try {
        await File(file.path).delete();
      } catch (_) {}
  }
}

Future<VideoDraft> repairRejectedVideo(VideoDraft old) async {
  final dir = await getTemporaryDirectory(),
      file = File(
        '${dir.path}/tomi-video-repair-${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
  try {
    await file.writeAsBytes(old.bytes, flush: true);
    return await readPickedVideo(XFile(file.path), forceConversion: true);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

/// A poster button allocates a native player only after the user opens it.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.video, required this.source});
  final PostVideo video;
  final Future<Uri?> Function() source;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'فتح الفيديو',
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => VideoPage(source: source)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: (video.width / video.height).clamp(.8, 1.78),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff253947),
                  Color(0xff28243f),
                  Color(0xff101820),
                ],
              ),
            ),
            child: Stack(
              children: [
                if (video.posterBytes != null)
                  Positioned.fill(
                    child: Image.memory(
                      video.posterBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                if (video.poster == null)
                  const Positioned.fill(
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        size: 100,
                        color: Color(0x155fffff),
                      ),
                    ),
                  ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        'فيديو • ${voiceTime(video.durationMs)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${video.width} × ${video.height}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.source});
  final Future<Uri?> Function() source;
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  VideoPlayerController? player;
  String? error;
  bool loading = false, foreground = true;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voiceMediaStops[this] = pause;
    unawaited(load());
  }

  Future<void> pause() async {
    epoch++;
    if (mounted && loading) setState(() => loading = false);
    await player?.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) unawaited(pause());
  }

  Future<void> load() async {
    final e = ++epoch;
    setState(() {
      loading = true;
      error = null;
    });
    final old = player;
    old?.removeListener(changed);
    player = null;
    await old?.dispose();
    VideoPlayerController? next;
    try {
      if (!await MediaPreferences.instance.allowNetworkMedia())
        throw StateError('Wi-Fi required');
      final uri = await widget.source();
      if (!mounted || e != epoch) return;
      if (uri == null || !['https', 'http'].contains(uri.scheme))
        throw StateError('Video unavailable');
      next = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      await next.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || e != epoch) {
        await next.dispose();
        return;
      }
      player = next;
      next = null;
      player!.addListener(changed);
      final preferences = MediaPreferences.instance;
      try {
        await preferences.restore();
      } catch (_) {}
      if (mounted &&
          e == epoch &&
          foreground &&
          preferences.autoplay &&
          !preferences.dataSaver)
        await toggle();
    } catch (_) {
      await next?.dispose();
      if (mounted && e == epoch)
        error = MediaPreferences.instance.wifiOnly
            ? 'تعذّر فتح الفيديو؛ تأكد من Wi-Fi أو غيّر خيار تنزيل الوسائط في الإعدادات.'
            : 'تعذّر فتح الفيديو؛ حدّث الرابط وجرّب مرة ثانية.';
    } finally {
      if (mounted && e == epoch) setState(() => loading = false);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> toggle() async {
    final p = player;
    if (p == null || !foreground) return;
    if (p.value.isPlaying) {
      await p.pause();
      return;
    }
    final e = epoch;
    await stopVoiceForCall(except: this);
    if (!mounted || e != epoch || !foreground || !identical(p, player)) return;
    if (p.value.position >= p.value.duration) await p.seekTo(Duration.zero);
    if (!mounted || e != epoch || !foreground) return;
    try {
      await p.play();
      if (mounted && e != epoch) await p.pause();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تشغيل الفيديو.');
    }
  }

  @override
  void dispose() {
    epoch++;
    WidgetsBinding.instance.removeObserver(this);
    voiceMediaStops.remove(this);
    player?.removeListener(changed);
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = player, v = p?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('الفيديو')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : p == null
                    ? const Icon(Icons.videocam_off_outlined, size: 60)
                    : AspectRatio(
                        aspectRatio: v!.aspectRatio,
                        child: VideoPlayer(p),
                      ),
              ),
            ),
            if (error != null || v?.hasError == true)
              Text(error ?? 'تعذّر تشغيل الفيديو.'),
            if (p != null && v!.isInitialized) ...[
              VideoProgressIndicator(
                p,
                allowScrubbing: true,
                padding: const EdgeInsets.all(16),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    tooltip: v.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                    onPressed: toggle,
                    icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${voiceTime(v.position.inMilliseconds)} / ${voiceTime(v.duration.inMilliseconds)}',
                  ),
                ],
              ),
            ],
            TextButton.icon(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث الفيديو'),
            ),
          ],
        ),
      ),
    );
  }
}
