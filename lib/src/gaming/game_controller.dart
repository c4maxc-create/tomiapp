import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../roulette/roulette_page.dart' show rouletteRequestId;
import 'game_models.dart';

abstract class GameIntentStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SecureGameIntentStore implements GameIntentStore {
  const SecureGameIntentStore();
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> remove(String key) => storage.delete(key: key);
}

class GamesController extends ChangeNotifier with WidgetsBindingObserver {
  GamesController(
    this.accounts, {
    GameIntentStore? intents,
    this.autoPoll = true,
    bool visible = true,
  }) : intents = intents ?? const SecureGameIntentStore(),
       visible = visible,
       owner = accounts.user?.id ?? '',
       session = accounts.sessionRevision {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    events = accounts.chats.realtimeEvents.stream.listen((event) {
      if (event['type'] == 'games.changed' &&
          (match == null || event['matchId'] == match!['id']))
        scheduleLoad();
    });
    if (autoPoll)
      poll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (foreground) unawaited(load());
      });
    unawaited(ready);
  }
  late final Future<void> ready = restore();
  final AccountController accounts;
  final GameIntentStore intents;
  final bool autoPoll;
  final String owner;
  final int session;
  final stopwatch = Stopwatch()..start();
  late final StreamSubscription<Map<String, dynamic>> events;
  Timer? poll, coalesce;
  Map<String, dynamic>? summary, match, pending;
  bool disposed = false, invalidated = false, visible, resumed = true;
  bool loading = false, busy = false, storageReady = false, initialized = false;
  String? error;
  int epoch = 0,
      anchor = DateTime.now().millisecondsSinceEpoch,
      anchorElapsed = 0,
      summaryAt = -15000;
  bool get current =>
      !disposed &&
      !invalidated &&
      owner.isNotEmpty &&
      accounts.user?.id == owner &&
      accounts.sessionRevision == session;
  bool get foreground => current && visible && resumed;
  bool get canAct =>
      current && initialized && storageReady && !busy && pending == null;
  String get storageKey => 'tomi.games.intent.${accounts.api.baseUrl}.$owner';
  int get serverNow => anchor + stopwatch.elapsedMilliseconds - anchorElapsed;
  GameProgress get progress => GameProgress.fromJson(
    (summary?['progress'] as Map?)?.cast<String, dynamic>() ??
        {'xp': accounts.user?.gameProgress.xp ?? 0},
  );
  List<Map<String, dynamic>> get activeMatches =>
      (summary?['activeMatches'] as List? ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
  void notify() {
    if (current) notifyListeners();
  }

  void accountChanged() {
    if (disposed || invalidated || current) return;
    invalidated = true;
    summary = null;
    match = null;
    pending = null;
    busy = false;
    loading = false;
    poll?.cancel();
    coalesce?.cancel();
    error = 'انتهت جلسة الحساب؛ ارجع وسجّل الدخول مجددًا.';
    notifyListeners();
  }

  void setVisible(bool value) {
    final was = foreground;
    visible = value;
    if (was && !value) unawaited(cancelBackgroundSearch());
    if (!was && foreground) scheduleLoad();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    if (!resumed) unawaited(cancelBackgroundSearch());
    if (foreground) scheduleLoad();
  }

  Future<void> restore() async {
    try {
      final raw = await intents.read(storageKey);
      if (!current) return;
      if (raw != null)
        pending = (jsonDecode(raw) as Map).cast<String, dynamic>();
      storageReady = true;
    } catch (_) {
      if (current) error = 'تعذّر حفظ محاولات اللعب على الجهاز؛ أعد فتح القسم.';
    }
    if (!current) return;
    initialized = true;
    notify();
    await load(forceSummary: true);
  }

  void scheduleLoad() {
    if (!foreground || !current || !initialized) return;
    coalesce ??= Timer(const Duration(milliseconds: 100), () {
      coalesce = null;
      unawaited(load());
    });
  }

  void applySummary(Map<String, dynamic> value) {
    summary = value;
    summaryAt = stopwatch.elapsedMilliseconds;
    accounts.applyGameProgress(progress, accountId: owner, session: session);
    if (value['coins'] is num) {
      accounts.voiceRooms.applyWallet({
        'coins': value['coins'],
        'nextClaim': value['nextClaim'] ?? accounts.voiceRooms.nextClaim,
      });
      accounts.voiceRooms.notify();
    }
  }

  void applyMatch(Map<String, dynamic> value) {
    if (match?['id'] == value['id'] &&
        (match!['revision'] as num).toInt() >
            (value['revision'] as num).toInt())
      return;
    match = value;
    anchor = (value['serverTime'] as num?)?.toInt() ?? serverNow;
    anchorElapsed = stopwatch.elapsedMilliseconds;
  }

  Future<void> load({bool forceSummary = false}) async {
    if (!current || !initialized || !foreground || loading || busy) return;
    final e = epoch, id = match?['id'];
    loading = true;
    notify();
    try {
      if (forceSummary ||
          summary == null ||
          id == null ||
          stopwatch.elapsedMilliseconds - summaryAt >= 15000) {
        final value = await accounts.chatRequest('GET', '/v1/games');
        if (!current || e != epoch) return;
        applySummary(value);
      }
      final found = summary?['search'];
      final searchMatch = found is Map && found['status'] == 'matched'
          ? found['matchId']
          : null;
      if (id == null && searchMatch is String) {
        final result = await accounts.chatRequest(
          'GET',
          '/v1/games/matches/$searchMatch',
        );
        if (!current || e != epoch) return;
        applyMatch((result['match'] as Map).cast<String, dynamic>());
      }
      if (id != null) {
        final value = await accounts.chatRequest(
          'GET',
          '/v1/games/matches/$id',
        );
        if (!current || e != epoch) return;
        applyMatch((value['match'] as Map).cast<String, dynamic>());
        if (match?['status'] == 'finished') summaryAt = -15000;
      }
      if (storageReady && pending == null) error = null;
    } on AccountFailure catch (f) {
      if (current && e == epoch)
        error = f.status == 404
            ? 'الألعاب غير متاحة حاليًا؛ تحقق من اتصالك أو حدّث التطبيق.'
            : f.message;
    } catch (_) {
      if (current && e == epoch) error = 'تعذّر تحديث الطاولة؛ أعد المحاولة.';
    } finally {
      if (current) {
        loading = false;
        notify();
      }
    }
  }

  Future<bool> open(String id) async {
    if (!current || busy) return false;
    busy = true;
    final e = ++epoch;
    error = null;
    notify();
    try {
      final value = await accounts.chatRequest('GET', '/v1/games/matches/$id');
      if (!current || e != epoch) return false;
      applyMatch((value['match'] as Map).cast<String, dynamic>());
      return true;
    } on AccountFailure catch (f) {
      if (current) error = f.message;
    } catch (_) {
      if (current) error = 'تعذّر فتح الجولة.';
    } finally {
      if (current) {
        busy = false;
        notify();
      }
    }
    return false;
  }

  Future<void> clearSaved(String requestId) async {
    final raw = await intents.read(storageKey);
    if (raw != null &&
        ((jsonDecode(raw) as Map)['body'] as Map)['requestId'] == requestId)
      await intents.remove(storageKey);
  }

  Future<void> cancelBackgroundSearch() async {
    final queue = summary?['search'];
    if (queue is Map && queue['status'] == 'searching' && canAct)
      await searchGame(queue['kind'] as String, cancel: true);
  }

  Future<void> searchGame(String kind, {bool cancel = false}) async {
    if (!canAct) return;
    busy = true;
    final e = ++epoch;
    error = null;
    notify();
    try {
      final value = await accounts.chatRequest(
        'POST',
        cancel ? '/v1/games/search/cancel' : '/v1/games/search',
        body: {'kind': kind},
      );
      if (!current || e != epoch) return;
      applySummary(value);
      if (value['match'] is Map)
        applyMatch((value['match'] as Map).cast<String, dynamic>());
    } on AccountFailure catch (f) {
      if (current) error = f.message;
    } catch (_) {
      if (current) error = 'تعذّر تحديث البحث؛ أعد المحاولة للتحقق من حالته.';
    } finally {
      if (current) {
        busy = false;
        notify();
        scheduleLoad();
      }
    }
  }

  Future<bool> create(String kind, String mode) =>
      send('/v1/games/matches', {'kind': kind, 'mode': mode});
  Future<bool> join(String code) =>
      send('/v1/games/join', {'code': code.trim().toUpperCase()});
  Future<bool> choose(String choice, int revision) async {
    if (!current || !canAct) return false;
    if (match?['revision'] != revision) {
      error = 'تغيّرت الطاولة؛ اختَر الحركة من الحالة الجديدة.';
      notify();
      return false;
    }
    return act('choose', {'choice': choice});
  }

  Future<bool> act(String type, [Map<String, dynamic> extra = const {}]) async {
    if (match == null) return false;
    return send('/v1/games/matches/${match!['id']}/action', {
      'type': type,
      'expectedRevision': match!['revision'],
      ...extra,
    });
  }

  Future<bool> send(String path, Map<String, dynamic> body) async {
    if (!canAct) return false;
    pending = {
      'path': path,
      'body': {'requestId': rouletteRequestId(), ...body},
    };
    return retryPending();
  }

  Future<bool> retryPending() async {
    if (!current || !initialized || !storageReady || busy || pending == null)
      return false;
    final intent = pending!,
        body = (intent['body'] as Map).cast<String, dynamic>(),
        id = body['requestId'] as String;
    busy = true;
    ++epoch;
    error = null;
    notify();
    try {
      await intents.write(storageKey, jsonEncode(intent));
      if (!current) return false;
      final result = await accounts.chatRequest(
        'POST',
        intent['path'] as String,
        body: body,
      );
      if (!current) return false;
      if (result['match'] is Map)
        applyMatch((result['match'] as Map).cast<String, dynamic>());
      if (result['receipt'] is Map && result['receipt']['left'] == true)
        match = null;
      applySummary(result);
      await clearSaved(id);
      if (!current) return false;
      pending = null;
      return true;
    } on AccountFailure catch (f) {
      if (!current) return false;
      error = f.message;
      if (const {
        'GAME_CHANGED',
        'GAME_CHOICE',
        'GAME_TURN',
        'GAME_CARD',
        'GAME_COLOR',
        'GAME_ACTION',
        'GAME_DRAW',
        'GAME_ENDED',
        'GAME_ACTIVE',
        'GAME_FULL',
        'GAME_STARTED',
        'GAME_NOT_FOUND',
        'GAME_MEMBERSHIP',
        'GAME_HOST',
        'GAME_PLAYERS',
        'GAME_BLOCKED',
        'VALIDATION',
        'REQUEST_CHANGED',
      }.contains(f.code)) {
        try {
          await clearSaved(id);
          if (current) pending = null;
        } catch (_) {
          /* Keep an uncertain durable intent for retry. */
        }
      }
    } catch (_) {
      if (current) error = 'لم نتأكد من الرد؛ اضغط استعادة نفس المحاولة.';
    } finally {
      if (current) {
        busy = false;
        notify();
        scheduleLoad();
      }
    }
    return false;
  }

  @override
  void dispose() {
    disposed = true;
    poll?.cancel();
    coalesce?.cancel();
    ++epoch;
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(events.cancel());
    stopwatch.stop();
    super.dispose();
  }
}
