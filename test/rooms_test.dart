import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/voice_rooms/room_audio.dart';
import 'package:tomi_app/src/voice_rooms/room_controller.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';
import 'package:tomi_app/src/voice_rooms/room_models.dart';

import 'account_fakes.dart';

const roomId = '33333333-3333-4333-8333-333333333333';
const myId = '11111111-1111-4111-8111-111111111111';
const peerId = '22222222-2222-4222-8222-222222222222';

class FakeRoomAudio implements RoomAudio {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  @override
  bool canPublish = false;
  @override
  bool micEnabled = false;
  bool disposed = false;
  int enables = 0, disposals = 0;
  Completer<void>? connectionGate, micGate;
  @override
  Set<String> speakers = {};
  @override
  Set<String> liveIdentities = {};
  @override
  Set<String> openMics = {};
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> connect(Map<String, dynamic> connection) async {
    await connectionGate?.future;
  }

  @override
  Future<void> microphone(bool enabled) async {
    if (enabled) {
      await micGate?.future;
      enables++;
    }
    micEnabled = enabled && !disposed;
  }

  @override
  Future<void> speaker(bool enabled) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    micEnabled = false;
    disposals++;
  }
}

class RoomFakeApi extends AccountApi {
  RoomFakeApi() : super('https://example.com');
  int version = 1,
      joins = 0,
      leaves = 0,
      requests = 0,
      seatCount = 8,
      listReads = 0;
  String role = 'member', tier = 'advanced';
  int? seat;
  bool allowed = false, present = true, configured = true;
  String? requested;
  Completer<void>? joinGate, getGate;
  Map<String, dynamic> get snapshot => {
    'id': roomId,
    'tier': tier,
    'publicId': tier == 'advanced' ? '100001' : null,
    'title': 'سوالف الأصدقاء وأهل تومي',
    'ownerId': peerId,
    'capacity': 20,
    'seatCount': seatCount,
    'memberCount': present ? 2 : 1,
    'revision': version,
    'state': 'open',
    'canControl': present,
    'moderationPending': false,
    'members': [
      {
        'user': accountJson(id: peerId, name: 'المالك'),
        'identity': 'peer-identity',
        'role': 'owner',
        'seat': -1,
        'micAllowed': true,
      },
      if (present)
        {
          'user': accountJson(),
          'identity': 'my-identity',
          'role': role,
          'seat': seat,
          'micAllowed': allowed,
          'requestedAt': requested,
        },
    ],
  };
  Map<String, dynamic> copy() =>
      jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  @override
  Future<AccountUser> me(String token) async =>
      AccountUser.fromJson(accountJson());
  @override
  Future<void> logout(String token) async {}
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.contains('/requests/'))
      throw const AccountFailure('REQUEST_NOT_FOUND', 'Not sent', status: 404);
    if (path == '/v1/calls/active') return {'configured': true, 'call': null};
    if (path == '/v1/rooms' && method == 'GET') {
      listReads++;
      return {
        'configured': configured,
        'rooms': [copy()],
        'nextBefore': null,
      };
    }
    if (path.endsWith('/join')) {
      joins++;
      await joinGate?.future;
      return {
        'room': copy(),
        'connection': {
          'identity': 'my-identity',
          'url': 'wss://test.livekit.cloud',
          'token': 'temporary-test-token',
        },
      };
    }
    if (path.endsWith('/leave')) {
      leaves++;
      return {'room': copy()};
    }
    if (path.endsWith('/request-mic')) {
      requests++;
      requested = '2026-10-15T12:00:00.000Z';
      version++;
      return {'room': copy()};
    }
    if (path.endsWith('/cancel-request')) {
      requested = null;
      version++;
      return {'room': copy()};
    }
    if (path == '/v1/rooms/$roomId' || path.endsWith('/heartbeat')) {
      final saved = copy();
      final gate = getGate;
      getGate = null;
      await gate?.future;
      return {'room': saved};
    }
    throw AccountFailure('UNEXPECTED', 'Unexpected test request: $path');
  }
}

