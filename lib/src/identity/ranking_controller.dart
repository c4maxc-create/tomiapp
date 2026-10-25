import 'dart:async';

import 'package:flutter/foundation.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';

class RankingController extends ChangeNotifier {
  RankingController(this.accounts, {this.roomId})
    : session = accounts.sessionRevision,
      owner = accounts.user?.id {
    if (accounts.realtimeEnabled) {
      updates = accounts.chats.realtimeEvents.stream.listen((event) {
        if (event['type'] == 'voice_room.changed' &&
            (roomId == null || event['roomId'] == roomId)) {
          debounce?.cancel();
          debounce = Timer(
            const Duration(milliseconds: 120),
            () => unawaited(load(quiet: true)),
          );
        }
      });
      refresh = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(load(quiet: true)),
      );
    }
  }
  Timer? refresh, debounce, boundary;
  StreamSubscription<Map<String, dynamic>>? updates;
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

  Future<void> load({String? selected, bool quiet = false}) async {
    if (!current || quiet && loading) return;
    if (selected != null) period = selected;
    final e = ++epoch;
    loading = true;
    error = null;
    if (selected != null || !quiet) data = null;
    notify();
    try {
      final d = await accounts.chatRequest(
        'GET',
        roomId == null ? '/v1/community/ranking' : '/v1/rooms/$roomId/ranking',
        query: {'period': period},
      );
      if (!current || e != epoch) return;
      data = d;
      boundary?.cancel();
      final until = DateTime.tryParse(d['until'] as String? ?? ''),
          server = DateTime.tryParse(d['serverTime'] as String? ?? '');
      if (accounts.realtimeEnabled && until != null && server != null) {
        final delay =
            until.difference(server) + const Duration(milliseconds: 100);
        boundary = Timer(
          delay.isNegative ? Duration.zero : delay,
          () => unawaited(load(quiet: true)),
        );
      }
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
    refresh?.cancel();
    debounce?.cancel();
    boundary?.cancel();
    unawaited(updates?.cancel());
    super.dispose();
  }
}
