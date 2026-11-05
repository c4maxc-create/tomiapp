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
      remoteVideoReady = false,
      reconnecting = false;
  bool backgroundAudio = false;
  String? audioLease;
  bool mediaReady = false,
      localDescriptionSent = false,
      remoteDescriptionSet = false;
  int generation = 0, after = 0, idleTicks = 0;
  int signalRevision = 0, stableRevision = 0, preparedRevision = 0;
  int appliedRevision = -1, handledMediaRevision = 0, modeDriveToken = 0;
  bool modeSyncing = false;
  String? mediaNotice;
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
    if (!foreground &&
        backgroundAudio &&
        mediaReady &&
        active?.ended == false) {
      // Stop capture itself, not just the rendered preview. Audio remains.
      final engine = media;
      cameraOn = false;
      if (engine != null)
        unawaited(
          engine
              .setVideo(false)
              .catchError((Object _) => unawaited(hangup(reason: 'failed'))),
        );
    } else if (!foreground) {
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
    final old = active;
    if (old?.id == call.id) {
      if (old!.ended && !call.ended) return;
      final before = old.mediaChange, next = call.mediaChange;
      // A polling response can arrive after a newer POST response. Do not
      // undo consent or a completed mode switch with that stale snapshot.
      if (!call.ended &&
          call.canControl &&
          before != null &&
          (next == null ||
              next.revision < before.revision ||
              next.revision == before.revision && next.phase < before.phase)) {
        call = DirectCall({
          ...call.data,
          'kind': old.data['kind'],
          'mediaChange': old.data['mediaChange'],
        });
      }
      if (old.state == 'connected' &&
          !call.ended &&
          call.canControl &&
          call.state != 'connected') {
        call = DirectCall({
          ...call.data,
          'state': old.state,
          'connectedAt': old.data['connectedAt'],
        });
      }
    }
    final previous = active?.id;
    active = call;
    if (!call.incoming)
      unawaited(accounts.mobile.clearCall(call.id).catchError((Object _) {}));
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
    if (mediaReady && media != null && !active!.ended) {
      unawaited(syncMediaChange(generation));
    }
  }

  Future<bool> open(String id) async {
    final gen = generation;
    if (identity == null || !foreground) return false;
    try {
      final d = await request('GET', '/v1/calls/$id');
      if (!valid(gen)) return false;
      if (active?.ended == false && active!.id != id) return false;
      apply(parse(d), show: true);
      lastSync = DateTime.now();
      error = null;
      return true;
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        notify();
      }
    }
    return false;
  }

  Future<void> tick() async {
    if (disposed ||
        identity == null ||
        (!foreground && !backgroundAudio) ||
        syncing ||
        busy)
      return;
    syncing = true;
    final gen = generation;
    try {
      if (audioLease != null) await accounts.mobile.renewAudio(audioLease!);
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
    final existing = active;
    if (existing?.incoming == true &&
        existing!.conversationId == conversationId &&
        existing.video == video) {
      await accept();
      return;
    }
    if (disposed ||
        identity == null ||
        !foreground ||
        busy ||
        active?.ended == false)
      return;
    if (accounts.voiceRoomActive || accounts.liveMediaLease != null) {
      error = 'غادر الغرفة أو البث قبل بدء المكالمة.';
      notify();
      return;
    }
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
          'خدمة المكالمات غير مفعّلة حاليًا؛ تواصل مع إدارة التطبيق.',
        );
      await releaseTail;
      await accounts.roomAudioReleased;
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
      await keepAudio(gen);
      if (!valid(gen) || active?.ended != false) return;
      await beginMedia(gen, caller: active!.isCaller);
      if (!active!.isCaller) await syncSignals(gen);
    } on AccountFailure catch (e) {
      if (valid(gen)) {
        error = e.message;
        await failed(gen);
      }
    } catch (_) {
      if (valid(gen)) {
        error = video
            ? 'تعذّر بدء المكالمة؛ اسمح بالمايك والكاميرا من إعدادات الهاتف وجرّب مرة ثانية.'
            : 'تعذّر بدء المكالمة؛ اسمح بالمايك من إعدادات الهاتف وجرّب مرة ثانية.';
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
    if (!foreground ||
        busy ||
        call == null ||
        !call.incoming ||
        !call.canControl)
      return;
    if (accounts.voiceRoomActive || accounts.liveMediaLease != null) {
      error = 'غادر الغرفة أو البث قبل قبول المكالمة.';
      notify();
      return;
    }
    final gen = generation,
        userId = accounts.user!.id,
        revision = accounts.sessionRevision;
    busy = true;
    error = null;
    notify();
    try {
      await releaseTail;
      await accounts.roomAudioReleased;
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
      await keepAudio(gen);
      if (!valid(gen) || active?.ended != false) return;
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
        error = call.video
            ? 'تعذّر الرد؛ اسمح بالمايك والكاميرا من إعدادات الهاتف وجرّب مرة ثانية.'
            : 'تعذّر الرد؛ اسمح بالمايك من إعدادات الهاتف وجرّب مرة ثانية.';
        await failed(gen);
      }
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> keepAudio(int gen) async {
    final id = active!.id;
    audioLease = id;
    final ready = await accounts.mobile.startAudio(
      id,
      'call',
      microphone: true,
    );
    if (!valid(gen) || active?.ended != false || !foreground) {
      await accounts.mobile.stopAudio(id);
      return;
    }
    backgroundAudio = ready;
    audioLease = ready ? id : null;
  }

  Future<void> beginMedia(int gen, {required bool caller}) async {
    final call = active!, engine = media!;
    after = 0;
    signalRevision = stableRevision = preparedRevision = handledMediaRevision =
        0;
    appliedRevision = -1;
    mediaNotice = null;
    mediaReady = false;
    localDescriptionSent = false;
    remoteDescriptionSet = false;
    localCandidates.clear();
    remoteCandidates.clear();
    muted = false;
    speakerOn = call.video;
    cameraOn = call.video;
    localConnected = false;
    remoteVideoReady = false;
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
      case 'media':
        if (e['remoteVideo'] is bool)
          remoteVideoReady = e['remoteVideo'] == true;
        notify();
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
        final engine = media;
        if (engine != null) {
          unawaited(engine.speaker(speakerOn).catchError((Object _) {}));
        }
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
        disconnectDeadline = Timer(const Duration(seconds: 20), () {
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
      'revision': signalRevision,
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
    final revision = signalRevision;
    signalTail = signalTail
        .then((_) async {
          if (!valid(gen) || active?.id != call.id || active!.ended) return;
          for (var attempt = 0; ; attempt++) {
            if (revision != signalRevision) return;
            try {
              await post('/v1/calls/${call.id}/signals', {
                'type': 'candidate',
                'requestId': requestId,
                'revision': revision,
                ...candidate,
              }, gen);
              break;
            } on AccountFailure catch (e) {
              if (e.code != 'NETWORK' || attempt >= 4) rethrow;
              if (!valid(gen) || active?.ended != false) return;
              reconnecting = true;
              notify();
              await Future<void>.delayed(
                Duration(milliseconds: 500 * (1 << attempt)),
              );
              if (!valid(gen) ||
                  active?.id != call.id ||
                  active?.ended != false)
                return;
            }
          }
        })
        .catchError((Object _) {
          if (valid(gen) && active?.id == call.id && active?.ended == false) {
            if (revision > 0) {
              unawaited(abortVideoChange(gen));
            } else {
              unawaited(failed(gen));
            }
          }
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
    await syncMediaChange(gen);
    if (!valid(gen) || media != engine || active?.ended != false) return;
    for (final v in d['signals'] as List) {
      final signal = v as Map<String, dynamic>, type = signal['type'];
      final revision = (signal['revision'] as num?)?.toInt() ?? 0;
      if (revision != signalRevision) {
        final change = active!.mediaChange;
        if (revision > signalRevision &&
            change?.revision == revision &&
            change!.preparing) {
          // Permission acquisition can still be in flight. Fetch this round
          // again after local video is ready instead of dropping its offer.
          break;
        }
        after = (signal['sequence'] as num).toInt();
        continue;
      }
      try {
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
      } catch (_) {
        if (revision == 0) rethrow;
        await abortVideoChange(gen);
        return;
      }
      if (!valid(gen) || media != engine) return;
      after = (signal['sequence'] as num).toInt();
    }
    await acknowledgeMediaChange(gen);
  }

  Future<void> changeKind(bool video) async {
    if (!foreground) return;
    final c = active;
    if (busy ||
        modeSyncing ||
        c == null ||
        c.state != 'connected' ||
        !c.canControl ||
        c.video == video ||
        c.mediaChange?.ongoing == true)
      return;
    final gen = generation;
    busy = true;
    mediaNotice = null;
    error = null;
    notify();
    try {
      final d = await post('/v1/calls/${c.id}/media-request', {
        'requestId': newRequestId(),
        'kind': video ? 'video' : 'audio',
      }, gen);
      if (valid(gen) && active?.id == c.id) apply(parse(d));
    } on AccountFailure catch (e) {
      if (valid(gen))
        error = e.status == 404
            ? 'تحويل المكالمات غير متاح بهذه النسخة بعد.'
            : e.message;
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> respondToVideo(bool accept) async {
    if (!foreground && accept) return;
    final c = active, change = active?.mediaChange;
    if (busy ||
        c == null ||
        change == null ||
        !change.pending ||
        change.requestedByMe ||
        !c.canControl)
      return;
    await mediaAction('media-response', {
      'requestId': change.requestId,
      'accept': accept,
    });
  }

  Future<void> cancelVideoRequest() async {
    final change = active?.mediaChange;
    if (change == null || !change.ongoing) return;
    await mediaAction('media-cancel', {'requestId': change.requestId});
  }

  Future<void> mediaAction(String action, Map<String, dynamic> body) async {
    final c = active, gen = generation;
    if (busy || c == null || c.ended) return;
    busy = true;
    notify();
    try {
      final d = await post('/v1/calls/${c.id}/$action', body, gen);
      if (valid(gen) && active?.id == c.id) apply(parse(d));
    } on AccountFailure catch (e) {
      if (valid(gen)) error = e.message;
    } finally {
      if (valid(gen)) {
        busy = false;
        notify();
      }
    }
  }

  bool sameChange(int gen, String callId, int revision) =>
      valid(gen) &&
      active?.id == callId &&
      active?.ended == false &&
      active?.mediaChange?.revision == revision;

  Future<void> syncMediaChange(int gen) async {
    final c = active, engine = media;
    var change = c?.mediaChange;
    if (!valid(gen) ||
        c == null ||
        c.ended ||
        engine == null ||
        !mediaReady ||
        change == null ||
        modeSyncing)
      return;
    modeSyncing = true;
    final token = ++modeDriveToken, revision = change.revision;
    try {
      if (!change.video &&
          change.state == 'applied' &&
          handledMediaRevision < revision) {
        await engine.setVideo(false);
        if (!sameChange(gen, c.id, revision)) return;
        cameraOn = false;
        handledMediaRevision = revision;
        mediaNotice = 'تم التحويل إلى مكالمة صوتية.';
        notify();
        return;
      }
      if (change.video &&
          !change.ongoing &&
          change.state != 'applied' &&
          handledMediaRevision < revision) {
        if (preparedRevision == revision) {
          await engine.rollback();
          await engine.setVideo(false);
          if (!sameChange(gen, c.id, revision)) return;
          cameraOn = false;
          signalRevision = stableRevision;
          localDescriptionSent = remoteDescriptionSet = true;
          localCandidates.clear();
          remoteCandidates.clear();
          preparedRevision = 0;
        }
        handledMediaRevision = revision;
        mediaNotice = switch (change.state) {
          'declined' => 'رُفض طلب الفيديو؛ المكالمة مستمرة صوتيًا.',
          'expired' => 'انتهت مهلة طلب الفيديو؛ المكالمة مستمرة صوتيًا.',
          'failed' => 'تعذّر تشغيل الكاميرا؛ المكالمة مستمرة صوتيًا.',
          _ => 'أُلغي طلب الفيديو؛ المكالمة مستمرة صوتيًا.',
        };
        notify();
        return;
      }
      if (!change.video || !change.preparing || !foreground) return;
      if (preparedRevision != revision) {
        await engine.setVideo(true);
        if (!foreground) {
          await engine.setVideo(false);
          cameraOn = false;
          await abortVideoChange(gen);
          return;
        }
        if (!sameChange(gen, c.id, revision) || media != engine) {
          if (valid(gen) && media == engine && active?.video != true) {
            await engine.setVideo(false);
          }
          return;
        }
        if (active!.mediaChange?.preparing != true) {
          await engine.setVideo(false);
          cameraOn = false;
          notify();
          return;
        }
        preparedRevision = revision;
        cameraOn = true;
        final d = await post('/v1/calls/${c.id}/media-ready', {
          'requestId': change.requestId,
          'ready': true,
        }, gen);
        if (!sameChange(gen, c.id, revision)) return;
        apply(parse(d));
        change = active!.mediaChange!;
      }
      if (change.state != 'negotiating') return;
      if (signalRevision != revision) {
        signalRevision = revision;
        localDescriptionSent = remoteDescriptionSet = false;
        localCandidates.clear();
        remoteCandidates.clear();
        try {
          await engine.speaker(true);
          if (valid(gen) && media == engine) speakerOn = true;
        } catch (_) {}
      }
      if (change.requestedByMe && !localDescriptionSent) {
        final sdp = await engine.offer();
        if (!sameChange(gen, c.id, revision)) return;
        await sendDescription('offer', sdp, gen);
      }
    } catch (_) {
      if (sameChange(gen, c.id, revision) && media == engine) {
        mediaNotice = 'تعذّر التحويل إلى فيديو؛ المكالمة مستمرة صوتيًا.';
        try {
          final d = await post('/v1/calls/${c.id}/media-ready', {
            'requestId': change!.requestId,
            'ready': false,
          }, gen);
          if (sameChange(gen, c.id, revision)) apply(parse(d));
        } catch (_) {}
        try {
          await engine.rollback();
        } catch (_) {}
        try {
          await engine.setVideo(false);
        } catch (_) {}
        if (valid(gen) && media == engine) {
          cameraOn = false;
          signalRevision = stableRevision;
          localDescriptionSent = remoteDescriptionSet = true;
          localCandidates.clear();
          remoteCandidates.clear();
          preparedRevision = 0;
        }
        notify();
      }
    } finally {
      if (modeDriveToken == token) modeSyncing = false;
    }
  }

  Future<void> acknowledgeMediaChange(int gen) async {
    final c = active, change = active?.mediaChange;
    if (!valid(gen) ||
        c == null ||
        c.ended ||
        change == null ||
        change.state != 'negotiating' ||
        signalRevision != change.revision ||
        !localDescriptionSent ||
        !remoteDescriptionSet ||
        appliedRevision == signalRevision)
      return;
    final revision = signalRevision;
    appliedRevision = revision;
    try {
      final d = await post('/v1/calls/${c.id}/media-applied', {
        'requestId': change.requestId,
      }, gen);
      if (sameChange(gen, c.id, revision)) {
        stableRevision = revision;
        mediaNotice = 'تم التحويل إلى مكالمة فيديو.';
        apply(parse(d));
      }
    } catch (_) {
      if (valid(gen) && appliedRevision == revision) appliedRevision = -1;
    }
  }

  Future<void> abortVideoChange(int gen) async {
    final c = active, engine = media, change = active?.mediaChange;
    if (!valid(gen) ||
        c == null ||
        c.ended ||
        engine == null ||
        change == null ||
        !change.preparing)
      return;
    try {
      final d = await post('/v1/calls/${c.id}/media-ready', {
        'requestId': change.requestId,
        'ready': false,
      }, gen);
      if (valid(gen) && active?.id == c.id) apply(parse(d));
    } catch (_) {}
    if (!valid(gen) || media != engine) return;
    try {
      await engine.rollback();
    } catch (_) {}
    try {
      await engine.setVideo(false);
    } catch (_) {}
    if (valid(gen) && media == engine) {
      cameraOn = false;
      signalRevision = stableRevision;
      localDescriptionSent = remoteDescriptionSet = true;
      localCandidates.clear();
      remoteCandidates.clear();
      preparedRevision = 0;
      mediaNotice = 'تعذّر التحويل إلى فيديو؛ المكالمة مستمرة صوتيًا.';
      notify();
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
    if (!foreground) return;
    await m.camera(!cameraOn);
    if (!foreground) {
      await m.setVideo(false);
      return;
    }
    if (valid(gen) && media == m) cameraOn = !cameraOn;
  });
  Future<void> switchCamera() => control((m) => m.switchCamera());
  void release() {
    final lease = audioLease;
    audioLease = null;
    backgroundAudio = false;
    if (lease != null)
      unawaited(accounts.mobile.stopAudio(lease).catchError((Object _) {}));
    if (active != null)
      unawaited(
        accounts.mobile.clearCall(active!.id).catchError((Object _) {}),
      );
    modeDriveToken++;
    modeSyncing = false;
    disconnectDeadline?.cancel();
    unawaited(mediaEvents?.cancel());
    mediaEvents = null;
    final old = media;
    media = null;
    mediaReady = false;
    localConnected = false;
    remoteVideoReady = false;
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
