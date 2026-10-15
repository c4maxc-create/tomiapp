import 'dart:async';
import 'package:flutter/widgets.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../messaging/audio_focus.dart';
import '../social/social_models.dart';
import 'room_audio.dart';
import 'room_models.dart';

class VoiceRoomsController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceRoomsController({
    required this.accounts,
    RoomAudio Function()? audioFactory,
    this.autoPoll = true,
  }) : audioFactory = audioFactory ?? LiveKitRoomAudio.new {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    accountChanged();
  }
  final AccountController accounts;
  final RoomAudio Function() audioFactory;
  final bool autoPoll;
  final rooms = <VoiceRoom>[];
  VoiceRoom? active;
  RoomAudio? audio;
  String? error, notice, identity, sessionKey, nextBefore, ownedRoomId;
  bool configured = false,
      loading = false,
      busy = false,
      joining = false,
      micBusy = false,
      connected = false,
      reconnecting = false,
      mediaReconnecting = false,
      speakerOn = true,
      foreground = true,
      disposed = false,
      syncing = false;
  int generation = 0;
  Timer? poll, reconnectDeadline;
  StreamSubscription<Map<String, dynamic>>? subscription;
  DateTime lastSync = DateTime.now(),
      lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> releaseTail = Future.value();
  bool get inRoom => active != null || joining;
  VoiceMember? get me => active?.member(accounts.user?.id);
  bool get manage => me?.role == 'owner' || me?.role == 'moderator';
  bool get microphoneOn => audio?.micEnabled == true;
  bool get canUseMic =>
      connected &&
      me?.seat != null &&
      me?.micAllowed == true &&
      audio?.canPublish == true;
  bool valid(int gen) => !disposed && generation == gen && sessionKey != null;
  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => accounts.chatRequest(method, path, body: body, query: query);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      request('POST', path, body: body);
  void accountChanged() {
    final key =
        accounts.phase == AccountPhase.signedIn &&
            accounts.pendingRecoveryCode == null
        ? '${accounts.user!.id}:${accounts.sessionRevision}'
        : null;
    if (disposed || key == sessionKey) return;
    sessionKey = key;
    generation++;
    poll?.cancel();
    release();
    active = null;
    identity = null;
    rooms.clear();
    nextBefore = null;
    ownedRoomId = null;
    busy = false;
    joining = false;
    syncing = false;
    loading = false;
    configured = false;
    error = null;
    notice = null;
    if (key != null && autoPoll)
      poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(tick()),
      );
    notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    foreground = state == AppLifecycleState.resumed;
    if (!foreground && inRoom)
      unawaited(leave(message: 'غادرت الغرفة عند مغادرة التطبيق.'));
    else if (foreground)
      unawaited(tick());
  }

  Future<void> load({bool more = false}) async {
    if (loading || disposed || sessionKey == null || more && nextBefore == null)
      return;
    final gen = generation;
    loading = true;
    error = null;
    notify();
    try {
      final d = await request(
        'GET',
        '/v1/rooms',
        query: more ? {'before': nextBefore!} : null,
      );
      if (!valid(gen)) return;
      configured = d['configured'] == true;
      ownedRoomId = d['ownedRoomId'] as String?;
      final items = (d['rooms'] as List).map(
        (v) => VoiceRoom(v as Map<String, dynamic>),
      );
      if (!more) rooms.clear();
      for (final r in items) {
        rooms.removeWhere((old) => old.id == r.id);
        rooms.add(r);
      }
      nextBefore = d['nextBefore'] as String?;
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تحميل الغرف؛ جرّب مرة ثانية.';
    } finally {
      if (valid(gen)) {
        loading = false;
        notify();
      }
    }
  }

  Future<String?> create(String title, int capacity, int seats) async {
    if (busy || inRoom || sessionKey == null) return null;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    final requestId = newRequestId();
    try {
      Map<String, dynamic> d;
      try {
        d = await post('/v1/rooms', {
          'requestId': requestId,
          'title': title.trim(),
          'capacity': capacity,
          'seatCount': seats,
        });
      } on AccountFailure catch (e) {
        if (e.code != 'NETWORK') rethrow;
        d = await post('/v1/rooms', {
          'requestId': requestId,
          'title': title.trim(),
          'capacity': capacity,
          'seatCount': seats,
        });
      }
      if (!valid(gen)) return null;
      final r = VoiceRoom(d['room'] as Map<String, dynamic>);
      ownedRoomId = r.id;
      rooms.removeWhere((v) => v.id == r.id);
      rooms.insert(0, r);
      return r.id;
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
      return null;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر إنشاء الغرفة؛ جرّب مرة ثانية.';
      return null;
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> cleanupGrant(
    String roomId,
    String grantIdentity,
    String? user,
    int revision,
  ) async {
    if (accounts.user?.id != user || accounts.sessionRevision != revision)
      return;
    try {
      await post('/v1/rooms/$roomId/leave', {'identity': grantIdentity});
    } catch (_) {}
  }

  Future<bool> join(String roomId) async {
    if (disposed || busy || inRoom || sessionKey == null || !foreground)
      return false;
    if (accounts.calls.busy || accounts.calls.active?.ended == false) {
      error = 'أنه المكالمة الخاصة قبل دخول الغرفة.';
      notify();
      return false;
    }
    final gen = ++generation,
        user = accounts.user?.id,
        revision = accounts.sessionRevision;
    busy = true;
    joining = true;
    syncing = false;
    error = null;
    notice = null;
    notify();
    Map<String, dynamic>? connection;
    try {
      await releaseTail;
      await accounts.calls.releaseTail;
      await stopVoiceForCall();
      if (!valid(gen) || !foreground) return false;
      Map<String, dynamic> d;
      try {
        d = await post('/v1/rooms/$roomId/join', {});
      } on AccountFailure catch (e) {
        if (e.code != 'NETWORK') rethrow;
        d = await post('/v1/rooms/$roomId/join', {});
      }
      connection = d['connection'] as Map<String, dynamic>;
      if (!valid(gen) || !foreground) {
        await cleanupGrant(
          roomId,
          connection['identity'] as String,
          user,
          revision,
        );
        return false;
      }
      identity = connection['identity'] as String;
      active = VoiceRoom(d['room'] as Map<String, dynamic>);
      if (active!.closed || !active!.canControl || me?.identity != identity) {
        throw const AccountFailure(
          'ROOM_CONNECTION_CHANGED',
          'تغيّرت عضوية الغرفة؛ حدّث القائمة وجرّب ثانية.',
        );
      }
      final engine = audioFactory();
      audio = engine;
      subscription = engine.events.listen((e) {
        if (!valid(gen) || audio != engine) return;
        switch (e['type']) {
          case 'disconnected':
            unawaited(leave(message: 'انتهى اتصال الغرفة.'));
            break;
          case 'reconnecting':
            reconnecting = true;
            mediaReconnecting = true;
            reconnectDeadline ??= Timer(const Duration(seconds: 25), () {
              if (valid(gen))
                unawaited(
                  leave(message: 'انقطع صوت الغرفة؛ تگدر تدخل مرة ثانية.'),
                );
            });
            break;
          case 'reconnected':
            reconnecting = false;
            mediaReconnecting = false;
            reconnectDeadline?.cancel();
            reconnectDeadline = null;
            break;
        }
        if (engine.micEnabled && !canUseMic)
          unawaited(engine.microphone(false).catchError((Object _) {}));
        notify();
      });
      await engine.connect(connection);
      if (!valid(gen) || !foreground) return false;
      connected = true;
      speakerOn = true;
      lastSync = DateTime.now();
      lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
      await tick();
      return valid(gen) && active != null;
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen))
        error = 'تعذّر الاتصال بصوت الغرفة؛ تأكد من الإنترنت وجرّب ثانية.';
    } finally {
      if (valid(gen)) {
        if (!connected) {
          release();
          active = null;
          identity = null;
          if (connection != null)
            unawaited(
              cleanupGrant(
                roomId,
                connection['identity'] as String,
                user,
                revision,
              ),
            );
        }
        busy = false;
        joining = false;
        notify();
      }
    }
    return false;
  }

  Future<void> apply(VoiceRoom room, int gen) async {
    if (!valid(gen) ||
        active?.id != room.id ||
        room.revision < (active?.revision ?? 0))
      return;
    active = room;
    if (room.closed ||
        !room.canControl ||
        room.member(accounts.user?.id)?.identity != identity) {
      await leave(
        message: room.closed
            ? (room.pending
                  ? 'انغلقت الغرفة؛ إكمال إيقاف الصوت قيد التنفيذ.'
                  : 'انغلقت الغرفة.')
            : 'غادرت الغرفة أو أزالتك الإدارة.',
      );
      return;
    }
    if (me?.seat == null || me?.micAllowed != true) {
      final engine = audio;
      if (engine != null)
        try {
          await engine.microphone(false);
        } catch (_) {
          await leave(message: 'توقف اتصال المايك.');
        }
    }
    notify();
  }

  Future<void> tick() async {
    if (disposed || !foreground || active == null || !connected || syncing)
      return;
    final gen = generation, r = active!;
    syncing = true;
    try {
      final beat = DateTime.now().difference(lastHeartbeat).inSeconds >= 10;
      final d = beat
          ? await post('/v1/rooms/${r.id}/heartbeat', {'identity': identity})
          : await request('GET', '/v1/rooms/${r.id}');
      if (!valid(gen)) return;
      if (beat) lastHeartbeat = DateTime.now();
      lastSync = DateTime.now();
      reconnecting = mediaReconnecting;
      await apply(VoiceRoom(d['room'] as Map<String, dynamic>), gen);
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        if (e.status == 403 ||
            e.status == 404 ||
            e.status == 409 ||
            e.status == 410)
          await leave(message: e.message);
        else {
          reconnecting = true;
          if (DateTime.now().difference(lastSync).inSeconds >= 25)
            await leave(message: 'انقطع الاتصال بالغرفة؛ تگدر تدخل مرة ثانية.');
        }
      }
    } catch (_) {
      if (valid(gen)) {
        reconnecting = true;
        if (DateTime.now().difference(lastSync).inSeconds >= 25)
          await leave(message: 'تعذّر تحديث الغرفة؛ تگدر تدخل مرة ثانية.');
      }
    } finally {
      if (valid(gen)) {
        syncing = false;
        notify();
      }
    }
  }

  Future<void> action(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    if (busy || active == null || disposed) return;
    final gen = generation, r = active!;
    busy = true;
    error = null;
    notify();
    try {
      final d = await post('/v1/rooms/${r.id}/$action', body);
      await apply(VoiceRoom(d['room'] as Map<String, dynamic>), gen);
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تنفيذ الطلب؛ حدّث الغرفة وجرّب ثانية.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> moderate(VoiceMember member, String operation) => action(
    'moderate',
    body: {'targetId': member.user.id, 'operation': operation},
  );
  Future<void> toggleMicrophone() async {
    if (micBusy || audio == null || !connected) return;
    final engine = audio!, gen = generation, enable = !engine.micEnabled;
    if (enable && !canUseMic) {
      error = 'انتظر الموافقة على المايك أو اكتمال تطبيق الصلاحية.';
      notify();
      return;
    }
    micBusy = true;
    error = null;
    notify();
    try {
      if (enable) await stopVoiceForCall();
      if (!valid(gen) || audio != engine) return;
      await engine.microphone(enable);
      // Permission dialogs can complete after demotion/background/leave.
      if (!valid(gen) || audio != engine || enable && !canUseMic)
        await engine.microphone(false);
    } catch (_) {
      if (valid(gen))
        error = 'تعذّر فتح المايك؛ اسمح بالمايك من إعدادات الهاتف وجرّب ثانية.';
    } finally {
      if (valid(gen)) {
        micBusy = false;
        notify();
      }
    }
  }

  Future<void> toggleSpeaker() async {
    if (!connected || audio == null) return;
    try {
      await audio!.speaker(!speakerOn);
      speakerOn = !speakerOn;
      notify();
    } catch (_) {
      error = 'تعذّر تغيير مخرج الصوت.';
      notify();
    }
  }

  Future<void> release() {
    final engine = audio;
    audio = null;
    unawaited(subscription?.cancel());
    subscription = null;
    connected = false;
    reconnecting = false;
    mediaReconnecting = false;
    reconnectDeadline?.cancel();
    reconnectDeadline = null;
    micBusy = false;
    releaseTail = releaseTail.catchError((Object _) {}).then((_) async {
      try {
        await engine?.dispose();
      } catch (_) {}
    });
    return releaseTail;
  }

  Future<void> leave({String? message}) async {
    final r = active,
        oldIdentity = identity,
        user = accounts.user?.id,
        revision = accounts.sessionRevision;
    generation++;
    active = null;
    identity = null;
    joining = false;
    busy = false;
    syncing = false;
    loading = false;
    notice = message;
    await release();
    notify();
    if (r != null && oldIdentity != null)
      await cleanupGrant(r.id, oldIdentity, user, revision);
  }

  @override
  void dispose() {
    if (disposed) return;
    final r = active, oldIdentity = identity;
    if (r != null && oldIdentity != null)
      unawaited(
        cleanupGrant(
          r.id,
          oldIdentity,
          accounts.user?.id,
          accounts.sessionRevision,
        ),
      );
    disposed = true;
    generation++;
    poll?.cancel();
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }
}
