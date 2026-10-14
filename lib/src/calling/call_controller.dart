import 'dart:async';
import 'package:flutter/widgets.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../social/social_models.dart';
import 'call_models.dart';
import '../messaging/audio_focus.dart';
import 'call_media.dart';

class CallController extends ChangeNotifier with WidgetsBindingObserver {
  CallController({
    required this.accounts,
    CallMedia Function()? mediaFactory,
    this.autoPoll = true,
  }) : mediaFactory = mediaFactory ?? NativeCallMedia.new {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    if (autoPoll)
      realtime = accounts.chats.realtimeEvents.stream.listen((e) {
        if (e['type'] == 'call.changed' || e['type'] == 'chat.ready')
          unawaited(tick());
      });
    accountChanged();
  }
  final AccountController accounts;
  final CallMedia Function() mediaFactory;
  final bool autoPoll;
  DirectCall? active;
  CallMedia? media;
  String? identity, error;
  bool configured = false,
      busy = false,
      syncing = false,
      foreground = true,
      disposed = false;
  bool muted = false,
      speakerOn = false,
      cameraOn = true,
      localConnected = false,
      reconnecting = false;
  bool mediaReady = false,
      localDescriptionSent = false,
      remoteDescriptionSet = false;
  int generation = 0, after = 0, idleTicks = 0;
  final localCandidates = <Map<String, dynamic>>[],
      remoteCandidates = <Map<String, dynamic>>[];
  Future<void> signalTail = Future.value(), releaseTail = Future.value();
  Timer? poll, disconnectDeadline;
  StreamSubscription<Map<String, dynamic>>? realtime, mediaEvents;
  DateTime lastHeartbeat = DateTime.now(), lastSync = DateTime.now();
  void Function(DirectCall call)? onShow;
  bool valid(int gen) => !disposed && generation == gen && identity != null;
  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => accounts.chatRequest(method, path, body: body, query: query);
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
    int gen,
  ) async {
    for (var n = 0; ; n++) {
      if (!valid(gen))
        throw const AccountFailure('SESSION_CHANGED', 'جلسة الحساب تغيّرت.');
      try {
        return await request('POST', path, body: body);
      } on AccountFailure catch (e) {
        if (n >= 1 || e.code != 'NETWORK') rethrow;
      }
    }
  }

  DirectCall parse(Map<String, dynamic> d) =>
      DirectCall(d['call'] as Map<String, dynamic>);
  void accountChanged() {
    final next =
        accounts.phase == AccountPhase.signedIn &&
            accounts.pendingRecoveryCode == null
        ? '${accounts.user!.id}:${accounts.sessionRevision}'
        : null;
    if (disposed || identity == next) return;
    identity = next;
    generation++;
    poll?.cancel();
    release();
    active = null;
    configured = false;
    busy = false;
    syncing = false;
    error = null;
    if (next != null && autoPoll) {
      unawaited(tick());
      poll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (active?.ended == false || ++idleTicks % 4 == 0) unawaited(tick());
      });
    }
    notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      if (active?.ended == false && !active!.incoming)
        unawaited(hangup(reason: 'background'));
      else if (busy || media != null) {
        generation++;
        busy = false;
        syncing = false;
        release();
        notify();
      }
    } else if (identity != null)
      unawaited(tick());
    notify();
  }

  void apply(DirectCall call, {bool show = false}) {
    if (disposed) return;
    final previous = active?.id;
    active = call;
    if (call.ended) {
      release();
      busy = false;
    } else if (!call.canControl) {
      active = call.locallyEnded('other_device');
      release();
      busy = false;
    }
    notify();
    if (show || previous != call.id) onShow?.call(active!);
  }

  Future<void> open(String id) async {
    final gen = generation;
    if (identity == null) return;
    try {
      final d = await request('GET', '/v1/calls/$id');
      if (!valid(gen)) return;
      if (active?.ended == false && active!.id != id) return;
      apply(parse(d), show: true);
      lastSync = DateTime.now();
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        notify();
      }
    }
  }

  Future<void> tick() async {
    if (disposed || identity == null || !foreground || syncing || busy) return;
    syncing = true;
    final gen = generation;
    try {
      final call = active;
      if (call == null || call.ended) {
        final d = await request('GET', '/v1/calls/active');
        if (!valid(gen)) return;
        configured = d['configured'] == true;
        if (d['call'] != null) {
          final next = parse(d);
          if (next.canControl) {
            apply(next);
            if (!next.incoming && media == null) await hangup(reason: 'failed');
          }
        }
      } else if (media != null && mediaReady && call.canControl) {
        await syncSignals(gen);
      } else {
        final d = await request('GET', '/v1/calls/${call.id}');
        if (!valid(gen)) return;
        apply(parse(d));
      }
      if (!valid(gen)) return;
      lastSync = DateTime.now();
      final current = active;
      if (current?.ended == false &&
          current!.canControl &&
          !current.incoming &&
          DateTime.now().difference(lastHeartbeat).inSeconds >= 10) {
        lastHeartbeat = DateTime.now();
        final d = await post('/v1/calls/${current.id}/heartbeat', {}, gen);
        if (valid(gen) && active?.id == current.id) apply(parse(d));
      }
      if (valid(gen)) error = null;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        if (e.code == 'CALL_OTHER_DEVICE' && active != null)
          apply(active!.locallyEnded('other_device'));
        else if (active?.ended == false) {
          error = 'نتحقق من الاتصال…';
          if (DateTime.now().difference(lastSync).inSeconds >= 25)
            unawaited(hangup(reason: 'failed'));
        } else if (e.status == 404)
          configured = false;
        notify();
      }
    } catch (_) {
      if (valid(gen)) {
        error = 'تعذّر تحديث حالة الاتصال.';
        notify();
      }
    } finally {
      if (gen == generation) syncing = false;
    }
  }

  void closeLateGrant(String id, String userId, int revision) {
    if (!disposed &&
        accounts.user?.id == userId &&
        accounts.sessionRevision == revision)
      unawaited(
        request(
          'POST',
          '/v1/calls/$id/end',
          body: {'reason': 'background'},
        ).catchError((Object _) => <String, dynamic>{}),
      );
  }

  Future<void> start(String conversationId, {bool video = false}) async {
    if (disposed || identity == null || busy || active?.ended == false) return;
    final gen = ++generation,
        userId = accounts.user!.id,
        revision = accounts.sessionRevision;
    busy = true;
    syncing = false;
    error = null;
    notify();
    final requestId = newRequestId();
    try {
      final settings = await request('GET', '/v1/calls/settings');
      if (!valid(gen)) return;
      configured = settings['configured'] == true;
      if (!configured)
        throw const AccountFailure(
          'CALLS_DISABLED',
          'المكالمات غير متاحة حاليًا؛ جرّب لاحقًا.',
        );
      await releaseTail;
      await stopVoiceForCall();
      if (!valid(gen)) return;
      final engine = mediaFactory();
      media = engine;
      await engine.prepare(video);
      if (!valid(gen) || !foreground) return;
      final d = await post('/v1/calls', {
        'conversationId': conversationId,
        'kind': video ? 'video' : 'audio',
        'requestId': requestId,
      }, gen);
      if (!valid(gen)) {
        closeLateGrant(parse(d).id, userId, revision);
        return;
      }
      apply(parse(d), show: true);
      if (active!.ended) return;
      await beginMedia(gen, caller: true);
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        await failed(gen);
      }
    } catch (_) {
      if (valid(gen)) {
        error =
            'تعذّر بدء المكالمة؛ اسمح بالمايك والكاميرا من إعدادات الهاتف وجرّب مرة ثانية.';
        await failed(gen);
      }
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> accept() async {
    final call = active;
    if (busy || call == null || !call.incoming || !call.canControl) return;
    final gen = generation,
        userId = accounts.user!.id,
        revision = accounts.sessionRevision;
    busy = true;
    error = null;
    notify();
    try {
      await releaseTail;
      await stopVoiceForCall();
      if (!valid(gen)) return;
      final engine = mediaFactory();
      media = engine;
      await engine.prepare(call.video);
      if (!valid(gen) || !foreground) return;
      final d = await post('/v1/calls/${call.id}/accept', {}, gen);
      if (!valid(gen)) {
        closeLateGrant(call.id, userId, revision);
        return;
      }
      apply(parse(d));
      if (active!.ended) return;
      await beginMedia(gen, caller: false);
      await syncSignals(gen);
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        if (e.code == 'CALL_OTHER_DEVICE')
          apply(call.locallyEnded('other_device'));
        else
          await failed(gen);
      }
    } catch (_) {
      if (valid(gen)) {
        error =
            'تعذّر الرد؛ اسمح بالمايك والكاميرا من إعدادات الهاتف وجرّب مرة ثانية.';
        await failed(gen);
      }
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> beginMedia(int gen, {required bool caller}) async {
    final call = active!, engine = media!;
    after = 0;
    mediaReady = false;
    localDescriptionSent = false;
    remoteDescriptionSet = false;
    localCandidates.clear();
    remoteCandidates.clear();
    muted = false;
    speakerOn = call.video;
    cameraOn = call.video;
    localConnected = false;
    reconnecting = false;
    signalTail = Future.value();
    final d = await post('/v1/calls/${call.id}/ice', {}, gen);
    if (!valid(gen) || active?.ended != false) return;
    mediaEvents = engine.events.listen(
      (e) {
        if (valid(gen) && media == engine) mediaEvent(e, gen);
      },
      onError: (Object _) {
        if (valid(gen)) unawaited(failed(gen));
      },
    );
    await engine.connect(d['configuration'] as Map<String, dynamic>);
    if (!valid(gen) || active?.ended != false) return;
    mediaReady = true;
    lastHeartbeat = DateTime.now();
    lastSync = DateTime.now();
    if (caller) {
      final sdp = await engine.offer();
      if (valid(gen)) await sendDescription('offer', sdp, gen);
    }
  }

  void mediaEvent(Map<String, dynamic> e, int gen) {
    switch (e['type']) {
      case 'candidate':
        final data = {...e}..remove('type');
        if (!localDescriptionSent) {
          if (localCandidates.length < 128) localCandidates.add(data);
        } else
          enqueueCandidate(data, gen);
      case 'connected':
        localConnected = true;
        reconnecting = false;
        disconnectDeadline?.cancel();
        notify();
        final call = active;
        if (call != null)
          unawaited(
            post('/v1/calls/${call.id}/connected', {}, gen)
                .then((d) {
                  if (valid(gen) && active?.id == call.id) apply(parse(d));
                })
                .catchError((Object _) {
                  if (valid(gen)) unawaited(failed(gen));
                }),
          );
      case 'disconnected':
        reconnecting = true;
        notify();
        disconnectDeadline?.cancel();
        disconnectDeadline = Timer(const Duration(seconds: 12), () {
          if (valid(gen)) unawaited(hangup(reason: 'failed'));
        });
      case 'failed':
        unawaited(failed(gen));
      default:
        notify();
    }
  }

  Future<void> sendDescription(String type, String sdp, int gen) async {
    final call = active;
    if (call == null) return;
    await post('/v1/calls/${call.id}/signals', {
      'type': type,
      'sdp': sdp,
      'requestId': newRequestId(),
    }, gen);
    if (!valid(gen) || active?.ended != false) return;
    localDescriptionSent = true;
    for (final c in localCandidates) enqueueCandidate(c, gen);
    localCandidates.clear();
  }

  void enqueueCandidate(Map<String, dynamic> candidate, int gen) {
    final call = active;
    if (call == null) return;
    final requestId = newRequestId();
    signalTail = signalTail
        .then((_) async {
          if (!valid(gen) || active?.id != call.id || active!.ended) return;
          await post('/v1/calls/${call.id}/signals', {
            'type': 'candidate',
            'requestId': requestId,
            ...candidate,
          }, gen);
        })
        .catchError((Object _) {
          if (valid(gen) && active?.id == call.id && active?.ended == false)
            unawaited(failed(gen));
        });
  }

  Future<void> syncSignals(int gen) async {
    final call = active, engine = media;
    if (call == null || engine == null || call.ended || !mediaReady) return;
    final d = await request(
      'GET',
      '/v1/calls/${call.id}/signals',
      query: {'after': after.toString()},
    );
    if (!valid(gen) || media != engine || active?.id != call.id) return;
    apply(parse(d));
    if (active!.ended) return;
    for (final v in d['signals'] as List) {
      final signal = v as Map<String, dynamic>, type = signal['type'];
      if (type == 'offer' || type == 'answer') {
        if (!remoteDescriptionSet) {
          await engine.remoteDescription(
            type as String,
            signal['sdp'] as String,
          );
          if (!valid(gen) || media != engine) return;
          remoteDescriptionSet = true;
          for (final c in remoteCandidates) await engine.candidate(c);
          remoteCandidates.clear();
          if (type == 'offer' && !localDescriptionSent) {
            final answer = await engine.answer();
            if (!valid(gen)) return;
            await sendDescription('answer', answer, gen);
          }
        }
      } else if (type == 'candidate') {
        if (remoteDescriptionSet)
          await engine.candidate(signal);
        else if (remoteCandidates.length < 256)
          remoteCandidates.add(signal);
      }
      if (!valid(gen) || media != engine) return;
      after = (signal['sequence'] as num).toInt();
    }
  }

  Future<void> failed(int gen) async {
    if (!valid(gen)) return;
    if (active?.ended == false && !active!.incoming)
      await hangup(reason: 'failed');
    else
      release();
  }

  Future<void> decline() async {
    final call = active;
    if (call == null || !call.incoming) return;
    final gen = ++generation;
    busy = false;
    syncing = false;
    apply(call.locallyEnded('declined'));
    try {
      final d = await post('/v1/calls/${call.id}/decline', {}, gen);
      if (valid(gen) && active?.id == call.id) apply(parse(d));
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        if (e.code == 'CALL_ALREADY_ACCEPTED') {
          try {
            final d = await post('/v1/calls/${call.id}/end', {
              'reason': 'ended',
            }, gen);
            if (valid(gen)) apply(parse(d));
          } catch (_) {}
        } else
          error = e.message;
      }
    }
    notify();
  }

  Future<void> hangup({String reason = 'ended'}) async {
    final call = active;
    if (call == null || call.ended) {
      release();
      return;
    }
    final gen = ++generation;
    busy = false;
    syncing = false;
    apply(call.locallyEnded(reason));
    try {
      final d = await post('/v1/calls/${call.id}/end', {'reason': reason}, gen);
      if (valid(gen) && active?.id == call.id) apply(parse(d));
    } catch (_) {}
    notify();
  }

  Future<void> control(Future<void> Function(CallMedia) work) async {
    final engine = media, gen = generation;
    if (busy || engine == null || active?.ended != false) return;
    busy = true;
    notify();
    try {
      await work(engine);
    } catch (_) {
      if (valid(gen)) error = 'تعذّر تغيير هذا الخيار.';
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> toggleMute() => control((m) async {
    final gen = generation;
    await m.mute(!muted);
    if (valid(gen) && media == m) muted = !muted;
  });
  Future<void> toggleSpeaker() => control((m) async {
    final gen = generation;
    await m.speaker(!speakerOn);
    if (valid(gen) && media == m) speakerOn = !speakerOn;
  });
  Future<void> toggleCamera() => control((m) async {
    final gen = generation;
    await m.camera(!cameraOn);
    if (valid(gen) && media == m) cameraOn = !cameraOn;
  });
  Future<void> switchCamera() => control((m) => m.switchCamera());
  void release() {
    disconnectDeadline?.cancel();
    unawaited(mediaEvents?.cancel());
    mediaEvents = null;
    final old = media;
    media = null;
    mediaReady = false;
    localConnected = false;
    reconnecting = false;
    if (old != null)
      releaseTail = releaseTail
          .then((_) => old.dispose())
          .catchError((Object _) {});
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    poll?.cancel();
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(realtime?.cancel());
    release();
    super.dispose();
  }
}
