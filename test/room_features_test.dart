import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/voice_rooms/room_controller.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';
import 'account_fakes.dart';
import 'rooms_test.dart' show RoomFakeApi, FakeRoomAudio, roomId, myId, peerId;

class RichRoomApi extends RoomFakeApi {
  final features = <String, dynamic>{
    'level': 3,
    'xp': 320,
    'remaining': 380,
    'next': 700,
    'floor': 300,
    'progress': .05,
    'background': 'ocean',
    'theme': 'gold',
    'announcement': 'هلا بكل أهل السالفة',
    'category': 'الأصدقاء',
    'companionEnabled': true,
    'chatDisabled': false,
    'imagesDisabled': false,
    'highQuality': true,
    'seats': [],
    'events': [],
  };
  final sends = <Map<String, dynamic>>[];
  bool failGift = false, ownerAbsent = false;
  Completer<void>? giftGate, giftLoadGate;
  int coins = 1000;
  @override
  Map<String, dynamic> get snapshot {
    final d = super.snapshot;
    d['features'] = Map<String, dynamic>.from(features);
    if (role == 'owner') {
      d['ownerId'] = myId;
      d['owner'] = accountJson();
      (d['members'] as List).first['role'] = 'member';
      (d['members'] as List).first['seat'] = 0;
    } else {
      d['owner'] = accountJson(id: peerId, name: 'مالك الغرفة');
    }
    if (ownerAbsent)
      (d['members'] as List).removeWhere((m) => m['role'] == 'owner');
    return d;
  }

  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/rooms/gifts') {
      await giftLoadGate?.future;
      return {
        'gifts': [
          {
            'id': 'rose',
            'name': 'وردة',
            'icon': 'rose',
            'category': 'شائعة',
            'price': 1,
          },
          {
            'id': 'diamond',
            'name': 'ألماسة',
            'icon': 'diamond',
            'category': 'مميزة',
            'price': 100,
          },
        ],
        'thresholds': [0, 100, 300, 700, 1500, 3000, 6000, 10000, 16000, 25000],
      };
    }
    if (path == '/v1/rooms/wallet')
      return {
        'wallet': {'coins': coins, 'nextClaim': '2026-10-16T10:00:00.000Z'},
      };
    if (path.endsWith('/gift')) {
      sends.add(Map<String, dynamic>.from(body!));
      await giftGate?.future;
      if (failGift) throw const AccountFailure('NETWORK', 'اتصال متقطع');
      coins -= 100;
      return {
        'room': copy(),
        'wallet': {'coins': coins, 'nextClaim': '2026-10-16T10:00:00.000Z'},
        'receiptId': 'test-receipt',
      };
    }
    if (path.endsWith('/seat-control')) {
      features['seats'] = [];
      version++;
      return {'room': copy()};
    }
    if (path.endsWith('/settings')) {
      features.addAll(body!);
      version++;
      return {'room': copy()};
    }
    if (path.endsWith('/answer-invite')) {
      features.remove('invitation');
      seat = -2;
      allowed = true;
      version++;
      return {'room': copy()};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<(AccountController, VoiceRoomsController, RichRoomApi, FakeRoomAudio)>
richRoom({bool owner = false}) async {
  final api = RichRoomApi(), audio = FakeRoomAudio();
  if (owner) {
    api.role = 'owner';
    api.seat = -1;
    api.allowed = true;
    audio.canPublish = true;
  }
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('test-token'),
    realtimeEnabled: false,
    roomAudioFactory: () => audio,
  );
  await a.restore();
  final c = a.voiceRooms;
  await c.join(roomId);
  return (a, c, api, audio);
}

