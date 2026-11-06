import '../experience/send_invitation_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../social/social_models.dart' show newRequestId;
import '../widgets.dart';
import 'live_setup_page.dart';

class LiveHub extends StatefulWidget {
  const LiveHub({super.key, required this.accounts, this.visible = true});
  final AccountController accounts;
  final bool visible;
  @override
  State<LiveHub> createState() => _LiveHubState();
}

class _LiveHubState extends State<LiveHub> {
  List<Map<String, dynamic>> lives = [];
  bool configured = false, loading = false;
  String? error;
  Timer? timer;
  Map<String, dynamic>? pending;
  LiveSetup? setup;
  bool creating = false;
  @override
  void initState() {
    super.initState();
    if (widget.visible) unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (widget.visible) unawaited(load());
    });
  }

  @override
  void didUpdateWidget(covariant LiveHub old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) unawaited(load());
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final d = await widget.accounts.chatRequest('GET', '/v1/lives');
      if (mounted)
        setState(() {
          configured = d['configured'] == true;
          lives = (d['lives'] as List)
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
          error = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  Future<void> create() async {
    if (creating) return;
    if (widget.accounts.liveAudioBusy) {
      showNote(context, 'أنه المكالمة أو غادر الروم قبل تجهيز البث.');
      return;
    }
    if (pending == null) {
      var title = '';
      final result = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('ابدأ بثًا مباشرًا'),
          content: TextField(
            onChanged: (value) => title = value,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'عنوان البث'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, title.trim()),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      if (result.isEmpty) {
        showNote(context, 'اكتب عنوانًا للبث أولًا.');
        return;
      }
      pending = {'title': result, 'requestId': newRequestId()};
    }
    if (setup == null) {
      setup = await Navigator.push<LiveSetup>(
        context,
        MaterialPageRoute<LiveSetup>(
          builder: (_) => LiveSetupPage(
            accounts: widget.accounts,
            title: pending!['title'] as String,
          ),
        ),
      );
      if (setup == null) {
        pending = null;
        return;
      }
    }
    creating = true;
    try {
      final d = await widget.accounts.chatRequest(
        'POST',
        '/v1/lives',
        body: pending,
      );
      pending = null;
      if (mounted) await open(Map<String, dynamic>.from(d['live'] as Map));
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
    creating = false;
    setup = null;
    await load();
  }

  Future<void> open(Map<String, dynamic> live) async {
    if (widget.accounts.voiceRoomActive ||
        widget.accounts.calls.active?.ended == false) {
      showNote(context, 'غادر الروم أو أنهِ المكالمة قبل تشغيل صوت البث.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomPage(
          accounts: widget.accounts,
          initial: live,
          setup: live['isMine'] == true ? setup : null,
        ),
      ),
    );
    await load();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('LIVE • مباشر'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff5b2157), Color(0xff173e52)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.sensors, size: 34, color: Colors.pinkAccent),
                const Text(
                  'لحظتك.. على الهواء',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const Text('بث فيديو مباشر وجولات مشتركة لخمس دقائق.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: configured ? create : null,
                  icon: const Icon(Icons.videocam),
                  label: Text(
                    pending == null
                        ? 'بدء بث مباشر'
                        : 'استعادة محاولة بدء البث',
                  ),
                ),
              ],
            ),
          ),
          if (!configured)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'خدمة البث غير مفعّلة حاليًا؛ انتظر تفعيلها من إدارة التطبيق.',
              ),
            ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'البثوث الحالية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          if (lives.isEmpty) const Text('ماكو بثوث حاليًا.'),
          for (final live in lives)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.pinkAccent,
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
                title: Text(live['title'] as String),
                subtitle: Text(
                  '${(live['host'] as Map?)?['displayName'] ?? ''} • LIVE',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => open(live),
              ),
            ),
          const Divider(),
          const Text(
            'الشحن الحقيقي غير مفعّل. هدايا جولات البث تستخدم الكوينز التجريبية الحالية فقط.',
          ),
        ],
      ),
    ),
  );
}

