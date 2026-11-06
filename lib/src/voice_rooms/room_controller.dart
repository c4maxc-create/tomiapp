import 'dart:async';

import 'package:flutter/widgets.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../messaging/audio_focus.dart';
import '../messaging/chat_models.dart';
import '../messaging/draft_store.dart';

import 'dart:typed_data';

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
    roomRealtime = accounts.chats.realtimeEvents.stream.listen((event) {
      if (event['type'] != 'voice_room.changed' ||
          event['roomId'] != active?.id)
        return;
      roomUpdate?.cancel();
      roomUpdate = Timer(
        const Duration(milliseconds: 60),
        () => unawaited(tick()),
      );
    });
  }
  final AccountController accounts;
  final RoomAudio Function() audioFactory;
  final bool autoPoll;
  StreamSubscription<Map<String, dynamic>>? roomRealtime;
  Timer? roomUpdate;
  Map<String, dynamic>? pendingCreation, pendingCosmetic;
  bool commerceReady = false;
  final rooms = <VoiceRoom>[];
  final preferenceBusy = <String>{};
  final preferenceCache = <String, Map<String, dynamic>>{};
  String scope = 'all';
  int listEpoch = 0;
  final gifts = <RoomGift>[];
  int coins = 0;
  bool walletReady = false;
  String? nextClaim;
  bool extrasLoading = false, pickingMedia = false;
  Map<String, dynamic>? pendingGift, pendingMessage;
  String? pendingGiftRoom, pendingMessageRoom;
  PendingChatMessage? roomMedia;
  String roomDraft = '';
  bool roomStorageReady = true,
      giftAttempted = false,
      messageAttempted = false,
      historyLoading = false,
      historyLoaded = false,
      historyWindow = false;
  int? eventsBefore;
  final history = <int, RoomEvent>{};
  final savedRoomRequests = <String, Map<String, dynamic>>{};
  Timer? roomDraftTimer;
  List<RoomEvent> get events =>
      history.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  Timer? pickerDeadline;
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
  bool minimized = false;
  void minimize() {
    minimized = active != null;
    notify();
  }

  void expand() {
    minimized = false;
    notify();
  }

  bool backgroundAudio = false;
  String? audioLease;
  bool get inRoom => active != null || joining;
  VoiceMember? get me => active?.member(accounts.user?.id);
  bool get manage => me?.role == 'owner' || me?.role == 'moderator';
  bool get microphoneOn => audio?.micEnabled == true;
  bool get canUseMic =>
      connected &&
      (foreground || backgroundAudio) &&
      !pickingMedia &&
      me?.seat != null &&
      me?.micAllowed == true &&
      audio?.canPublish == true;
  bool valid(int gen) => !disposed && generation == gen && sessionKey != null;
  final Map<String, DateTime> openMicSince = {};
  int get microphoneSeconds {
    final since = identity == null ? null : openMicSince[identity];
    return since == null
        ? 0
        : DateTime.now().difference(since).inSeconds.clamp(0, 86400);
  }

  void notify() {
    final open = audio?.openMics ?? <String>{};
    openMicSince.removeWhere((key, _) => !open.contains(key));
    for (final id in open) {
      openMicSince.putIfAbsent(id, DateTime.now);
    }
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
    minimized = false;
    generation++;
    poll?.cancel();
    release();
    active = null;
    identity = null;
    rooms.clear();
    scope = 'all';
    listEpoch++;
    preferenceBusy.clear();
    preferenceCache.clear();
    savedRoomRequests.clear();
    pendingCreation = null;
    pendingCosmetic = null;
    commerceReady = false;
    roomUpdate?.cancel();
    nextBefore = null;
    ownedRoomId = null;
    busy = false;
    joining = false;
    syncing = false;
    loading = false;
    configured = false;
    gifts.clear();
    coins = 0;
    walletReady = false;
    nextClaim = null;
    extrasLoading = false;
    pendingGift = null;
    pendingMessage = null;
    pendingGiftRoom = null;
    pendingMessageRoom = null;
    roomMedia = null;
    roomDraft = '';
    roomStorageReady = true;
    giftAttempted = false;
    messageAttempted = false;
    history.clear();
    eventsBefore = null;
    historyLoading = false;
    historyLoaded = false;
    historyWindow = false;
    roomDraftTimer?.cancel();
    pickingMedia = false;
    pickerDeadline?.cancel();
    error = null;
    notice = null;
    if (key != null) unawaited(restoreSavedRooms(generation));
    if (key != null && autoPoll)
      poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(tick()),
      );
    notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    foreground = state == AppLifecycleState.resumed;
    if (!foreground && inRoom && !backgroundAudio) {
      if (pickingMedia) {
        unawaited(audio?.microphone(false));
      } else {
        unawaited(leave(message: 'غادرت الغرفة عند مغادرة التطبيق.'));
      }
    } else if (foreground)
      unawaited(tick());
  }

  Future<void> selectScope(String value) async {
    if (scope == value || !['all', 'favorites', 'following'].contains(value))
      return;
    listEpoch++;
    scope = value;
    rooms.clear();
    nextBefore = null;
    loading = false;
    notify();
    await load();
  }

  Future<void> setPreference(
    VoiceRoom room, {
    bool? favorite,
    bool? following,
  }) async {
    if (disposed || !preferenceBusy.add(room.id)) return;
    final gen = generation;
    notify();
    try {
      final latest = active?.id == room.id
          ? active!
          : rooms.where((r) => r.id == room.id).firstOrNull ?? room;
      final d = await request(
        'PUT',
        '/v1/rooms/${room.id}/preferences',
        body: {
          if (favorite != null) 'favorite': favorite,
          if (following != null) 'following': following,
          'expectedRevision': latest.preferenceRevision,
        },
      );
      if (!valid(gen)) return;
      final prefs = d['preferences'] as Map<String, dynamic>;
      rememberPreferences(VoiceRoom({...room.data, 'preferences': prefs}));
      final index = rooms.indexWhere((r) => r.id == room.id);
      if (index >= 0) {
        final old = rooms[index],
            next = VoiceRoom({
              ...old.data,
              'preferences': prefs,
            }).preservePreferences(old);
        if (scope == 'favorites' && !next.favorite ||
            scope == 'following' && !next.following)
          rooms.removeAt(index);
        else
          rooms[index] = next;
      }
      if (active?.id == room.id)
        active = VoiceRoom({
          ...active!.data,
          'preferences': prefs,
        }).preservePreferences(active!);
      error = null;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        if (e.code == 'PREFERENCES_CHANGED') unawaited(load());
      }
    } catch (_) {
      if (valid(gen)) error = 'تعذّر حفظ المفضلة أو المتابعة.';
    } finally {
      if (valid(gen)) {
        preferenceBusy.remove(room.id);
        notify();
      }
    }
  }

  VoiceRoom rememberPreferences(VoiceRoom room) {
    final previous = preferenceCache[room.id];
    if (previous != null &&
        room.preferenceRevision <
            ((previous['revision'] as num?)?.toInt() ?? 0)) {
      return VoiceRoom({...room.data, 'preferences': previous});
    }
    preferenceCache[room.id] = room.preferences;
    return room;
  }

  Future<void> load({bool more = false}) async {
    if (loading || disposed || sessionKey == null || more && nextBefore == null)
      return;
    final gen = generation, rev = ++listEpoch;
    loading = true;
    error = null;
    notify();
    try {
      final d = await request(
        'GET',
        '/v1/rooms',
        query: {'scope': scope, if (more) 'before': nextBefore!},
      );
      if (!valid(gen) || rev != listEpoch) return;
      configured = d['configured'] == true;
      ownedRoomId = d['ownedRoomId'] as String?;
      final items = (d['rooms'] as List).map(
        (v) => VoiceRoom(v as Map<String, dynamic>),
      );
      if (!more) rooms.clear();
      for (final item in items) {
        final r = rememberPreferences(item);
        rooms.removeWhere((old) => old.id == r.id);
        if (scope == 'favorites' && !r.favorite ||
            scope == 'following' && !r.following)
          continue;
        rooms.add(r);
      }
      nextBefore = d['nextBefore'] as String?;
    } on AccountFailure catch (e) {
      if (valid(gen) && rev == listEpoch) error = e.message;
    } catch (_) {
      if (valid(gen) && rev == listEpoch)
        error = 'تعذّر تحميل الغرف؛ جرّب مرة ثانية.';
    } finally {
      if (valid(gen) && rev == listEpoch) {
        loading = false;
        notify();
      }
    }
  }

  Future<bool> saveCommerce(
    String scope,
    Map<String, dynamic>? body,
    int gen,
  ) async {
    final owner = accounts.draftOwnerId;
    if (owner == null || !valid(gen) || !commerceReady)
      throw const DraftStorageFailure(
        'تعذّر قراءة الشراء المحفوظ؛ أعد فتح الصفحة.',
      );
    return accounts.draftStore.write(
      owner,
      scope,
      body,
      valid: () => valid(gen) && owner == accounts.draftOwnerId,
    );
  }

  Future<String?> create(
    String title,
    int capacity,
    int seats, {
    String tier = 'free',
    bool acceptTerms = false,
  }) async {
    if (busy || inRoom || sessionKey == null) return null;
    final gen = generation;
    bool recorded = false;
    busy = true;
    error = null;
    notify();
    try {
      if (!commerceReady) await restoreSavedRooms(gen);
      final desired = {
        'title': title.trim(),
        'capacity': capacity,
        'seatCount': seats,
        'tier': tier,
        'acceptTerms': acceptTerms,
      };
      final saved = pendingCreation;
      if (saved != null && desired.entries.any((e) => saved[e.key] != e.value))
        throw const DraftStorageFailure(
          'عندك طلب إنشاء محفوظ؛ أكمله قبل إنشاء غرفة أخرى.',
        );
      final body = pendingCreation ??= {
        'requestId': newRequestId(),
        ...desired,
      };
      if (!await saveCommerce('voice-create', body, gen)) return null;
      recorded = true;
      Map<String, dynamic>? d;
      if (saved != null) {
        try {
          d = await request('GET', '/v1/rooms/purchases/${body['requestId']}');
        } on AccountFailure catch (e) {
          if (e.status != 404 && e.code != 'REQUEST_NOT_FOUND') rethrow;
        }
      }
      d ??= await post('/v1/rooms', body);
      if (!valid(gen)) return null;
      if (!await saveCommerce('voice-create', null, gen)) return null;
      pendingCreation = null;
      if (d['wallet'] is Map<String, dynamic>)
        applyWallet(d['wallet'] as Map<String, dynamic>);
      final room = VoiceRoom(d['room'] as Map<String, dynamic>);
      ownedRoomId = room.closed ? null : room.id;
      rooms.removeWhere((v) => v.id == room.id);
      if (!room.closed) rooms.insert(0, room);
      return room.closed ? null : room.id;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        if (e.code == 'ROOMS_DISABLED') configured = false;
        if ((e.status == 503 && e.code == 'ROOMS_DISABLED') ||
            e.status >= 400 &&
                e.status < 500 &&
                const {
                  'ROOM_COINS_LOW',
                  'VALIDATION',
                  'ROOM_TERMS',
                  'ROOM_OWNED',
                  'ROOMS_DISABLED',
                  'COSMETIC_EXPIRED',
                }.contains(e.code)) {
          try {
            if (await saveCommerce('voice-create', null, gen))
              pendingCreation = null;
          } catch (_) {
            error = 'تعذّر حفظ النتيجة؛ أعد التحقق من الطلب المحفوظ.';
          }
        }
      }
      return null;
    } catch (_) {
      if (valid(gen))
        error = recorded
            ? 'طلب الإنشاء محفوظ؛ اضغط إكمال الطلب للتحقق بدون خصم جديد.'
            : 'تعذّر حفظ الطلب؛ لم يبدأ الشراء. أعد المحاولة.';
      return null;
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<bool> purchaseCosmetic(Map<String, dynamic> item) async {
    if (busy || sessionKey == null) return false;
    final gen = generation;
    bool recorded = false;
    busy = true;
    error = null;
    notify();
    try {
      if (!commerceReady) await restoreSavedRooms(gen);
      if (pendingCosmetic != null &&
          (pendingCosmetic!['kind'] != item['kind'] ||
              pendingCosmetic!['styleId'] != item['id']))
        throw const DraftStorageFailure('أكمل الشراء المحفوظ أولًا.');
      final body = pendingCosmetic ??= {
        'requestId': newRequestId(),
        'kind': item['kind'],
        'styleId': item['id'],
      };
      if (!await saveCommerce('voice-shop', body, gen)) return false;
      recorded = true;
      final d = await post('/v1/rooms/shop', body);
      if (!valid(gen)) return false;
      if (!await saveCommerce('voice-shop', null, gen)) return false;
      pendingCosmetic = null;
      applyWallet(d['wallet'] as Map<String, dynamic>);
      await tick();
      return true;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        if (e.status >= 400 &&
            e.status < 500 &&
            const {
              'ROOM_COINS_LOW',
              'VALIDATION',
              'ROOM_TERMS',
              'ROOM_OWNED',
              'ROOMS_DISABLED',
              'COSMETIC_EXPIRED',
            }.contains(e.code)) {
          try {
            if (await saveCommerce('voice-shop', null, gen))
              pendingCosmetic = null;
          } catch (_) {
            error = 'تعذّر حفظ النتيجة؛ أعد التحقق من الطلب المحفوظ.';
          }
        }
      }
    } catch (_) {
      if (valid(gen))
        error = recorded
            ? 'الشراء محفوظ؛ أعد المحاولة للتحقق بدون خصم جديد.'
            : 'تعذّر حفظ الطلب؛ لم يبدأ الشراء. أعد المحاولة.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
    return false;
  }

  Future<String?> findRoom(String publicId) async {
    final gen = generation;
    try {
      final d = await request(
        'GET',
        '/v1/rooms/lookup/${Uri.encodeComponent(publicId.trim())}',
      );
      if (!valid(gen)) return null;
      final room = VoiceRoom(d['room'] as Map<String, dynamic>);
      rooms.removeWhere((r) => r.id == room.id);
      rooms.insert(0, room);
      error = null;
      notify();
      return room.id;
    } on AccountFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'تعذّر البحث عن الغرفة.';
    }
    notify();
    return null;
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

  Future<bool> join(String roomId, {String? password}) async {
    if (accounts.liveMediaLease != null) {
      error = 'أغلق البث قبل دخول الروم.';
      notify();
      return false;
    }
    if (inRoom && active?.id != roomId && !busy) {
      await leave();
      await releaseTail;
    }
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
        d = await post('/v1/rooms/$roomId/join', {
          if (password != null) 'password': password,
        });
      } on AccountFailure catch (e) {
        if (e.code != 'NETWORK') rethrow;
        d = await post('/v1/rooms/$roomId/join', {
          if (password != null) 'password': password,
        });
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
      active = rememberPreferences(
        VoiceRoom(d['room'] as Map<String, dynamic>),
      );
      history.clear();
      historyLoaded = false;
      historyWindow = false;
      historyLoading = false;
      eventsBefore = null;
      mergeEvents(active!);
      await restoreRoom(roomId, gen);
      if (!valid(gen)) return false;
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
      final lease = identity!;
      audioLease = lease;
      final ready = await accounts.mobile.startAudio(lease, 'room');
      if (!valid(gen) || !foreground) {
        await accounts.mobile.stopAudio(lease);
        return false;
      }
      backgroundAudio = ready;
      audioLease = ready ? lease : null;
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
    active = rememberPreferences(room.preservePreferences(active!));
    final ownMember = active!.member(accounts.user?.id);
    if (ownMember != null) accounts.applyRoomIdentity(ownMember.user);
    mergeEvents(room);
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
    if (disposed ||
        (!foreground && !backgroundAudio) ||
        active == null ||
        !connected ||
        syncing)
      return;
    final gen = generation, r = active!;
    syncing = true;
    try {
      if (audioLease != null) await accounts.mobile.renewAudio(audioLease!);
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

  Future<bool> action(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    if (busy || active == null || disposed) return false;
    final gen = generation, r = active!;
    busy = true;
    error = null;
    notify();
    try {
      final d = await post('/v1/rooms/${r.id}/$action', body);
      if (!valid(gen)) return false;
      await apply(VoiceRoom(d['room'] as Map<String, dynamic>), gen);
      return valid(gen);
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
    return false;
  }

  Future<void> loadGifts() async {
    if (extrasLoading || sessionKey == null || disposed) return;
    final gen = generation;
    extrasLoading = true;
    error = null;
    notify();
    try {
      final d = await Future.wait([
        request('GET', '/v1/rooms/gifts'),
        request('GET', '/v1/rooms/wallet'),
      ]);
      if (!valid(gen)) return;
      gifts
        ..clear()
        ..addAll(
          (d[0]['gifts'] as List).map(
            (v) => RoomGift(v as Map<String, dynamic>),
          ),
        );
      applyWallet(d[1]['wallet'] as Map<String, dynamic>);
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تحميل الهدايا والرصيد.';
    } finally {
      if (valid(gen)) {
        extrasLoading = false;
        notify();
      }
    }
  }

  void applyWallet(Map<String, dynamic> d) {
    walletReady = true;
    coins = (d['coins'] as num).toInt();
    nextClaim = d['nextClaim'] as String?;
  }

  Future<void> claimCoins() async {
    if (busy || sessionKey == null) return;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    try {
      final d = await post('/v1/rooms/wallet/claim', {});
      if (!valid(gen)) return;
      applyWallet(d['wallet'] as Map<String, dynamic>);
      notice = d['claimed'] == true
          ? 'وصلتك 500 عملة تجريبية.'
          : 'المكافأة تتجدد كل24 ساعة؛ موعدها ظاهر بالمحفظة.';
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تحديث المحفظة.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void>? restoringSavedRooms;
  Future<void> restoreSavedRooms(int gen) async {
    if (restoringSavedRooms != null) await restoringSavedRooms;
    if (commerceReady || !valid(gen)) return;
    final work = _readSavedRooms(gen);
    restoringSavedRooms = work;
    try {
      await work;
    } finally {
      if (identical(work, restoringSavedRooms)) restoringSavedRooms = null;
    }
  }

  Future<void> _readSavedRooms(int gen) async {
    final owner = accounts.draftOwnerId;
    if (owner == null) return;
    try {
      final rows = await accounts.draftStore.list(owner);
      if (!valid(gen)) return;
      pendingCreation = rows['voice-create'];
      pendingCosmetic = rows['voice-shop'];
      commerceReady = true;
      for (final e in rows.entries.where((e) => e.key.startsWith('room:')))
        savedRoomRequests[e.key.substring(5)] = e.value;
      notify();
    } catch (_) {
      if (valid(gen)) {
        notice = 'تعذّر قراءة بعض الإرسالات المحفوظة؛ لم تُحذف.';
        notify();
      }
    }
  }

  Future<bool> resolveSavedRoom(
    String rid,
    String kind, {
    bool discard = false,
  }) async {
    final data = savedRoomRequests[rid],
        owner = accounts.draftOwnerId,
        gen = generation;
    if (data == null || owner == null || busy || rid == active?.id)
      return false;
    final body = data[kind] as Map<String, dynamic>?;
    if (body == null) return false;
    busy = true;
    error = null;
    notify();
    try {
      if (!discard) {
        final receipt = await request(
          'GET',
          '/v1/rooms/$rid/requests/${body['requestId']}',
        );
        if (!valid(gen)) return false;
        if (receipt['kind'] != kind)
          throw const AccountFailure('REQUEST_CHANGED', 'طلب الإرسال تغيّر.');
        if (receipt['wallet'] is Map<String, dynamic>)
          applyWallet(receipt['wallet'] as Map<String, dynamic>);
      }
      final next = {
        ...data,
        kind: null,
        '${kind}Attempted': false,
        if (kind == 'message') 'media': null,
      };
      if (!await accounts.draftStore.write(
        owner,
        'room:$rid',
        next,
        valid: () => valid(gen) && accounts.draftOwnerId == owner,
      ))
        return false;
      if (!valid(gen)) return false;
      savedRoomRequests[rid] = next;
      notice = discard
          ? 'أُلغيت إعادة المحاولة على هذا الجهاز.'
          : 'تم التأكد من نجاح الإرسال السابق.';
      return true;
    } on AccountFailure catch (e) {
      if (valid(gen))
        error = e.status == 404
            ? 'لم يُسجّل هذا الإرسال. ادخل الغرفة لإعادة المحاولة، أو ألغِ المحاولة المحفوظة.'
            : e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر التحقق أو حفظ النتيجة؛ أعد المحاولة.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
    return false;
  }

  Future<void> restoreRoom(String roomId, int gen) async {
    pendingGift = null;
    pendingGiftRoom = null;
    pendingMessage = null;
    pendingMessageRoom = null;
    roomMedia = null;
    roomDraft = '';
    roomStorageReady = true;
    giftAttempted = false;
    messageAttempted = false;
    final owner = accounts.draftOwnerId;
    try {
      final d = owner == null
          ? null
          : await accounts.draftStore.read(owner, 'room:$roomId');
      if (!valid(gen) || active?.id != roomId || d == null) return;
      pendingGift = d['gift'] as Map<String, dynamic>?;
      pendingGiftRoom = pendingGift == null ? null : roomId;
      pendingMessage = d['message'] as Map<String, dynamic>?;
      pendingMessageRoom = pendingMessage == null ? null : roomId;
      if (d['media'] is Map)
        roomMedia = PendingChatMessage.restore(
          d['media'] as Map<String, dynamic>,
        );
      roomDraft = d['draft'] as String? ?? '';
      giftAttempted = d['giftAttempted'] == true;
      messageAttempted = d['messageAttempted'] == true;
      if (pendingGift != null || pendingMessage != null)
        notice =
            'يوجد إرسال محفوظ؛ راجعه واضغط إعادة المحاولة للتحقق من نتيجته.';
    } catch (_) {
      if (valid(gen)) {
        roomStorageReady = false;
        error = 'تعذّر قراءة إرسال الغرفة المحفوظ؛ لم يُحذف.';
      }
    }
  }

  Future<bool> persistRoom() {
    final owner = accounts.draftOwnerId,
        revision = accounts.sessionRevision,
        rid = active?.id;
    if (owner == null || rid == null) return Future.value(false);
    if (!roomStorageReady)
      return Future.error(
        const DraftStorageFailure('تعذّر قراءة الإرسال المحفوظ؛ لم نكتب فوقه.'),
      );
    final p = roomMedia,
        data = {
          'title': active!.title,
          'gift': pendingGift,
          'message': pendingMessage,
          'media': p?.toJson(),
          'draft': roomDraft,
          'giftAttempted': giftAttempted,
          'messageAttempted': messageAttempted,
        };
    return accounts.draftStore
        .write(
          owner,
          'room:$rid',
          data,
          blobs: <String, Uint8List>{
            if (p?.media != null) p!.mediaKey!: p.media!.bytes,
          },
          valid: () =>
              !disposed &&
              accounts.draftOwnerId == owner &&
              accounts.sessionRevision == revision,
        )
        .then((ok) {
          if (ok &&
              !disposed &&
              accounts.draftOwnerId == owner &&
              accounts.sessionRevision == revision) {
            savedRoomRequests[rid] = data;
            notify();
          }
          return ok;
        });
  }

  void setRoomDraft(String text) {
    roomDraft = text;
    roomDraftTimer?.cancel();
    roomDraftTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(
        persistRoom().catchError((Object _) {
          if (!disposed) {
            error = 'تعذّر حفظ مسودة الغرفة.';
            notify();
          }
          return false;
        }),
      ),
    );
  }

  void mergeEvents(VoiceRoom r) {
    if (!historyLoaded)
      eventsBefore = (r.features['eventsBefore'] as num?)?.toInt();
    final high = history.keys.isEmpty
        ? 0
        : history.keys.reduce((a, b) => a > b ? a : b);
    for (final e in r.events)
      if (!historyWindow || e.sequence <= high) history[e.sequence] = e;
    while (history.length > 500)
      history.remove(history.keys.reduce((a, b) => a < b ? a : b));
  }

  Future<void> olderEvents() async {
    final rid = active?.id, gen = generation;
    if (rid == null || historyLoading || eventsBefore == null) return;
    historyLoading = true;
    notify();
    try {
      final d = await request(
        'GET',
        '/v1/rooms/$rid/events',
        query: {'before': '$eventsBefore'},
      );
      if (!valid(gen) || active?.id != rid) return;
      for (final row in d['events'] as List) {
        final e = RoomEvent(row as Map<String, dynamic>);
        history[e.sequence] = e;
      }
      historyLoaded = true;
      eventsBefore = (d['nextBefore'] as num?)?.toInt();
      if (history.length > 500) {
        historyWindow = true;
        while (history.length > 500)
          history.remove(history.keys.reduce((a, b) => a > b ? a : b));
      }
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تحميل رسائل الغرفة الأقدم.';
    } finally {
      if (valid(gen)) {
        historyLoading = false;
        notify();
      }
    }
  }

  void latestEvents() {
    history.clear();
    historyWindow = false;
    historyLoaded = false;
    if (active != null) mergeEvents(active!);
    notify();
  }

  Future<void> cancelPending(String kind) async {
    if (busy || active == null) return;
    final gen = generation,
        gift = pendingGift,
        message = pendingMessage,
        media = roomMedia,
        giftRoom = pendingGiftRoom,
        messageRoom = pendingMessageRoom,
        ga = giftAttempted,
        ma = messageAttempted;
    if (kind == 'gift') {
      pendingGift = null;
      pendingGiftRoom = null;
      giftAttempted = false;
    } else {
      pendingMessage = null;
      pendingMessageRoom = null;
      roomMedia = null;
      messageAttempted = false;
    }
    try {
      if (!await persistRoom())
        throw const DraftStorageFailure('Storage changed');
    } catch (_) {
      if (valid(gen)) {
        pendingGift = gift;
        pendingMessage = message;
        roomMedia = media;
        pendingGiftRoom = giftRoom;
        pendingMessageRoom = messageRoom;
        giftAttempted = ga;
        messageAttempted = ma;
        error = 'تعذّر حفظ إلغاء المحاولة.';
      }
    }
    if (valid(gen)) notify();
  }

  Future<bool> sendGift(
    String recipient,
    String gift,
    int quantity, {
    String audience = 'person',
  }) {
    if (busy || active == null || sessionKey == null)
      return Future.value(false);
    if (pendingGift != null) return retrySend('gift');
    pendingGift = {
      'requestId': newRequestId(),
      'recipientId': recipient,
      'audience': audience,
      if (audience != 'person')
        'recipientIds':
            active!.members
                .where(
                  (m) =>
                      audience == 'all' ||
                      (audience == 'mics' ? m.seat != null : m.seat == null),
                )
                .map((m) => m.user.id)
                .toList()
              ..sort(),
      'giftId': gift,
      'quantity': quantity,
    };
    pendingGiftRoom = active?.id;
    giftAttempted = false;
    return retrySend('gift');
  }

  Future<bool> sendMessage(
    String text, {
    String? imageUploadId,
    ImageDraft? image,
  }) {
    if (busy || active == null || sessionKey == null)
      return Future.value(false);
    if (pendingMessage != null) return retrySend('message');
    roomMedia = image == null ? null : PendingChatMessage(text, image);
    messageAttempted = false;
    pendingMessage = {
      'requestId': roomMedia?.requestId ?? newRequestId(),
      'text': text,
      if (imageUploadId != null) 'imageUploadId': imageUploadId,
      if (image != null) 'attachmentSha256': image.contentSha256,
    };
    pendingMessageRoom = active?.id;
    return retrySend('message');
  }

  Future<bool> retrySend(String kind) async {
    final body = kind == 'gift' ? pendingGift : pendingMessage,
        roomId = kind == 'gift' ? pendingGiftRoom : pendingMessageRoom;
    if (busy ||
        disposed ||
        active == null ||
        body == null ||
        active!.id != roomId)
      return false;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    void clear() {
      if (kind == 'gift') {
        pendingGift = null;
        pendingGiftRoom = null;
      } else {
        pendingMessage = null;
        pendingMessageRoom = null;
      }
    }

    try {
      if (!await persistRoom()) return false;
      if (kind == 'gift' ? giftAttempted : messageAttempted) {
        try {
          final receipt = await request(
            'GET',
            '/v1/rooms/$roomId/requests/${body['requestId']}',
          );
          if (!valid(gen)) return false;
          if (receipt['kind'] != kind)
            throw const AccountFailure(
              'REQUEST_CHANGED',
              'معرّف الإرسال استُخدم لطلب آخر.',
            );
          if (receipt['wallet'] is Map<String, dynamic>)
            applyWallet(receipt['wallet'] as Map<String, dynamic>);
          clear();
          if (kind == 'message') {
            roomMedia = null;
            roomDraft = '';
            messageAttempted = false;
          } else
            giftAttempted = false;
          await persistRoom();
          await tick();
          return true;
        } on AccountFailure catch (e) {
          if (e.status != 404) rethrow;
        }
      }
      if (kind == 'message' && roomMedia != null) {
        final p = roomMedia!;
        if (p.media == null) {
          final m = p.savedMedia!,
              bytes = await accounts.draftStore.bytes(
                accounts.draftOwnerId!,
                m['mediaKey'] as String,
              );
          if (!valid(gen)) return false;
          p.image = ImageDraft(bytes, m['type'] as String);
        }
        if (!p.uploaded) {
          if (p.upload != null &&
              (p.preparedAt == null ||
                  DateTime.now().difference(p.preparedAt!).inMinutes >= 14))
            p.upload = null;
          if (p.upload == null) {
            p.upload = await accounts.preparePostMedia(p.media!, p.requestId);
            if (!valid(gen)) return false;
            p.preparedAt = DateTime.now();
            if (!await persistRoom()) return false;
          }
          await accounts.uploadImage(p.upload!, p.media!);
          if (!valid(gen)) return false;
          p.uploaded = true;
        }
        body['imageUploadId'] = p.upload!.id;
      }
      if (kind == 'gift')
        giftAttempted = true;
      else
        messageAttempted = true;
      if (!await persistRoom()) return false;
      Map<String, dynamic> d;
      try {
        d = await post('/v1/rooms/$roomId/$kind', body);
      } on AccountFailure catch (e) {
        if (e.code != 'NETWORK') rethrow;
        if (!valid(gen)) return false;
        d = await post('/v1/rooms/$roomId/$kind', body);
      }
      if (!valid(gen)) return false;
      if (d['wallet'] is Map<String, dynamic>)
        applyWallet(d['wallet'] as Map<String, dynamic>);
      clear();
      if (kind == 'message') {
        roomMedia = null;
        roomDraft = '';
        messageAttempted = false;
      } else
        giftAttempted = false;
      await persistRoom();
      await apply(VoiceRoom(d['room'] as Map<String, dynamic>), gen);
      return true;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        if (kind == 'gift' && e.code == 'ROOM_RECIPIENTS_CHANGED') {
          clear();
          giftAttempted = false;
        }
        if (e.code == 'UPLOAD_INVALID' &&
            kind == 'message' &&
            roomMedia != null) {
          roomMedia!.upload = null;
          roomMedia!.uploaded = false;
        }
        try {
          await persistRoom();
        } catch (_) {
          error =
              'تعذّر حفظ الإرسال على الجهاز؛ لا تغلق الصفحة قبل إعادة المحاولة.';
        }
      }
    } catch (_) {
      if (valid(gen))
        error = 'نتيجة الإرسال بعد مو مؤكدة؛ اضغط إعادة المحاولة لنفس الطلب.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> roomData(String action) async {
    final r = active, gen = generation;
    if (r == null) return null;
    try {
      final d = await request('GET', '/v1/rooms/${r.id}/$action');
      return valid(gen) ? d : null;
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تحميل بيانات الغرفة.';
    }
    notify();
    return null;
  }

  Future<String?> uploadRoomImage(ImageDraft image) async {
    final gen = generation;
    if (active == null) return null;
    try {
      final d = await post('/v1/media/images', {
        'contentType': image.contentType,
        'byteLength': image.bytes.length,
        'contentMd5': image.contentMd5,
      });
      if (!valid(gen)) return null;
      final upload = ImageUpload.fromJson(d);
      await accounts.uploadImage(upload, image);
      return valid(gen) ? upload.id : null;
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } catch (_) {
      if (valid(gen)) error = 'تعذّر رفع الصورة.';
    }
    notify();
    return null;
  }

  Future<T?> mediaPicker<T>(Future<T?> Function() pick) async {
    if (pickingMedia || active == null) return null;
    final gen = generation;
    pickingMedia = true;
    final deadline = Timer(const Duration(seconds: 40), () {
      if (valid(gen) && !foreground && !backgroundAudio)
        unawaited(
          leave(message: 'انتهت مهلة اختيار الصورة؛ ادخل للغرفة مرة ثانية.'),
        );
    });
    pickerDeadline = deadline;
    try {
      await audio?.microphone(false);
      if (!valid(gen)) return null;
      return await pick();
    } finally {
      deadline.cancel();
      if (valid(gen)) {
        pickingMedia = false;
        if (identical(pickerDeadline, deadline)) pickerDeadline = null;
        if (!foreground && !backgroundAudio)
          await leave(message: 'غادرت الغرفة عند مغادرة التطبيق.');
        if (valid(gen)) notify();
      }
    }
  }

  Future<bool> moderate(VoiceMember member, String operation, {int? seat}) =>
      action(
        'moderate',
        body: {
          'targetId': member.user.id,
          'operation': operation,
          if (seat != null) 'seat': seat,
        },
      );
  Future<void> toggleMicrophone() async {
    if (!foreground || micBusy || audio == null || !connected) return;
    final engine = audio!, gen = generation, enable = !engine.micEnabled;
    if (enable && (!canUseMic || !foreground)) {
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
      if (enable &&
          valid(gen) &&
          foreground &&
          audio == engine &&
          audioLease != null) {
        final ready = await accounts.mobile.startAudio(
          audioLease!,
          'room',
          microphone: true,
        );
        if (valid(gen) && audio == engine) backgroundAudio = ready;
      }
      // Permission dialogs can complete after demotion/background/leave.
      if (!valid(gen) ||
          audio != engine ||
          enable && (!canUseMic || !foreground))
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
    final lease = audioLease;
    audioLease = null;
    backgroundAudio = false;
    if (lease != null)
      unawaited(accounts.mobile.stopAudio(lease).catchError((Object _) {}));
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
    minimized = false;
    final saved = persistRoom().catchError((Object _) => false);
    final r = active,
        oldIdentity = identity,
        user = accounts.user?.id,
        revision = accounts.sessionRevision;
    await saved;
    if (accounts.user?.id != user ||
        accounts.sessionRevision != revision ||
        active?.id != r?.id ||
        identity != oldIdentity)
      return;
    generation++;
    preferenceBusy.clear();
    history.clear();
    eventsBefore = null;
    historyLoading = false;
    historyLoaded = false;
    historyWindow = false;
    active = null;
    identity = null;
    joining = false;
    busy = false;
    syncing = false;
    loading = false;
    extrasLoading = false;
    pickingMedia = false;
    pickerDeadline?.cancel();
    pickerDeadline = null;
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
    roomUpdate?.cancel();
    unawaited(roomRealtime?.cancel());
    pickerDeadline?.cancel();
    roomDraftTimer?.cancel();
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }
}
