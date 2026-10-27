import '../messaging/draft_store.dart';

import 'package:flutter/foundation.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../social/social_models.dart';

const reportReasonLabels = {
  'spam': 'إزعاج أو رسائل مكررة',
  'harassment': 'إساءة أو تحرش',
  'unsafe': 'محتوى غير آمن',
  'impersonation': 'انتحال شخصية',
  'other': 'سبب آخر',
};
const reportStatusLabels = {
  'open': 'بانتظار المراجعة',
  'reviewing': 'قيد المراجعة',
  'resolved': 'تمت المعالجة',
  'dismissed': 'أُغلِق بعد المراجعة',
};
const staffPermissionLabels = {
  'reports': 'مراجعة البلاغات',
  'accounts': 'البحث في الحسابات',
  'bans': 'الحظر وإلغاء الحظر',
  'posts': 'إدارة المنشورات',
  'rooms': 'إدارة الغرف',
  'metrics': 'إحصاءات التطبيق',
  'audit': 'قراءة سجل الإدارة',
};

const adminActionLabels = {
  'add_coins': 'إضافة كوينز',
  'withdraw_coins': 'سحب كوينز',
  'add_charisma': 'إضافة كارزما',
  'withdraw_charisma': 'سحب كارزما',
  'mark_special': 'تمييز الحساب',
  'unmark_special': 'إلغاء تمييز الحساب',
  'create_account': 'إنشاء حساب جديد',
  'review_report': 'حفظ مراجعة البلاغ',
  'hide_post': 'إخفاء المنشور',
  'restore_post': 'استعادة المنشور',
  'close_room': 'إغلاق الغرفة',
  'suspend_user': 'إيقاف الحساب',
  'restore_user': 'إلغاء إيقاف الحساب',
  'grant_moderator': 'تعيين مشرف للتطبيق',
  'revoke_moderator': 'إلغاء إشراف التطبيق',
};

class ModerationController extends ChangeNotifier {
  ModerationController(this.accounts)
    : owner = accounts.user?.id,
      session = accounts.sessionRevision {
    accounts.addListener(accountChanged);
  }
  final AccountController accounts;
  final String? owner;
  final int session;
  Map<String, dynamic> access = {}, metrics = {};
  Map<String, dynamic>? detail, pendingCommand;
  String? detailId, error, detailError, notice, nextBefore, createdRecoveryCode;
  bool pendingRestored = false;
  String section = 'reports', filter = 'open', query = '';
  final items = <Map<String, dynamic>>[];
  int epoch = 0, detailEpoch = 0, accessEpoch = 0;
  bool loading = false,
      accessLoading = false,
      detailLoading = false,
      acting = false,
      disposed = false;
  bool get current =>
      !disposed &&
      owner != null &&
      accounts.user?.id == owner &&
      accounts.sessionRevision == session;
  String get role => access['role'] as String? ?? 'member';
  bool can(String permission) =>
      role == 'owner' ||
      role == 'moderator' &&
          (access['permissions'] as List? ??
                  staffPermissionLabels.keys.where((p) => p != 'bans').toList())
              .contains(permission);
  bool sectionAllowed(String value) => value == 'mine' || value == 'staff'
      ? value == 'mine' || role == 'owner'
      : (value == 'users' ? (can('accounts') || can('bans')) : can(value));
  bool get staff => role == 'owner' || role == 'moderator';
  bool get actionLocked => acting || pendingCommand != null || !current;
  void notify() {
    if (!disposed) notifyListeners();
  }

  void accountChanged() {
    if (current || disposed) return;
    epoch++;
    detailEpoch++;
    accessEpoch++;
    access = {};
    metrics = {};
    detail = null;
    pendingCommand = null;
    createdRecoveryCode = null;
    items.clear();
    nextBefore = null;
    loading = false;
    accessLoading = false;
    detailLoading = false;
    acting = false;
    error = 'انتهت جلسة الحساب.';
    notify();
  }

