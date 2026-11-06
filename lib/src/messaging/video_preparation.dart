import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../accounts/account_api.dart';

/// Native codec conversion happens before creating any upload/nonce. Never
/// changes an uncertain request or deletes the user's gallery original.
class VideoPreparation {
  static Future<void> tail = Future.value();
  static Future<XFile> prepare(XFile source) {
    final done = Completer<XFile>();
    tail = tail.catchError((Object _) {}).then((_) async {
      try {
        done.complete(await convert(source));
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static Future<XFile> convert(XFile source) async {
    if (!Platform.isAndroid && !Platform.isIOS) return source;
    if (await source.length() > 512 * 1024 * 1024)
      throw const AccountFailure(
        'INVALID_VIDEO',
        'الفيديو أكبر من512 MB؛ قصّه أو قلّل حجمه قبل اختياره.',
      );
    final info = await VideoCompress.getMediaInfo(source.path);
    final duration = info.duration ?? 0;
    if (duration < 100 || duration > 180000)
      throw const AccountFailure(
        'VIDEO_DURATION',
        'اختار فيديو مدته حتى ثلاث دقائق.',
      );
    for (final quality in [
      VideoQuality.Res1280x720Quality,
      VideoQuality.Res960x540Quality,
    ]) {
      final out = await VideoCompress.compressVideo(
        source.path,
        quality: quality,
        includeAudio: true,
        deleteOrigin: false,
        frameRate: 30,
      );
      if (out?.path == null) continue;
      final file = File(out!.path!);
      if (await file.length() <= 25 * 1024 * 1024)
        return XFile(file.path, mimeType: 'video/mp4');
      if (file.path != source.path) await file.delete();
    }
    throw const AccountFailure(
      'VIDEO_PREPARATION',
      'تعذّر تجهيز الفيديو بحجم مناسب؛ جرّب قصّ جزء منه.',
    );
  }
}
