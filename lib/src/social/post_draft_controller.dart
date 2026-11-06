import 'package:flutter/widgets.dart';
import '../messaging/upload_transfer.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../messaging/chat_models.dart';
import '../messaging/draft_store.dart';
import 'social_models.dart';

class PostDraftController extends ChangeNotifier with WidgetsBindingObserver {
  PostDraftController(this.accounts)
    : owner = accounts.draftOwnerId,
      session = accounts.sessionRevision {
    WidgetsBinding.instance.addObserver(this);
    restored = restore();
  }
  final AccountController accounts;
  final String? owner;
  final int session;
  late final Future<void> restored;
  PendingChatMessage item = PendingChatMessage('', null);
  bool disposed = false, loading = true, busy = false, storageReady = true;
  String? error;
  UploadTransfer? transfer;
  void cancelUpload() => transfer?.cancel();
  String audience = 'public';
  void selectAudience(String value) {
    if (locked || !['public', 'followers'].contains(value)) return;
    audience = value;
    item = PendingChatMessage(item.text, item.image, video: item.video);
    unawaited(persist());
    notify();
  }

  Timer? debounce;
  bool get current =>
      !disposed &&
      owner == accounts.draftOwnerId &&
      session == accounts.sessionRevision;
  bool get locked => busy || loading || item.commitAttempted;
  void notify() {
    if (current) notifyListeners();
  }

  Future<void> restore() async {
    try {
      final d = owner == null
          ? null
          : await accounts.draftStore.read(owner!, 'post');
      if (!current || d == null) return;
      item = PendingChatMessage.restore(d);
      audience = d['audience'] == 'followers' ? 'followers' : 'public';
      await loadMedia();
      if (current && item.commitAttempted)
        error =
            'يوجد نشر لم نتأكد من نتيجته؛ اضغط إعادة المحاولة للتحقق قبل نشره مجددًا.';
    } catch (_) {
      if (current) {
        storageReady = false;
        error = 'تعذّر قراءة مسودة المنشور؛ لم تُحذف.';
      }
    } finally {
      if (current) {
        loading = false;
        notify();
      }
    }
  }

  Future<void> loadMedia() async {
    if (item.media != null || !item.hasMedia) return;
    final d = item.savedMedia!,
        b = await accounts.draftStore.bytes(owner!, d['mediaKey'] as String);
    if (!current) return;
    if (d['kind'] == 'video')
      item.video = VideoDraft(
        b,
        durationMs: (d['durationMs'] as num).toInt(),
        width: (d['width'] as num).toInt(),
        height: (d['height'] as num).toInt(),
        poster: d['poster'] as String?,
      );
    else
      item.image = ImageDraft(b, d['type'] as String);
  }

  Future<bool> persist() async {
    await restored;
    if (!current || owner == null) return false;
    if (!storageReady)
      throw const DraftStorageFailure('تعذّر قراءة المسودة؛ لم نكتب فوقها.');
    return accounts.draftStore.write(
      owner!,
      'post',
      {...item.toJson(), 'audience': audience},
      blobs: <String, Uint8List>{
        if (item.media != null) item.mediaKey!: item.media!.bytes,
      },
      valid: () => current,
    );
  }

