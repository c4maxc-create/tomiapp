import 'package:flutter/foundation.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import 'identity_models.dart';

class IdentityController extends ChangeNotifier {
  IdentityController(this.accounts)
    : session = accounts.sessionRevision,
      owner = accounts.user?.id;
  final AccountController accounts;
  final int session;
  final String? owner;
  IdentityCatalog? catalog;
  bool loading = false, saving = false, disposed = false;
  String? error;
  int epoch = 0;
  bool get current =>
      !disposed &&
      accounts.user?.id == owner &&
      accounts.sessionRevision == session;
  void notify() {
    if (current) notifyListeners();
  }

  Future<void> load() async {
    if (!current) return;
    final e = ++epoch;
    loading = true;
    error = null;
    notify();
    try {
      final d = await accounts.chatRequest('GET', '/v1/identity/catalog');
      if (!current || e != epoch) return;
      catalog = IdentityCatalog(d);
      await accounts.reloadMe();
    } on AccountFailure catch (f) {
      if (current && e == epoch)
        error = f.status == 404
            ? 'حدّث السيرفر إلى0.11 لتفعيل الهوية.'
            : f.message;
    } catch (_) {
      if (current && e == epoch) error = 'تعذّر تحميل مستويات الهوية.';
    } finally {
      if (current && e == epoch) {
        loading = false;
        notify();
      }
    }
  }

  Future<void> select(String key, String id) async {
    if (!current || saving || loading) return;
    saving = true;
    error = null;
    notify();
    try {
      await accounts.saveIdentity({
        key: id,
        'expectedRevision': accounts.user!.identity.revision,
      });
    } on AccountFailure catch (f) {
      if (current) {
        error = f.message;
        if (f.code == 'IDENTITY_CHANGED') {
          try {
            await accounts.reloadMe();
          } catch (_) {
            if (current)
              error = 'تغيّر اختيارك من جهاز آخر. حدّث الصفحة وحاول مجددًا.';
          }
        }
      }
    } catch (_) {
      if (current) error = 'تعذّر حفظ اختيار الهوية.';
    } finally {
      if (current) {
        saving = false;
        notify();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    epoch++;
    super.dispose();
  }
}