Widget roomApp(Widget page, {double scale = 1}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData.dark(useMaterial3: true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'uncertain gift retries reuse the same request id and confirmed response updates wallet',
    () async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      api.failGift = true;
      expect(await c.sendGift(peerId, 'diamond', 1), false);
      expect(api.sends.length, 2);
      expect(c.pendingGift, isNotNull);
      api.failGift = false;
      expect(await c.retrySend('gift'), true);
      expect(c.pendingGift, isNull);
      expect(c.coins, 900);
      expect(api.sends.map((d) => d['requestId']).toSet().length, 1);
    },
  );
  test(
    'late gift response after leaving cannot change a newer wallet or recreate room membership',
    () async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      final gate = Completer<void>();
      api.giftGate = gate;
      c.coins = 123;
      final send = c.sendGift(peerId, 'diamond', 1);
      await Future<void>.delayed(Duration.zero);
      await c.leave();
      gate.complete();
      expect(await send, false);
      expect(c.active, isNull);
      expect(c.coins, 123);
    },
  );
  test(
    'accepting a special-seat invitation never starts microphone capture',
    () async {
      final (a, c, api, audio) = await richRoom();
      addTearDown(a.dispose);
      api.features['invitation'] = {
        'seat': -2,
        'expiresAt': '2030-01-01T00:00:00Z',
      };
      await c.tick();
      expect(c.active!.invitation, isNotNull);
      expect(await c.action('answer-invite', body: {'accept': true}), true);
      expect(c.me!.seat, -2);
      expect(audio.enables, 0);
      expect(c.microphoneOn, false);
    },
  );
  test(
    'gallery handoff mutes capture and returning does not unmute; normal background still leaves',
    () async {
      final (a, c, api, audio) = await richRoom(owner: true);
      addTearDown(a.dispose);
      await c.toggleMicrophone();
      expect(audio.micEnabled, true);
      final gate = Completer<String?>();
      final picking = c.mediaPicker(() => gate.future);
      await Future<void>.delayed(Duration.zero);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(audio.micEnabled, false);
      expect(c.active, isNotNull);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      gate.complete('test-image');
      expect(await picking, 'test-image');
      expect(c.microphoneOn, false);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await c.releaseTail;
      expect(c.active, isNull);
    },
  );
  test(
    'leaving during gift loading releases loading state and a late response cannot overwrite a new room',
    () async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      final gate = Completer<void>();
      api.giftLoadGate = gate;
      final loading = c.loadGifts();
      await Future<void>.delayed(Duration.zero);
      expect(c.extrasLoading, true);
      await c.leave();
      expect(c.extrasLoading, false);
      c.coins = 77;
      gate.complete();
      await loading;
      expect(c.coins, 77);
      expect(c.gifts, isEmpty);
      api.giftLoadGate = null;
      expect(await c.join(roomId), true);
      await c.loadGifts();
      expect(c.gifts, isNotEmpty);
    },
  );
  testWidgets(
    'owner absence keeps a reserved seat with identity visible and no claimant control',
    (tester) async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      api.ownerAbsent = true;
      api.version++;
      await c.tick();
      await tester.pumpWidget(roomApp(VoiceRoomPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('room-seat--1')), findsOneWidget);
      expect(find.text('المالك • محجوز دائمًا'), findsOneWidget);
      await tester.tap(find.byKey(const Key('room-seat--1')));
      await tester.pump();
      expect(find.textContaining('مكان المالك'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'gift picker selects recipient and gift then sends correct quantity with trial wallet',
    (tester) async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(roomApp(VoiceRoomPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الهدايا'));
      await tester.pumpAndSettle();
      expect(find.text('عملات تجريبية'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gift-diamond')));
      await tester.tap(find.byKey(const Key('send-room-gift')));
      await tester.pumpAndSettle();
      expect(api.sends.single['giftId'], 'diamond');
      expect(api.sends.single['recipientId'], peerId);
      expect(api.sends.single['quantity'], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'white room settings toggle persists and remains usable at large Arabic text',
    (tester) async {
      final (a, c, api, _) = await richRoom(owner: true);
      addTearDown(a.dispose);
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        roomApp(RoomSettingsPage(controller: c), scale: 1.8),
      );
      await tester.pumpAndSettle();
      final control = find.widgetWithText(
        SwitchListTile,
        'تعطيل الدردشة العامة',
      );
      await tester.scrollUntilVisible(control, 300);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(api.features['chatDisabled'], true);
      expect(c.active!.chatDisabled, true);
      api.features['seats'] = [
        {'seat': 0, 'muted': true, 'locked': false},
      ];
      api.version++;
      await c.tick();
      await tester.pumpWidget(roomApp(VoiceRoomPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-seat-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء كتم المقعد'));
      await tester.pumpAndSettle();
      expect(c.active!.seatMuted(0), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'room landscape and gift sheet fit narrow screen at double text size',
    (tester) async {
      final (a, c, api, _) = await richRoom(owner: true);
      addTearDown(a.dispose);
      tester.view.physicalSize = const Size(740, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(roomApp(VoiceRoomPage(controller: c)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 760);
      await tester.pumpWidget(roomApp(VoiceRoomPage(controller: c), scale: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الهدايا'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
