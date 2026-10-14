import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/calling/call_controller.dart';
import 'package:tomi_app/src/calling/call_media.dart';
import 'package:tomi_app/src/calling/call_screens.dart';
import 'account_fakes.dart';
import 'package:tomi_app/src/messaging/audio_focus.dart';
import 'chat_test.dart' show ChatFakeApi, threadId;

const callId = '33333333-3333-4333-8333-333333333333';
const fakeSdp =
    'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=fingerprint:sha-256 00:11\r\n';

class FakeCallMedia implements CallMedia {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  final received = <String>[];
  Completer<void>? preparation;
  bool disposed = false,
      prepared = false,
      denied = false,
      muted = false,
      speaking = false,
      video = true;
  int switches = 0;
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> prepare(bool v) async {
    if (denied) throw StateError('permission denied');
    await preparation?.future;
    if (!disposed) prepared = true;
    video = v;
  }

  @override
  Future<void> connect(Map<String, dynamic> configuration) async {
    bus.add({
      'type': 'candidate',
      'candidate': 'candidate:local',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
    });
  }

  @override
  Future<String> offer() async => fakeSdp;
  @override
  Future<String> answer() async => fakeSdp;
  @override
  Future<void> remoteDescription(String type, String sdp) async {
    received.add(type);
  }

  @override
  Future<void> candidate(Map<String, dynamic> data) async {
    received.add('candidate');
  }

  @override
  Future<void> mute(bool value) async {
    muted = value;
  }

  @override
  Future<void> speaker(bool value) async {
    speaking = value;
  }

  @override
  Future<void> camera(bool value) async {
    video = value;
  }

  @override
  Future<void> switchCamera() async {
    switches++;
  }

  @override
  Widget view({required bool local}) =>
      ColoredBox(color: local ? Colors.purple : Colors.black);
  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    prepared = false;
    await bus.close();
  }
}

class CallFakeApi extends ChatFakeApi {
  bool caller = true, configured = true, loseStart = false, otherDevice = false;
  bool ringing = true;
  int starts = 0, seq = 0;
  Completer<void>? startGate;
  final requests = <Map<String, dynamic>>[], signals = <Map<String, dynamic>>[];
  Map<String, dynamic> call = {};
  void resetCall({bool incoming = false}) {
    caller = !incoming;
    call = {
      'id': callId,
      'conversationId': threadId,
      'kind': 'audio',
      'state': 'ringing',
      'reason': null,
      'isCaller': caller,
      'canControl': true,
      'peer': conversation['peer'],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'ringDeadline': DateTime.now()
          .add(const Duration(seconds: 35))
          .toUtc()
          .toIso8601String(),
      'acceptedAt': null,
      'connectedAt': null,
      'endedAt': null,
    };
  }

  Map<String, dynamic> snapshot() => {'call': Map<String, dynamic>.from(call)};
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!path.startsWith('/v1/calls'))
      return super.chatRequest(token, method, path, body: body, query: query);
    requests.add({
      'method': method,
      'path': path,
      'body': body == null ? null : Map<String, dynamic>.from(body),
    });
    if (path.endsWith('/settings')) return {'configured': configured};
    if (path.endsWith('/active'))
      return {
        'configured': configured,
        'call': ringing && call.isNotEmpty
            ? Map<String, dynamic>.from(call)
            : null,
      };
    if (path == '/v1/calls' && method == 'POST') {
      starts++;
      if (call.isEmpty) resetCall();
      call['kind'] = body!['kind'];
      await startGate?.future;
      if (loseStart) {
        loseStart = false;
        throw const AccountFailure('NETWORK', 'lost reply');
      }
      return snapshot();
    }
    if (path == '/v1/calls' && method == 'GET')
      return {
        'calls': call.isEmpty ? [] : [Map<String, dynamic>.from(call)],
        'nextBefore': null,
      };
    if (path.endsWith('/accept')) {
      if (otherDevice)
        throw const AccountFailure(
          'CALL_OTHER_DEVICE',
          'جهاز آخر',
          status: 409,
        );
      call['state'] = 'connecting';
      return snapshot();
    }
    if (path.endsWith('/decline') || path.endsWith('/end')) {
      call['state'] = 'ended';
      call['reason'] = path.endsWith('/decline')
          ? 'declined'
          : body?['reason'] ?? 'ended';
      return snapshot();
    }
    if (path.endsWith('/ice'))
      return {
        'configuration': {'iceServers': []},
      };
    if (path.endsWith('/signals')) {
      if (method == 'POST') {
        signals.add(Map<String, dynamic>.from(body!));
        return {'sequence': ++seq};
      }
      final after = int.parse(query?['after'] ?? '0');
      return {
        ...snapshot(),
        'signals': signals
            .where((s) => (s['sequence'] as int? ?? 0) > after)
            .toList(),
        'nextAfter': seq,
      };
    }
    if (path.endsWith('/connected')) {
      call['state'] = 'connected';
      call['connectedAt'] = DateTime.now().toUtc().toIso8601String();
      return snapshot();
    }
    return snapshot();
  }
}

Future<void> drain() async {
  for (var i = 0; i < 12; i++) await Future<void>.delayed(Duration.zero);
}

Future<(AccountController, CallController, FakeCallMedia)> setup(
  CallFakeApi api, {
  FakeCallMedia? engine,
}) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('session'),
    realtimeEnabled: false,
  );
  await a.restore();
  final m = engine ?? FakeCallMedia(),
      c = CallController(accounts: a, mediaFactory: () => m, autoPoll: false);
  return (a, c, m);
}