  void editText(String text) {
    if (locked || !current) return;
    item = PendingChatMessage(text, item.image, video: item.video);
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(
        persist().catchError((Object _) {
          if (current) {
            error = 'تعذّر حفظ مسودة المنشور.';
            notify();
          }
          return false;
        }),
      ),
    );
  }

  Future<void> attachment(ImageDraft? media) async {
    if (locked || !current) return;
    item = PendingChatMessage(
      item.text,
      media is VideoDraft ? null : media,
      video: media is VideoDraft ? media : null,
    );
    try {
      await persist();
      error = null;
    } catch (_) {
      error = 'تعذّر حفظ المرفق على الجهاز.';
      rethrow;
    } finally {
      notify();
    }
  }

  Future<SocialPost?> receipt() async {
    if (!item.commitAttempted) return null;
    try {
      final d = await accounts.chatRequest(
        'GET',
        '/v1/posts/requests/${item.requestId}',
      );
      if (!current) return null;
      return SocialPost.fromJson(d['post'] as Map<String, dynamic>);
    } on AccountFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> clear() async {
    if (!current || busy) return;
    if (!await accounts.draftStore.write(
      owner!,
      'post',
      null,
      valid: () => current,
    ))
      return;
    item = PendingChatMessage('', null);
    error = null;
    notify();
  }

  Future<SocialPost?> publish() async {
    await restored;
    if (!current || busy) return null;
    if (item.text.trim().isEmpty && !item.hasMedia) {
      error = 'اكتب نصًا أو اختَر صورة أو فيديو.';
      notify();
      return null;
    }
    busy = true;
    error = null;
    notify();
    SocialPost? post;
    try {
      if (!await persist()) return null;
      post = await receipt();
      if (!current) return null;
      if (post == null) {
        await loadMedia();
        if (!current) return null;
        if (item.hasMedia && !item.uploaded) {
          if (item.upload != null &&
              (item.preparedAt == null ||
                  DateTime.now().difference(item.preparedAt!).inMinutes >= 14))
            item.upload = null;
          if (item.upload == null) {
            item.upload = await accounts.preparePostMedia(
              item.media!,
              item.requestId,
            );
            if (!current) return null;
            item.preparedAt = DateTime.now();
            if (!await persist()) return null;
          }
          transfer = UploadTransfer()..addListener(notify);
          transfer!.active = true;
          UploadTransfer.owners[item.media!] = transfer;
          try {
            await accounts.uploadImage(item.upload!, item.media!);
          } finally {
            UploadTransfer.owners[item.media!] = null;
            transfer!.active = false;
            transfer!.removeListener(notify);
          }
          if (transfer!.cancelled)
            throw const AccountFailure(
              'UPLOAD_CANCELLED',
              'توقف الرفع؛ المسودة محفوظة.',
            );
          if (!current) return null;
          item.uploaded = true;
          if (!await persist()) return null;
        }
        item.commitAttempted = true;
        if (!await persist()) return null;
        post = await accounts.publishPost(
          item.text,
          item.requestId,
          audience: audience,
          uploadId: item.hasImage ? item.upload?.id : null,
          videoUploadId: item.hasVideo ? item.upload?.id : null,
          attachmentSha256: item.mediaKey,
        );
      }
      if (!current) return null;
      if (!await accounts.draftStore.write(
        owner!,
        'post',
        null,
        valid: () => current,
      ))
        return null;
      item = PendingChatMessage('', null);
      return post;
    } on AccountFailure catch (e) {
      if (current) {
        error = e.message;
        if (e.code == 'REQUEST_REMOVED') {
          await accounts.draftStore.write(
            owner!,
            'post',
            null,
            valid: () => current,
          );
          if (current) item = PendingChatMessage('', null);
        }
        if (e.code == 'UPLOAD_INVALID') {
          item.upload = null;
          item.uploaded = false;
        }
      }
    } catch (_) {
      if (current)
        error = 'تعذّر الحفظ أو النشر؛ المسودة محفوظة ويمكن إعادة المحاولة.';
    } finally {
      if (current) {
        busy = false;
        try {
          if (post == null) await persist();
        } catch (_) {
          error =
              'تعذّر حفظ المسودة على الجهاز؛ أبقِ هذه الصفحة مفتوحة وأعد المحاولة.';
        }
        notify();
      }
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && current && !busy) {
      debounce?.cancel();
      unawaited(
        persist().catchError((Object _) {
          if (current) {
            error = 'تعذّر حفظ المسودة على الجهاز.';
            notify();
          }
          return false;
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    transfer?.cancel();
    disposed = true;
    debounce?.cancel();
    super.dispose();
  }
}