Future<(AccountController, VoiceRoomsController, RoomFakeApi, FakeRoomAudio)>
setup() async {
  final api = RoomFakeApi(), audio = FakeRoomAudio();
  final accounts = AccountController(
    api: api,
    vault: MemoryTokenVault('test-token'),
    realtimeEnabled: false,
    roomAudioFactory: () => audio,
  );
  await accounts.restore();
  final rooms = accounts.voiceRooms;
  return (accounts, rooms, api, audio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('joining listens without capturing mic; request and approval never auto-unmute', () async {
    final (a, c, api, audio) = await setup();
    addTearDown(() {
      c.dispose();
      a.dispose();
    });
    expect(await c.join(roomId), true);
    expect(audio.enables, 0);
    expect(c.canUseMic, false);
    await c.action('request-mic');
    expect(api.requests, 1);
    expect(audio.enables, 0);
    api.seat = 1;
    api.allowed = true;
    api.version++;
    audio.canPublish = true;
    await c.tick();
    expect(c.canUseMic, true);
    expect(audio.enables, 0);
    await c.toggleMicrophone();
    expect(audio.micEnabled, true);
    await c.toggleMicrophone();
    expect(audio.micEnabled, false);
    await c.leave();
    expect(audio.disposed, true);
    expect(api.leaves, 1);
  });
  test('demotion closes mic and a stale lower-revision response cannot restore its permission', () async {
    final (a, c, api, audio) = await setup();
    addTearDown(() {
      c.dispose();
      a.dispose();
    });
    api.seat = 1;
    api.allowed = true;
    audio.canPublish = true;
    await c.join(roomId);
    await c.toggleMicrophone();
    final old = VoiceRoom(api.copy());
    api.seat = null;
    api.allowed = false;
    api.version++;
    await c.tick();
    expect(audio.micEnabled, false);
    expect(c.canUseMic, false);
    await c.apply(old, c.generation);
    expect(c.canUseMic, false);
    expect(c.me!.seat, isNull);
  });
  test(
    'late mic permission after moderator revocation remains muted',
    () async {
      final (a, c, api, audio) = await setup();
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      api.seat = 1;
      api.allowed = true;
      audio.canPublish = true;
      await c.join(roomId);
      final gate = Completer<void>();
      audio.micGate = gate;
      final opening = c.toggleMicrophone();
      await Future<void>.delayed(Duration.zero);
      api.allowed = false;
      api.version++;
      await c.tick();
      gate.complete();
      await opening;
      expect(audio.micEnabled, false);
      expect(c.canUseMic, false);
    },
  );
  test(
    'leaving during join closes a late grant without starting the audio engine',
    () async {
      final (a, c, api, audio) = await setup();
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      final gate = Completer<void>();
      api.joinGate = gate;
      final joining = c.join(roomId);
      await Future<void>.delayed(Duration.zero);
      await c.leave();
      gate.complete();
      expect(await joining, false);
      expect(c.inRoom, false);
      expect(api.leaves, 1);
      expect(audio.enables, 0);
    },
  );
  test('background and logout stop capture and leave; microphone dialog completion cannot revive it', () async {
    final (a, c, api, audio) = await setup();
    addTearDown(() {
      c.dispose();
      a.dispose();
    });
    api.seat = 1;
    api.allowed = true;
    audio.canPublish = true;
    await c.join(roomId);
    final gate = Completer<void>();
    audio.micGate = gate;
    final opening = c.toggleMicrophone();
    await Future<void>.delayed(Duration.zero);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    gate.complete();
    await opening;
    await c.releaseTail;
    expect(c.inRoom, false);
    expect(audio.disposed, true);
    expect(audio.micEnabled, false);
    await a.logout();
    expect(c.active, isNull);
  });
  test(
    'kick removes membership and API synchronization stops the audio engine',
    () async {
      final (a, c, api, audio) = await setup();
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.join(roomId);
      api.present = false;
      api.version++;
      await c.tick();
      expect(c.active, isNull);
      expect(audio.disposed, true);
      expect(c.notice, contains('الإدارة'));
    },
  );
  test('a join snapshot after removal cannot start the media engine', () async {
    final (a, c, api, audio) = await setup();
    addTearDown(() {
      c.dispose();
      a.dispose();
    });
    api.present = false;
    api.version++;
    expect(await c.join(roomId), false);
    expect(c.active, isNull);
    expect(audio.enables, 0);
    expect(api.leaves, 1);
  });
  testWidgets('room list loads when its tab becomes visible', (tester) async {
    final (a, c, api, audio) = await setup();
    addTearDown(() {
      c.dispose();
      a.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: VoiceRoomsScreen(accounts: a, visible: false)),
    );
    await tester.pumpAndSettle();
    expect(api.listReads, 0);
    await tester.pumpWidget(
      MaterialApp(home: VoiceRoomsScreen(accounts: a, visible: true)),
    );
    await tester.pumpAndSettle();
    expect(api.listReads, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'room UI fits narrow Arabic screen and 2x text with working request and leave controls',
    (tester) async {
      final (a, c, api, audio) = await setup();
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.join(roomId);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: VoiceRoomPage(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('room-request-mic')));
      await tester.pumpAndSettle();
      expect(api.requests, 1);
      expect(audio.enables, 0);
      expect(find.byTooltip('إلغاء طلب المايك'), findsOneWidget);
      expect(find.byKey(const Key('leave-voice-room')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