class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({
    super.key,
    required this.accounts,
    required this.initial,
    this.setup,
  });
  final AccountController accounts;
  final Map<String, dynamic> initial;
  final LiveSetup? setup;
  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage>
    with WidgetsBindingObserver {
  late Map<String, dynamic> live = widget.initial;
  lk.Room? media;
  lk.EventsListener<lk.RoomEvent>? listener;
  Timer? poll, clock, update, tapFlush;
  final queuedTaps = <String, int>{};
  StreamSubscription<Map<String, dynamic>>? realtime;
  bool refreshing = false;
  bool disposed = false,
      busy = false,
      supporting = false,
      everPublished = false,
      microphoneOn = true,
      cameraOn = true,
      front = true;
  String? error, roomName;
  final lease = Object();
  Map<String, dynamic>? pendingSupport;
  int serverOffset = 0;
  String get id => live['id'] as String;
  bool get mine => live['isMine'] == true;
  Map? get battle => live['battle'] as Map?;
  @override
  void initState() {
    super.initState();
    microphoneOn = widget.setup?.microphone ?? true;
    front = widget.setup?.front ?? true;
    WidgetsBinding.instance.addObserver(this);
    realtime = widget.accounts.chats.realtimeEvents.stream.listen((e) {
      if (e['type'] == 'live.changed' &&
          (e['liveIds'] as List? ?? []).contains(id) &&
          update == null) {
        update = Timer(const Duration(milliseconds: 400), () {
          update = null;
          unawaited(refresh());
        });
      }
    });
    widget.accounts.liveMediaLease = lease;
    unawaited(join());
    poll = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(refresh()),
    );
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> join() async {
    if (busy || disposed) return;
    busy = true;
    try {
      final d = await widget.accounts.chatRequest(
        'POST',
        '/v1/lives/$id/join',
        body: {},
      );
      if (disposed) return;
      live = Map<String, dynamic>.from(d['live'] as Map);
      final c = Map<String, dynamic>.from(d['connection'] as Map);
      if (c['room'] == roomName &&
          media?.connectionState == lk.ConnectionState.connected)
        return;
      await listener?.dispose();
      await media?.disconnect();
      await media?.dispose();
      if (disposed) return;
      final r = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          stopLocalTrackOnUnpublish: true,
          dynacast: true,
          defaultCameraCaptureOptions: lk.CameraCaptureOptions(
            cameraPosition: front
                ? lk.CameraPosition.front
                : lk.CameraPosition.back,
            params: lk.VideoParameters(
              dimensions: lk.VideoDimensions(1280, 720),
              encoding: lk.VideoEncoding(maxBitrate: 2500000, maxFramerate: 30),
            ),
          ),
        ),
      );
      media = r;
      listener = r.createListener()
        ..on<lk.RoomEvent>((e) {
          if (mounted) setState(() {});
        });
      await r.connect(c['url'] as String, c['token'] as String);
      if (disposed) {
        await r.dispose();
        return;
      }
      roomName = c['room'] as String;
      if (c['publish'] == true) {
        await r.localParticipant?.setMicrophoneEnabled(microphoneOn);
        if (disposed) return;
        await r.localParticipant?.setCameraEnabled(cameraOn);
        everPublished = true;
      }
      error = null;
    } on AccountFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'تعذّر اتصال البث. راجع إذن الكاميرا والمايك واتصال الشبكة.';
    } finally {
      busy = false;
      if (mine && !everPublished && error != null) {
        await media?.disconnect();
        try {
          await widget.accounts.chatRequest(
            'POST',
            '/v1/lives/$id/end',
            body: {},
          );
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> refresh() async {
    if (disposed || refreshing) return;
    refreshing = true;
    try {
      if (mine &&
          (media?.connectionState != lk.ConnectionState.connected ||
              !everPublished)) {
        await join();
        if (!everPublished ||
            media?.connectionState != lk.ConnectionState.connected)
          return;
      }
      Map<String, dynamic>? next;
      final d = await widget.accounts.chatRequest(
        'POST',
        '/v1/lives/$id/heartbeat',
        body: {},
      );
      next = Map<String, dynamic>.from(d['live'] as Map);
      serverOffset =
          (d['serverNow'] as num).toInt() -
          DateTime.now().millisecondsSinceEpoch;
      if (disposed) return;
      {
        final old = battle?['state'], oldId = battle?['id'];
        live = next;
        if (old != battle?['state'] ||
            oldId != battle?['id'] ||
            media?.connectionState == lk.ConnectionState.disconnected)
          await join();
      }
      if (mounted) setState(() {});
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
      if (e.code == 'LIVE_ENDED') await media?.disconnect();
    } finally {
      refreshing = false;
    }
  }

  Future<void> control(String kind) async {
    final p = media?.localParticipant;
    if (p == null || !mine || busy) return;
    try {
      if (kind == 'mic') {
        microphoneOn = !microphoneOn;
        await p.setMicrophoneEnabled(microphoneOn);
      } else if (kind == 'camera') {
        cameraOn = !cameraOn;
        await p.setCameraEnabled(cameraOn);
      } else {
        for (final t in p.videoTrackPublications) {
          final track = t.track;
          if (track is lk.LocalVideoTrack) {
            front = !front;
            await track.setCameraPosition(
              front ? lk.CameraPosition.front : lk.CameraPosition.back,
            );
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر تغيير إعداد الصوت أو الكاميرا.');
    }
  }

  Future<void> invite() async {
    try {
      final d = await widget.accounts.chatRequest('GET', '/v1/lives');
      if (!mounted) return;
      final choices = (d['lives'] as List)
          .where((x) => (x as Map)['id'] != id)
          .toList();
      const mode = 'combined';
      final target = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (d) => StatefulBuilder(
          builder: (d, set) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('دعوة لجولة • 5 دقائق')),
                  const ListTile(
                    subtitle: Text(
                      'سكور واحد يجمع التكبيس والهدايا؛ الأعلى يفوز بعد خمس دقائق.',
                    ),
                  ),
                  if (choices.isEmpty)
                    const ListTile(title: Text('لا يوجد بث آخر حاليًا.')),
                  for (final x in choices)
                    ListTile(
                      title: Text(x['title'] as String),
                      onTap: () => Navigator.pop(d, x['id'] as String),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (target != null) {
        await widget.accounts.chatRequest(
          'POST',
          '/v1/lives/$id/invite',
          body: {'targetId': target, 'mode': mode},
        );
        await refresh();
      }
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    }
  }

  Future<void> answer(bool accept) async {
    try {
      await widget.accounts.chatRequest(
        'POST',
        '/v1/lives/battles/${battle!['id']}/${accept ? 'accept' : 'decline'}',
        body: {},
      );
      await refresh();
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    }
  }

  void queueTap(String target) {
    if (disposed || battle?['state'] != 'playing') return;
    queuedTaps[target] = ((queuedTaps[target] ?? 0) + 1).clamp(0, 30);
    tapFlush ??= Timer(const Duration(milliseconds: 300), () {
      tapFlush = null;
      unawaited(flushTaps());
    });
  }

  Future<void> flushTaps() async {
    if (disposed ||
        supporting ||
        pendingSupport != null ||
        queuedTaps.isEmpty ||
        battle?['state'] != 'playing')
      return;
    final target = queuedTaps.keys.first,
        count = queuedTaps.values.first.clamp(1, 10);
    queuedTaps[target] = queuedTaps[target]! - count;
    if (queuedTaps[target] == 0) queuedTaps.remove(target);
    await support(target, count: count);
  }

  Future<void> support(
    String target, {
    bool sendGift = false,
    int? count,
  }) async {
    if (supporting || battle?['state'] != 'playing') return;
    if (pendingSupport != null && pendingSupport!['targetId'] != target) {
      showNote(context, 'عندك دعم سابق غير مؤكد؛ استعد نفس المحاولة أولًا.');
      return;
    }
    int? gift;
    if (sendGift && pendingSupport == null) {
      gift = await showDialog<int>(
        context: context,
        builder: (d) => SimpleDialog(
          title: const Text('هدية من رصيدك التجريبي'),
          children: [
            for (final n in [100, 500, 1000])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(d, n),
                child: Text('$n كوينز • تأكيد الإرسال'),
              ),
          ],
        ),
      );
      if (gift == null) return;
    }
    pendingSupport ??= {
      'targetId': target,
      'requestId': newRequestId(),
      if (count != null) 'count': count,
      if (gift != null) 'gift': gift,
    };
    supporting = true;
    try {
      await widget.accounts.chatRequest(
        'POST',
        '/v1/lives/battles/${battle!['id']}/support',
        body: pendingSupport,
      );
      pendingSupport = null;
      await refresh();
    } on AccountFailure catch (e) {
      if (!['NETWORK'].contains(e.code)) pendingSupport = null;
      if (mounted) showNote(context, e.message);
    } finally {
      supporting = false;
      if (pendingSupport == null && !disposed && queuedTaps.isNotEmpty) {
        tapFlush ??= Timer(const Duration(milliseconds: 300), () {
          tapFlush = null;
          unawaited(flushTaps());
        });
      }
    }
  }

  Future<void> leave() async {
    if (disposed) return;
    disposed = true;
    if (identical(widget.accounts.liveMediaLease, lease))
      widget.accounts.liveMediaLease = null;
    poll?.cancel();
    clock?.cancel();
    update?.cancel();
    tapFlush?.cancel();
    unawaited(realtime?.cancel());
    await media?.disconnect();
    if (mine)
      try {
        await widget.accounts.chatRequest(
          'POST',
          '/v1/lives/$id/end',
          body: {},
        );
      } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(leave());
  }

  @override
  void dispose() {
    disposed = true;
    if (identical(widget.accounts.liveMediaLease, lease))
      widget.accounts.liveMediaLease = null;
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    clock?.cancel();
    update?.cancel();
    tapFlush?.cancel();
    unawaited(realtime?.cancel());
    unawaited(listener?.dispose());
    unawaited(media?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = <(String, lk.VideoTrack)>[];
    final r = media;
    if (r != null) {
      for (final p in <lk.Participant>[
        if (r.localParticipant != null) r.localParticipant!,
        ...r.remoteParticipants.values,
      ]) {
        for (final publication in p.videoTrackPublications) {
          final t = publication.track;
          if (t is lk.VideoTrack) tracks.add((p.identity, t));
        }
      }
    }
    if (battle != null)
      tracks.sort((a, b) {
        int rank(String identity) =>
            identity.startsWith('live-${battle!["aUserId"]}-')
            ? 0
            : identity.startsWith('live-${battle!["bUserId"]}-')
            ? 1
            : 2;
        return rank(a.$1) - rank(b.$1);
      });
    final seconds = battle == null
        ? 0
        : (((battle!['endsAt'] as num).toInt() -
                      DateTime.now().millisecondsSinceEpoch -
                      serverOffset) ~/
                  1000)
              .clamp(0, 300);
    return PopScope(
      canPop: disposed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(live['title'] as String),
          leading: IconButton(onPressed: leave, icon: const Icon(Icons.close)),
          actions: [
            if (mine)
              IconButton(
                tooltip: 'دعوة صديق لمشاهدة البث',
                icon: const Icon(Icons.person_add_alt_1),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SendInvitationPage(
                      accounts: widget.accounts,
                      kind: 'live',
                      targetId: id,
                    ),
                  ),
                ),
              ),
            if (mine)
              IconButton(
                onPressed: invite,
                icon: const Icon(Icons.group_add_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: busy
                          ? const CircularProgressIndicator()
                          : Text(
                              error ?? 'بانتظار صورة البث…',
                              style: const TextStyle(color: Colors.white),
                            ),
                    )
                  : Row(
                      children: [
                        for (final track in tracks.take(2))
                          Expanded(
                            child: lk.VideoTrackRenderer(
                              track.$2,
                              fit: lk.VideoViewFit.cover,
                            ),
                          ),
                      ],
                    ),
            ),
            if (error != null)
              ListTile(
                title: Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                trailing: TextButton(
                  onPressed: join,
                  child: const Text('إعادة الاتصال'),
                ),
              ),
            if (mine)
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => control('mic'),
                    tooltip: microphoneOn ? 'كتم المايك' : 'فتح المايك',
                    icon: Icon(
                      microphoneOn ? Icons.mic : Icons.mic_off,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => control('camera'),
                    tooltip: cameraOn ? 'إيقاف الكاميرا' : 'فتح الكاميرا',
                    icon: Icon(
                      cameraOn ? Icons.videocam : Icons.videocam_off,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => control('flip'),
                    tooltip: 'تبديل الكاميرا',
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
                ],
              ),
            if (battle != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      battle!['state'] == 'playing'
                          ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} • سكور مشترك'
                          : battle!['state'] == 'finished'
                          ? 'انتهت الجولة • ${battle!['winner'] == 'tie'
                                ? 'تعادل'
                                : battle!['winner'] == id
                                ? 'فزت'
                                : 'الفائز هو الطرف الآخر'}'
                          : 'دعوة جولة',
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    Text(
                      '${battle!['aScore']}  —  ${battle!['bScore']}',
                      style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (battle!['state'] == 'invited' &&
                        battle!['bId'] == id &&
                        mine)
                      Wrap(
                        children: [
                          FilledButton(
                            onPressed: () => answer(true),
                            child: const Text('قبول الجولة'),
                          ),
                          TextButton(
                            onPressed: () => answer(false),
                            child: const Text('رفض'),
                          ),
                        ],
                      ),
                    if (pendingSupport != null)
                      TextButton(
                        onPressed: supporting
                            ? null
                            : () => support(
                                pendingSupport!['targetId'] as String,
                              ),
                        child: const Text('استعادة الدعم السابق غير المؤكد'),
                      ),
                    if (battle!['state'] == 'playing' && !mine)
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final side in ['aId', 'bId'])
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.icon(
                                  onPressed: () =>
                                      queueTap(battle![side] as String),
                                  icon: const Icon(Icons.touch_app),
                                  label: Text(
                                    side == 'aId'
                                        ? 'كبّس للأول'
                                        : 'كبّس للثاني',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: supporting
                                      ? null
                                      : () => support(
                                          battle![side] as String,
                                          sendGift: true,
                                        ),
                                  icon: const Icon(Icons.card_giftcard),
                                  label: const Text('هدية'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    const Text(
                      'التكبيسة = نقطة • الهدية = قيمتها بالكوينز التجريبية',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'HD • جودة متكيفة مع الشبكة',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
