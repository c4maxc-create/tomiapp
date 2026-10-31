import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import 'pending_store.dart';
import 'roulette_page.dart' show rouletteRequestId;

class LiveRouletteController extends ChangeNotifier {
  LiveRouletteController(this.accounts, this.roomId) {
    accountId = accounts.user?.id ?? '';
    session = accounts.sessionRevision;
    events = accounts.chats.realtimeEvents.stream.listen((e) {
      if (e['type'] == 'roulette.live' && foreground) unawaited(load());
    });
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (foreground) unawaited(load());
    });
    unawaited(restore());
  }
  final AccountController accounts;
  final String roomId;
  late final String accountId;
  late final int session;
  late final StreamSubscription<Map<String, dynamic>> events;
  Timer? timer;
  Map<String, dynamic>? state, pending;
  int denomination = 20, generation = 0, offset = 0;
  bool loading = true, busy = false, disposed = false, foreground = true, ready = false;
  String? error;
  bool get current => !disposed && accountId.isNotEmpty && accounts.user?.id == accountId && accounts.sessionRevision == session;
  String get key => 'tomi.live.roulette.${accounts.api.baseUrl}.$accountId';
  String get path => '/v1/rooms/$roomId/live-roulette';
  int get serverNow => DateTime.now().millisecondsSinceEpoch + offset;
  bool get canBet => current && ready && !busy && pending == null && state?['allowed'] == true && state?['phase'] == 'betting' && serverNow < (state!['bettingEndsAt'] as num).toInt();
  void notify() { if (current) notifyListeners(); }
  Future<void> restore() async {
    try {
      final prefs = await RoulettePendingStore.getInstance(), raw = await prefs.getString(key);
      if (!current) return;
      if (raw != null) pending = (jsonDecode(raw) as Map).cast<String, dynamic>();
      ready = true;
      await load();
    } catch (_) {
      if (current) { error = 'تعذّر قراءة المحاولة المحفوظة؛ أعد فتح اللعبة.'; loading = false; notify(); }
    }
  }
  void apply(Map<String, dynamic> value) {
    final revision = (value['revision'] as num).toInt();
    if (state != null && revision < (state!['revision'] as num).toInt()) return;
    offset = (value['serverTime'] as num).toInt() - DateTime.now().millisecondsSinceEpoch;
    state = value;
  }
  Future<void> load() async {
    if (!current || !ready || busy || refreshing) return;
    refreshing = true;
    final stamp = generation;
    try {
      final result = await accounts.chatRequest('GET', path);
      if (!current || stamp != generation) return;
      apply(result);
      if (pending == null) error = null;
    } on AccountFailure catch (f) {
      if (current && stamp == generation) error = f.message;
    } catch (_) {
      if (current && stamp == generation) error = 'تعذّر تحديث الجولة؛ نحاول مجددًا.';
    } finally {
      refreshing = false;
      if (current && stamp == generation) { loading = false; notify(); }
    }
  }
  bool refreshing = false;
  void lifecycle(bool active) {
    foreground = active;
    if (active) unawaited(load());
  }
  void choose(int value) { if (busy || pending != null) return; denomination = value; notify(); }
  Future<void> bet(int slot) async {
    if (!canBet) return;
    pending = {'requestId': rouletteRequestId(), 'roundId': state!['roundId'], 'chips': [{'slot': slot, 'denomination': denomination}]};
    await submit();
  }
  Future<void> repeat() async {
    if (!canBet || (state!['lastBets'] as List).isEmpty) return;
    pending = {'requestId': rouletteRequestId(), 'roundId': state!['roundId'], 'repeat': true};
    await submit();
  }
  Future<void> submit() async {
    if (!current || busy || pending == null) return;
    busy = true; error = null; generation++; notify();
    try {
      final prefs = await RoulettePendingStore.getInstance();
      if (!current) return;
      if (!await prefs.setString(key, jsonEncode(pending))) throw StateError('Intent not saved');
      if (!current) return;
      final result = await accounts.chatRequest('POST', '$path/bet', body: Map<String,dynamic>.from(pending!));
      if (!current) return;
      apply((result['state'] as Map).cast<String,dynamic>());
      await prefs.remove(key);
      if (!current) return;
      pending = null;
      accounts.voiceRooms.applyWallet({'coins': state!['coins'], 'nextClaim': accounts.voiceRooms.nextClaim});
      accounts.voiceRooms.notify();
    } on AccountFailure catch (f) {
      if (!current) return;
      // Membership loss can hide a previously accepted receipt. Keep it until
      // the same account enters a room and explicitly reconciles the request.
      if (f.status >= 400 && f.status < 500 && f.code != 'ROOM_MEMBERSHIP' && f.status != 401) {
        final prefs = await RoulettePendingStore.getInstance();
        await prefs.remove(key);
        if (!current) return;
        pending = null;
      }
      error = f.message;
    } catch (_) {
      if (current) error = 'لم نتأكد من الرد؛ اضغط استعادة الرهان للتحقق من نفس المحاولة.';
    } finally {
      if (current) { busy = false; notify(); if (pending == null) unawaited(load()); }
    }
  }
  Future<Map<String,dynamic>> leaderboard() => accounts.chatRequest('GET', '$path/leaderboard');
  @override
  void dispose() {
    disposed = true; generation++; timer?.cancel(); unawaited(events.cancel()); super.dispose();
  }
}
