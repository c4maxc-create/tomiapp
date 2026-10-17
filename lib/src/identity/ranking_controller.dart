import 'package:flutter/foundation.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';

class RankingController extends ChangeNotifier {
  RankingController(this.accounts, {this.roomId})
    : session = accounts.sessionRevision,
      owner = accounts.user?.id;
  final AccountController accounts;
  final String? roomId, owner;
  final int session;
  String period = 'all';
  Map<String, dynamic>? data;
  String? error;
  bool loading = false, disposed = false;
  int epoch = 0;
  bool get current =>
      !disposed &&
      accounts.user?.id == owner &&
      accounts.sessionRevision == session;
  void notify() {
    if (current) notifyListeners();
  }

  Future<void> load({String? selected}) async {
    if (!current) return;
    if (selected != null) period = selected;
    final e = ++epoch;
    loading = true;
    error = null;
    data = null;
    notify();
    try {
      final d = await accounts.chatRequest(
        'GET',
        roomId == null ? '/v1/community/ranking' : '/v1/rooms/$roomId/ranking',
        query: {'period': period},
      );
      if (!current || e != epoch) return;
      data = d;
    } on AccountFailure catch (f) {
      if (current && e == epoch) error = f.message;
    } catch (_) {
      if (current && e == epoch) error = 'تعذّر تحميل ترتيب المساهمين.';
    } finally {
      if (current && e == epoch) {
        loading = false;
        notify();
      }
    }
  }

  List<Map<String, dynamic>> get leaders =>
      (data?['leaders'] as List? ?? []).cast<Map<String, dynamic>>();
  @override
  void dispose() {
    disposed = true;
    epoch++;
    super.dispose();
  }
}