  Future<void> loadAccess() async {
    if (!current || accessLoading) return;
    final e = ++accessEpoch;
    accessLoading = true;
    notify();
    try {
      final d = await accounts.chatRequest('GET', '/v1/moderation/access');
      if (current && e == accessEpoch) {
        access = d;
        if (!staff)
          revokeView();
        else {
          await restorePending();
          if (!can('reports')) {
            detail = null;
            detailId = null;
            detailEpoch++;
          }
          if (!sectionAllowed(section))
            section = [
              'reports',
              'users',
              'posts',
              'rooms',
              'metrics',
              'audit',
              'staff',
            ].firstWhere(sectionAllowed, orElse: () => 'reports');
        }
      }
    } on AccountFailure catch (f) {
      if (current && e == accessEpoch)
        error = f.status == 404
            ? 'حدّث السيرفر إلى 0.12 لتفعيل البلاغات والإدارة.'
            : f.message;
    } catch (_) {
      if (current && e == accessEpoch)
        error = 'تعذّر التحقق من صلاحية الإدارة.';
    } finally {
      if (current && e == accessEpoch) {
        accessLoading = false;
        notify();
      }
    }
  }

  Future<void> load({
    String? selected,
    String? selectedFilter,
    String? search,
    bool more = false,
  }) async {
    if (!current || more && (loading || nextBefore == null)) return;
    if (selected != null && selected != section) {
      section = selected;
      filter = selected == 'reports' || selected == 'rooms' ? 'open' : 'all';
      query = '';
      more = false;
    }
    if (selectedFilter != null) {
      filter = selectedFilter;
      more = false;
    }
    if (search != null) {
      query = search;
      more = false;
    }
    final e = ++epoch;
    loading = true;
    error = null;
    if (!more) {
      items.clear();
      nextBefore = null;
      metrics = {};
    }
    notify();
    try {
      final d = await accounts.chatRequest(
        'GET',
        section == 'mine' ? '/v1/reports' : '/v1/admin/$section',
        query: {
          if (more) 'before': nextBefore!,
          if (section == 'reports') 'status': filter,
          if (section == 'rooms') 'state': filter,
          if ((section == 'users' || section == 'staff') && query.isNotEmpty)
            'q': query,
        },
      );
      if (!current || e != epoch) return;
      if (section == 'metrics')
        metrics = d;
      else {
        final rows = (d['items'] as List).cast<Map<String, dynamic>>();
        for (final row in rows) {
          final id = row['id'] ?? (row['user'] as Map?)?['id'];
          items.removeWhere(
            (old) => (old['id'] ?? (old['user'] as Map?)?['id']) == id,
          );
          items.add(row);
        }
        nextBefore = d['nextBefore'] as String?;
      }
    } on AccountFailure catch (f) {
      if (current && e == epoch) {
        error = f.status == 404
            ? 'حدّث السيرفر إلى 0.12 لعرض هذه الصفحة.'
            : f.message;
        if (f.status == 403 && section != 'mine') {
          if (f.code == 'ADMIN_PERMISSION')
            await loadAccess();
          else
            revokeView();
        }
      }
    } catch (_) {
      if (current && e == epoch) error = 'تعذّر تحميل البيانات؛ جرّب التحديث.';
    } finally {
      if (current && e == epoch) {
        loading = false;
        notify();
      }
    }
  }

  void revokeView() {
    epoch++;
    detailEpoch++;
    accessEpoch++;
    loading = false;
    detailLoading = false;
    accessLoading = false;
    access = {'role': 'member'};
    createdRecoveryCode = null;
    items.clear();
    detail = null;
    metrics = {};
    pendingCommand = null;
    nextBefore = null;
    notify();
  }

  Future<void> loadDetail(String id) async {
    if (!current) return;
    final e = ++detailEpoch;
    detailId = id;
    detail = null;
    detailError = null;
    detailLoading = true;
    notify();
    try {
      final d = await accounts.chatRequest('GET', '/v1/admin/reports/$id');
      if (current && e == detailEpoch) detail = d;
    } on AccountFailure catch (f) {
      if (current && e == detailEpoch) {
        detailError = f.message;
        if (f.status == 403) {
          if (f.code == 'ADMIN_PERMISSION')
            await loadAccess();
          else
            revokeView();
        }
      }
    } catch (_) {
      if (current && e == detailEpoch) detailError = 'تعذّر تحميل البلاغ.';
    } finally {
      if (current && e == detailEpoch) {
        detailLoading = false;
        notify();
      }
    }
  }