void cleanup(AccountController a, CallController c) {
  c.dispose();
  a.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'caller sends SDP before gathered ICE and preserves a start nonce across a lost response',
    () async {
      final api = CallFakeApi()..loseStart = true;
      final (a, c, m) = await setup(api);
      await c.start(threadId);
      await c.signalTail;
      expect(api.starts, 2);
      final starts = api.requests
          .where((r) => r['path'] == '/v1/calls' && r['method'] == 'POST')
          .toList();
      expect(starts[0]['body'], starts[1]['body']);
      expect(api.signals.map((s) => s['type']).toList(), [
        'offer',
        'candidate',
      ]);
      expect(m.prepared, isTrue);
      await c.toggleMute();
      await c.toggleSpeaker();
      expect(m.muted, isTrue);
      expect(m.speaking, isTrue);
      await c.hangup();
      await c.releaseTail;
      expect(m.disposed, isTrue);
      expect(c.active!.ended, isTrue);
      cleanup(a, c);
    },
  );
  test(
    'callee accepts before offer arrives and later polling completes the answer',
    () async {
      final api = CallFakeApi()..resetCall(incoming: true);
      final (a, c, m) = await setup(api);
      await c.tick();
      expect(c.active!.incoming, isTrue);
      expect(m.prepared, isFalse);
      await c.accept();
      expect(c.mediaReady, isTrue);
      expect(api.signals, isEmpty);
      api.signals.add({'sequence': 1, 'type': 'offer', 'sdp': fakeSdp});
      api.signals.add({
        'sequence': 2,
        'type': 'candidate',
        'candidate': 'candidate:remote',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
      await c.tick();
      await c.signalTail;
      expect(m.received, ['offer', 'candidate']);
      expect(api.signals.any((s) => s['type'] == 'answer'), isTrue);
      cleanup(a, c);
    },
  );
  test(
    'declining an incoming call never acquires microphone or camera',
    () async {
      final api = CallFakeApi()..resetCall(incoming: true);
      final (a, c, m) = await setup(api);
      await c.tick();
      await c.decline();
      expect(m.prepared, isFalse);
      expect(c.active!.reason, 'declined');
      cleanup(a, c);
    },
  );
  test(
    'permissions denied before dialing do not create a server call',
    () async {
      final api = CallFakeApi();
      final (a, c, m) = await setup(
        api,
        engine: FakeCallMedia()..denied = true,
      );
      await c.start(threadId);
      await c.releaseTail;
      expect(api.starts, 0);
      expect(c.busy, isFalse);
      expect(m.disposed, isTrue);
      expect(c.error, isNotNull);
      cleanup(a, c);
    },
  );
  test(
    'background during microphone permission cancels preparation without dialing',
    () async {
      final gate = Completer<void>(),
          api = CallFakeApi(),
          engine = FakeCallMedia()..preparation = gate;
      final (a, c, m) = await setup(api, engine: engine);
      final work = c.start(threadId);
      await drain();
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      gate.complete();
      await work;
      await c.releaseTail;
      expect(api.starts, 0);
      expect(m.disposed, isTrue);
      expect(c.busy, isFalse);
      cleanup(a, c);
    },
  );
  test(
    'a late create response after background is ended and cannot reopen media',
    () async {
      final api = CallFakeApi()..startGate = Completer<void>();
      final (a, c, m) = await setup(api);
      final work = c.start(threadId);
      await drain();
      expect(api.starts, 1);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      api.startGate!.complete();
      await work;
      await drain();
      await c.releaseTail;
      expect(api.call['state'], 'ended');
      expect(m.disposed, isTrue);
      expect(c.media, isNull);
      cleanup(a, c);
    },
  );
  test('another device winning acceptance releases the local camera', () async {
    final api = CallFakeApi()
      ..resetCall(incoming: true)
      ..otherDevice = true;
    final (a, c, m) = await setup(api);
    await c.tick();
    await c.accept();
    await c.releaseTail;
    expect(c.active!.reason, 'other_device');
    expect(m.disposed, isTrue);
    cleanup(a, c);
  });
  test(
    'account logout clears call state and releases native resources',
    () async {
      final api = CallFakeApi();
      final (a, c, m) = await setup(api);
      await c.start(threadId);
      await a.logout();
      await c.releaseTail;
      expect(c.active, isNull);
      expect(m.disposed, isTrue);
      cleanup(a, c);
    },
  );
  test('camera controls and app background end an accepted call', () async {
    final api = CallFakeApi();
    final (a, c, m) = await setup(api);
    await c.start(threadId, video: true);
    await c.toggleCamera();
    await c.switchCamera();
    expect(m.video, isFalse);
    expect(m.switches, 1);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    await drain();
    await c.releaseTail;
    expect(c.active!.ended, isTrue);
    expect(m.disposed, isTrue);
    cleanup(a, c);
  });
  test(
    'calls wait for voice recording and playback to release audio',
    () async {
      final gate = Completer<void>(), key = Object();
      voiceMediaStops[key] = () => gate.future;
      final api = CallFakeApi();
      final (a, c, m) = await setup(api);
      try {
        final work = c.start(threadId);
        await drain();
        expect(m.prepared, isFalse);
        expect(api.starts, 0);
        gate.complete();
        await work;
        expect(m.prepared, isTrue);
        expect(api.starts, 1);
      } finally {
        voiceMediaStops.remove(key);
        cleanup(a, c);
      }
    },
  );
  testWidgets(
    'incoming and video screens fit 320px with enlarged Arabic text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CallFakeApi()..resetCall(incoming: true);
      api.call['kind'] = 'video';
      final (a, c, m) = await setup(api);
      await c.tick();
      Widget page() => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: CallPage(calls: c, initialCall: c.active!),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      expect(find.byKey(const Key('call-accept')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => c.accept());
      await tester.pump();
      expect(find.byType(AspectRatio), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      cleanup(a, c);
      await tester.pump();
      expect(m.disposed, isTrue);
    },
  );
}
