import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import 'pending_store.dart';
import 'roulette_page.dart' show rouletteRequestId;

class LiveRouletteController extends ChangeNotifier {
  LiveRouletteController(this.accounts, this.roomId) {
    accountId = accounts.user?.id ?? '';
    session = accounts.sessionRevision;
    accounts.addListener(accountChanged);
    events = accounts.chats.realtimeEvents.stream.listen((e) {
      if (e['type'] == 'roulette.live') scheduleLoad();
    });
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (foreground) unawaited(load());
    });
    unawaited(restore());
  }
  final AccountController accounts;
  final String? roomId;
  late final String accountId;
  late final int session;
  late final StreamSubscription<Map<String, dynamic>> events;
  final Stopwatch watch = Stopwatch()..start();
  Timer? timer, refreshTimer;
  Map<String, dynamic>? state, pending;
  int denomination = 20, generation = 0;
  int clockAnchor = DateTime.now().millisecondsSinceEpoch, anchorElapsed = 0;
  int lastNow = 0;
  bool clockReady = false, invalidated = false;
  bool loading = true, busy = false, disposed = false, foreground = true, ready = false;
  bool refreshing = false, refreshQueued = false;
  String? error;
  bool get current => !disposed && !invalidated && accountId.isNotEmpty && accounts.user?.id == accountId && accounts.sessionRevision == session;
  String get key => 'tomi.live.roulette.${accounts.api.baseUrl}.$accountId';
  String get path => roomId == null ? '/v1/games/live-roulette' : '/v1/rooms/$roomId/live-roulette';
  int get serverNow {
    lastNow = math.max(lastNow, clockAnchor + watch.elapsedMilliseconds - anchorElapsed);
    return lastNow;
  }
  bool get canBet => current && ready && !busy && pending == null && state?['allowed'] == true && state?['phase'] == 'betting' && serverNow < (state!['bettingEndsAt'] as num).toInt();
  void notify() { if (current) notifyListeners(); }
  void accountChanged() {
    if (disposed || invalidated || current) return;
    invalidated = true;
    state = null; ready = false; loading = false; busy = false;
    timer?.cancel(); refreshTimer?.cancel();
    error = 'انتهت جلسة الحساب؛ أغلق اللعبة وسجّل الدخول مجددًا.';
    notifyListeners();
  }
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
  bool apply(Map<String, dynamic> value, {int? sentAt}) {
    final revision = (value['revision'] as num).toInt();
    if (state != null && revision < (state!['revision'] as num).toInt()) return false;
    final received = watch.elapsedMilliseconds;
    final travel = sentAt == null ? 0 : ((received - sentAt).clamp(0, 1000) ~/ 2);
    final estimated = (value['serverTime'] as num).toInt() + travel;
    if (!clockReady) { lastNow = estimated; clockReady = true; }
    // Stopwatch avoids device wall-clock changes; reads never move backwards.
    clockAnchor = estimated; anchorElapsed = received;
    state = value;
    return true;
  }
  void scheduleLoad() {
    if (!current || !foreground || !ready) return;
    if (busy || refreshing) { refreshQueued = true; return; }
    refreshTimer ??= Timer(const Duration(milliseconds: 120), () {
      refreshTimer = null;
      if (foreground) unawaited(load());
    });
  }
  Future<void> load() async {
    if (!current || !ready || !foreground) return;
    if (busy || refreshing) { refreshQueued = true; return; }
    refreshing = true; refreshQueued = false;
    final stamp = generation, sentAt = watch.elapsedMilliseconds;
    try {
      final result = await accounts.chatRequest('GET', path);
      if (!current || stamp != generation) return;
      apply(result, sentAt: sentAt);
      if (pending == null) error = null;
    } on AccountFailure catch (f) {
      if (current && stamp == generation) error = f.message;
    } catch (_) {
      if (current && stamp == generation) error = 'تعذّر تحديث الجولة؛ نحاول مجددًا.';
    } finally {
      refreshing = false;
      if (current) {
        if (stamp == generation) { loading = false; notify(); }
        if (refreshQueued) scheduleLoad();
      }
    }
  }
  void lifecycle(bool active) {
    foreground = active;
    if (!active) { refreshTimer?.cancel(); refreshTimer = null; }
    else unawaited(load());
  }
  void choose(int value) {
    if (!current || busy || pending != null || !const [20,100,1000,5000].contains(value)) return;
    denomination = value; notify();
  }
  Future<void> bet(int slot) async {
    if (!canBet || slot < 0 || slot > 7) return;
    pending = {'requestId': rouletteRequestId(), 'roundId': state!['roundId'], 'chips': [{'slot': slot, 'denomination': denomination}]};
    await submit();
  }
  Future<void> repeat() async {
    if (!canBet || (state!['lastBets'] as List).isEmpty) return;
    pending = {'requestId': rouletteRequestId(), 'roundId': state!['roundId'], 'repeat': true};
    await submit();
  }
  Future<void> removeSaved(RoulettePendingStore store, String requestId) async {
    final raw = await store.getString(key);
    if (raw != null && (jsonDecode(raw) as Map)['requestId'] == requestId) await store.remove(key);
  }
  Future<void> submit() async {
    if (!current || busy || pending == null) return;
    final intent = Map<String,dynamic>.from(pending!), requestId = pending!['requestId'] as String;
    busy = true; error = null; generation++; notify();
    var accepted = false;
    try {
      final prefs = await RoulettePendingStore.getInstance();
      if (!current) return;
      if (!await prefs.setString(key, jsonEncode(intent))) throw StateError('Intent not saved');
      if (!current) return;
      final sentAt = watch.elapsedMilliseconds;
      final result = await accounts.chatRequest('POST', '$path/bet', body: intent);
      if (!current) return;
      apply((result['state'] as Map).cast<String,dynamic>(), sentAt: sentAt);
      await removeSaved(prefs, requestId);
      if (!current) return;
      pending = null; accepted = true;
      accounts.voiceRooms.applyWallet({'coins': state!['coins'], 'nextClaim': accounts.voiceRooms.nextClaim});
      accounts.voiceRooms.notify();
    } on AccountFailure catch (f) {
      if (!current) return;
      // Auth, membership and rate limits may hide an already accepted receipt.
      // Only a definitive rejection after receipt lookup releases the intent.
      if (const {'ROULETTE_CLOSED','INSUFFICIENT_COINS','ROULETTE_CHIPS','ROULETTE_ACCESS','VALIDATION'}.contains(f.code)) {
        final prefs = await RoulettePendingStore.getInstance();
        await removeSaved(prefs, requestId);
        if (!current) return;
        pending = null;
      }
      error = f.message;
    } catch (_) {
      if (current) error = 'لم نتأكد من الرد؛ استعد الرهان للتحقق من نفس المحاولة.';
    } finally {
      if (current) {
        busy = false; notify();
        if (refreshQueued) scheduleLoad();
        else if (!accepted && pending == null) unawaited(load());
      }
    }
  }
  Future<Map<String,dynamic>> leaderboard() => accounts.chatRequest('GET', '$path/leaderboard');
  @override
  void dispose() {
    disposed = true; generation++; timer?.cancel(); refreshTimer?.cancel();
    accounts.removeListener(accountChanged);
    unawaited(events.cancel()); watch.stop(); super.dispose();
  }
}