  Future<void> restorePending() async {
    if (pendingRestored || !current) return;
    final key = accounts.draftOwnerId;
    if (key == null)
      throw const DraftStorageFailure('تعذّر فتح سجل إجراء الإدارة.');
    final saved = await accounts.draftStore.read(key, 'admin-action');
    if (!current) return;
    pendingRestored = true;
    pendingCommand ??= saved;
  }

  Future<void> storePending(Map<String, dynamic>? value) async {
    final key = accounts.draftOwnerId;
    if (key == null ||
        !current ||
        !await accounts.draftStore.write(
          key,
          'admin-action',
          value?['action'] == 'create_account' ? null : value,
          valid: () => current,
        )) {
      throw const DraftStorageFailure(
        'تعذّر حفظ إجراء الإدارة؛ أعد التحقق قبل طلب جديد.',
      );
    }
  }

  Future<bool> runCommand(Map<String, dynamic> body) async {
    if (actionLocked) return false;
    try {
      await restorePending();
      if (pendingCommand != null || !current) {
        notify();
        return false;
      }
      pendingCommand = Map<String, dynamic>.unmodifiable({
        ...body,
        'requestId': newRequestId(),
      });
      await storePending(pendingCommand);
      createdRecoveryCode = null;
      return await retryCommand();
    } catch (_) {
      error = 'تعذّر حفظ الطلب؛ لم يبدأ الإجراء. أعد فتح لوحة الإدارة.';
      notify();
      return false;
    }
  }

  Future<bool> retryCommand() async {
    final body = pendingCommand;
    if (!current || acting || body == null) return false;
    acting = true;
    error = null;
    notice = null;
    notify();
    try {
      await storePending(body);
      final d = await accounts.chatRequest(
        'POST',
        '/v1/admin/actions',
        body: body,
      );
      if (!current) return false;
      await storePending(null);
      if (!current) return false;
      pendingCommand = null;
      createdRecoveryCode = d['recoveryCode'] as String?;
      notice = d['applied'] == true
          ? 'تم حفظ الإجراء وسجله.'
          : 'الحالة مطابقة؛ لا يوجد تغيير جديد.';
      final selectedDetail = detailId;
      await load();
      if (selectedDetail != null && current) await loadDetail(selectedDetail);
      return true;
    } on AccountFailure catch (f) {
      if (current) {
        error = f.message;
        if ([400, 401, 403, 404, 409, 410].contains(f.status)) {
          await storePending(null);
          pendingCommand = null;
        }
        if (f.status == 403) {
          if (f.code == 'ADMIN_PERMISSION')
            await loadAccess();
          else
            revokeView();
        }
        if (f.status == 409) {
          final selectedDetail = detailId;
          await load();
          if (selectedDetail != null && current)
            await loadDetail(selectedDetail);
          if (current) error = f.message;
        }
      }
    } catch (_) {
      if (current)
        error = 'تعذّر تأكيد الإجراء. أعد التحقق بنفس الطلب قبل إجراء جديد.';
    } finally {
      if (current) {
        acting = false;
        notify();
      }
    }
    return false;
  }

  Future<void> discardRetry() async {
    if (acting || !current) return;
    pendingCommand = null;
    error = null;
    notice = 'أُلغي تكرار الطلب؛ هذا لا يلغي إجراءً قبله السيرفر.';
    acting = true;
    notify();
    try {
      await storePending(null);
    } catch (_) {
      error = 'تعذّر حذف المحاولة المحفوظة؛ أعد فتح اللوحة.';
    } finally {
      acting = false;
      notify();
    }
  }

  @override
  void dispose() {
    createdRecoveryCode = null;
    disposed = true;
    epoch++;
    detailEpoch++;
    accounts.removeListener(accountChanged);
    super.dispose();
  }
}
