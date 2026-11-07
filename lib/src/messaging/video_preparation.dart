import 'direct_mp4.dart';
import '../preferences/media_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../accounts/account_api.dart';

/// Native codec conversion happens before creating any upload/nonce. Never
/// changes an uncertain request or deletes the user's gallery original.
class VideoEditOptions {
  const VideoEditOptions({
    required this.startSeconds,
    required this.durationSeconds,
    this.posterMillis = 0,
  });
  final int startSeconds, durationSeconds, posterMillis;
}

class VideoPreparation {
  static Future<void> tail = Future.value();
  static Future<XFile> prepare(
    XFile source, {
    VideoEditOptions? edit,
    int maxSeconds = 180,
    bool forceConversion = false,
  }) {
    final done = Completer<XFile>();
    tail = tail.catchError((Object _) {}).then((_) async {
      try {
        done.complete(
          await convert(
            source,
            edit: edit,
            maxSeconds: maxSeconds,
            forceConversion: forceConversion,
          ),
        );
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static Future<XFile> convert(
    XFile source, {
    VideoEditOptions? edit,
    int maxSeconds = 180,
    bool forceConversion = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return source;
    if (await source.length() > 512 * 1024 * 1024)
      throw const AccountFailure(
        'INVALID_VIDEO',
        'الفيديو أكبر من512 MB؛ اختَر ملفاً أصغر.',
      );
    final info = await VideoCompress.getMediaInfo(source.path);
    final duration = info.duration ?? 0;
    if (duration < 100 ||
        !duration.isFinite ||
        (edit == null && duration > maxSeconds * 1000) ||
        (edit != null &&
            (edit.startSeconds < 0 ||
                edit.durationSeconds < 1 ||
                edit.durationSeconds > 180 ||
                edit.startSeconds * 1000 >= duration ||
                (edit.startSeconds + edit.durationSeconds) * 1000 >
                    duration + 1000)))
      throw AccountFailure(
        'VIDEO_DURATION',
        maxSeconds == 60
            ? 'فيديو الستوري حتى60 ثانية؛ اختَر مقطعاً أقصر.'
            : 'الفيديو حتى ثلاث دقائق؛ اختَر مقطعاً أقصر.',
      );
    final preferences = MediaPreferences.instance;
    try {
      await preferences.restore();
    } catch (_) {}
    if (!forceConversion &&
        edit == null &&
        !preferences.dataSaver &&
        await canSendOriginalMp4(source))
      return source;
    var smaller = preferences.dataSaver;
    if (preferences.smartQuality && !smaller) {
      try {
        final network = await Connectivity().checkConnectivity();
        smaller =
            network.contains(ConnectivityResult.mobile) &&
            !network.contains(ConnectivityResult.wifi) &&
            !network.contains(ConnectivityResult.ethernet);
      } catch (_) {}
    }
    final needsTrim =
        edit != null &&
        (edit.startSeconds > 0 || edit.durationSeconds * 1000 < duration);
    for (final quality in [
      if (!smaller) VideoQuality.Res1280x720Quality,
      VideoQuality.Res960x540Quality,
    ]) {
      final out = await VideoCompress.compressVideo(
        source.path,
        quality: quality,
        includeAudio: true,
        deleteOrigin: false,
        frameRate: 30,
        startTime: needsTrim ? edit.startSeconds : null,
        duration: needsTrim ? edit.durationSeconds : null,
      );
      if (out?.path == null) continue;
      final file = File(out!.path!);
      if (await file.length() <= 25 * 1024 * 1024)
        return XFile(file.path, mimeType: 'video/mp4');
      if (file.path != source.path) await file.delete();
    }
    throw const AccountFailure(
      'VIDEO_PREPARATION',
      'تعذّر تجهيز هذا الفيديو للإرسال؛ أعد المحاولة أو اختَر فيديو آخر.',
    );
  }
}
