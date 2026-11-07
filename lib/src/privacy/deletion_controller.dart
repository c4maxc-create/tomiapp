import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../messaging/draft_store.dart';
import '../social/social_models.dart';

String deletionReceiptToken() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

class AccountDeletionController extends ChangeNotifier {
  AccountDeletionController(this.accounts) {
    accounts.addListener(accountChanged);
  }
  final AccountController accounts;
  Map<String, dynamic>? pending, status, preview;
  String? error, localError;
  String? previewUserId;
  bool busy = false, disposed = false, ready = false, loading = true;
  String get receiptOwner =>
      draftOwner(accounts.api.baseUrl, 'account-erasure-v1');
  bool get accepted =>
      status?['accepted'] == true || pending?['accepted'] == true;
  void changed() {
    if (!disposed) notifyListeners();
  }

  void accountChanged() {
    if (previewUserId != accounts.user?.id) {
      preview = null;
      previewUserId = null;
      changed();
    }
  }

  Future<void> save() async {
    if (!await accounts.draftStore.write(receiptOwner, 'pending', pending))
      throw const DraftStorageFailure(
        'لم يحفظ إيصال الحذف؛ لم نبدأ طلبًا جديدًا.',
      );
  }

  Future<void> restore() async {
    loading = true;
    error = null;
    changed();
    try {
      final data = await accounts.draftStore.read(receiptOwner, 'pending');
      if (disposed) return;
      if (data != null) {
        if (data['userId'] is! String ||
            data['requestId'] is! String ||
            data['receiptToken'] is! String ||
            !RegExp(r'^[a-f0-9-]{36}$').hasMatch(data['userId'] as String) ||
            !RegExp(r'^[a-f0-9-]{36}$').hasMatch(data['requestId'] as String) ||
            !RegExp(
              r'^[A-Za-z0-9_-]{43}$',
            ).hasMatch(data['receiptToken'] as String)) {
          throw const DraftStorageFailure(
            'إيصال الحذف المحفوظ غير صالح؛ لم نرسل أي طلب.',
          );
        }
        pending = data;
        status = (data['status'] as Map?)?.cast<String, dynamic>();
      }
      ready = true;
      if (accepted) await cleanLocal();
      if (accounts.user != null && !accepted) {
        final user = accounts.user!.id, revision = accounts.sessionRevision;
        final data = await accounts.chatRequest(
          'GET',
          '/v1/account/deletion/preview',
        );
        if (accounts.user?.id == user && accounts.sessionRevision == revision) {
          preview = data;
          previewUserId = user;
        }
      }
    } on AccountFailure catch (f) {
      error = f.status == 404
          ? 'حدّث السيرفر إلى 1.0 التجريبية لتفعيل حذف الحساب.'
          : f.message;
    } catch (_) {
      error = 'تعذّر قراءة الإيصال أو حفظه؛ لم نبدأ حذفًا جديدًا.';
    } finally {
      loading = false;
      changed();
    }
  }

  Future<void> cleanLocal() async {
    final id = pending?['userId'];
    if (id is! String || !accepted) return;
    localError = null;
    try {
      await accounts.finishDeletedAccount(
        id,
        sessionFence: pending?['sessionFence'] as String?,
      );
    } catch (_) {
      localError =
          'قُبل الحذف؛ تعذّر مسح الجلسة أو المسودات على هذا الجهاز. أعد تنظيف الجهاز أدناه.';
    }
  }

  Future<void> send(
    String password,
    String confirmation, {
    String? identityToken,
  }) async {
    if (busy || !ready || accepted) return;
    final user = accounts.user?.id, revision = accounts.sessionRevision;
    if (user == null || pending != null && pending!['userId'] != user) {
      error = 'هذا الإيصال لحساب آخر أو الجلسة انتهت. تحقّق منه قبل طلب جديد.';
      changed();
      return;
    }
    if (confirmation != 'حذف حسابي') {
      error = 'اكتب «حذف حسابي» لتأكيد القرار.';
      changed();
      return;
    }
    busy = true;
    error = null;
    changed();
    try {
      pending ??= {
        'requestId': newRequestId(),
        'receiptToken': deletionReceiptToken(),
        'userId': user,
        'sessionFence': accounts.draftSessionFence,
      };
      await save(); // Receipt is durable before the irreversible request.
      final d = await accounts.requestAccountDeletion(
        {
          'requestId': pending!['requestId'],
          'receiptToken': pending!['receiptToken'],
          'password': password,
          if (identityToken != null) 'identityToken': identityToken,
          'confirmation': confirmation,
        },
        user,
        revision,
      );
      await confirm(d);
    } on AccountFailure catch (f) {
      error = f.message;
    } catch (_) {
      error = 'تعذّر تأكيد الحذف. تحقّق بنفس الإيصال قبل طلب آخر.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> confirm(Map<String, dynamic> data) async {
    if (data['accepted'] != true || data['requestId'] != pending?['requestId'])
      throw const AccountFailure('BAD_RECEIPT', 'تعذّر التحقق من إيصال الحذف.');
    status = data;
    pending = {...pending!, 'accepted': true, 'status': data};
    String? warning;
    try {
      await save();
    } catch (_) {
      warning =
          'تأكد قبول الحذف، لكن تعذّر حفظ آخر حالة. الإيصال الأصلي يبقى أداة التحقق.';
    }
    await cleanLocal();
    localError ??= warning;
  }

  Future<void> check() async {
    final p = pending;
    if (busy || p == null) return;
    busy = true;
    error = null;
    changed();
    try {
      await confirm(
        await accounts.api.publicRequest(
          'POST',
          '/v1/account/deletion/status',
          body: {
            'requestId': p['requestId'],
            'receiptToken': p['receiptToken'],
          },
        ),
      );
    } on AccountFailure catch (f) {
      error = f.message;
    } catch (_) {
      error = 'تعذّر التحقق من النتيجة؛ احتفظ بالإيصال وجرّب لاحقًا.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> forget() async {
    if (busy) return;
    busy = true;
    changed();
    try {
      await accounts.draftStore.write(receiptOwner, 'pending', null);
      pending = null;
      status = null;
      error = null;
      localError = null;
    } catch (_) {
      error = 'تعذّر إزالة الإيصال من هذا الجهاز.';
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    disposed = true;
    accounts.removeListener(accountChanged);
    super.dispose();
  }
}
