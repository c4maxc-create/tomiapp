import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';

import 'account_fakes.dart';
import 'room_features_test.dart' show RichRoomApi, richRoom;
import 'rooms_test.dart' show FakeRoomAudio, roomId, peerId;

class CommerceApi extends RichRoomApi {
  CommerceApi() {
    coins = 9000;
  }
  final creations = <Map<String, dynamic>>[],
      purchases = <Map<String, dynamic>>[],
      completed = <String, Map<String, dynamic>>{};
  bool loseCreate = false, loseShop = false, rateShop = false;
  @override
  Map<String, dynamic> get snapshot {
    final d = super.snapshot;
    d['expiresAt'] = '2026-12-24T00:00:00.000Z';
    for (final m in d['members'] as List) {
      (m['user'] as Map)['avatarPreset'] = 'initials';
    }
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
    if (path == '/v1/rooms' && method == 'POST') {
      creations.add(Map.from(body!));
      completed.putIfAbsent(body['requestId'] as String, () {
        coins -= body['tier'] == 'advanced' ? 5799 : 0;
        return {
          'room': {
            ...snapshot,
            'id': body['requestId'],
            'title': body['title'],
            'tier': body['tier'],
          },
          'wallet': {'coins': coins},
        };
      });
      if (loseCreate) throw const AccountFailure('NETWORK', 'نتيجة غير مؤكدة');
      return completed[body['requestId']]!;
    }
    if (path.startsWith('/v1/rooms/purchases/')) {
      final value = completed[path.split('/').last];
      if (value == null)
        throw const AccountFailure('REQUEST_NOT_FOUND', 'لم يسجل', status: 404);
      return value;
    }
    if (path == '/v1/rooms/shop' && method == 'POST') {
      if (rateShop)
        throw const AccountFailure('RATE_LIMITED', 'انتظر', status: 429);
      purchases.add(Map.from(body!));
      completed.putIfAbsent(body['requestId'] as String, () {
        coins -= 700;
        return {
          'wallet': {'coins': coins},
          'expiresAt': '2026-11-01T12:00:00.000Z',
        };
      });
      if (loseShop) throw const AccountFailure('NETWORK', 'نتيجة غير مؤكدة');
      return completed[body['requestId']]!;
    }
    if (path == '/v1/rooms/shop' && method == 'GET')
      return {
        'items': [
          {
            'id': 'flame',
            'kind': 'frame',
            'name': 'إطار اللهب',
            'days': 7,
            'price': 700,
          },
        ],
        'owned': [],
      };
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<AccountController> account(CommerceApi api, DraftStore store) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('test-token'),
    draftStore: store,
    realtimeEnabled: false,
    roomAudioFactory: FakeRoomAudio.new,
  );
  await a.restore();
  await a.voiceRooms.restoreSavedRooms(a.voiceRooms.generation);
  return a;
}

final shot = GlobalKey();
Widget app(Widget page, {double scale = 1}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData.dark(useMaterial3: true),
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(
      c,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: RepaintBoundary(key: shot, child: child!),
  ),
  home: page,
);
Future<void> capture(WidgetTester t, String name) async {
  if (Platform.environment['TOMI_VISUAL_QA'] != '1') return;
  final b = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await b.toImage(pixelRatio: 1),
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final d = Directory('validation/1.3-voice/screens');
    await d.create(recursive: true);
    await File('${d.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['TOMI_VISUAL_QA'] != '1') return;
    final bytes = await File(
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ).readAsBytes();
    for (final name in ['Roboto', 'Ahem'])
      await (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'paid room intent survives restart and lost ACK without another charge',
    () async {
      final api = CommerceApi()..loseCreate = true, store = MemoryDraftStore();
      var a = await account(api, store);
      expect(
        await a.voiceRooms.create(
          'غرفة محفوظة',
          20,
          8,
          tier: 'advanced',
          acceptTerms: true,
        ),
        isNull,
      );
      expect(api.coins, 3201);
      final nonce = api.creations.single['requestId'];
      a.dispose();
      a = await account(api, store);
      addTearDown(a.dispose);
      api.loseCreate = false;
      expect(a.voiceRooms.pendingCreation!['requestId'], nonce);
      expect(
        await a.voiceRooms.create(
          'غرفة محفوظة',
          20,
          8,
          tier: 'advanced',
          acceptTerms: true,
        ),
        nonce,
      );
      expect(api.creations.length, 1);
      expect(api.coins, 3201);
      expect(a.voiceRooms.pendingCreation, isNull);
    },
  );
  test(
    'cosmetic purchase retries the durable request after app restart',
    () async {
      final api = CommerceApi()..loseShop = true, store = MemoryDraftStore();
      var a = await account(api, store);
      const item = {'id': 'flame', 'kind': 'frame'};
      expect(await a.voiceRooms.purchaseCosmetic(item), false);
      expect(api.coins, 8300);
      final nonce = api.purchases.single['requestId'];
      a.dispose();
      a = await account(api, store);
      addTearDown(a.dispose);
      api.loseShop = false;
      api.rateShop = true;
      expect(await a.voiceRooms.purchaseCosmetic(item), false);
      expect(a.voiceRooms.pendingCosmetic!['requestId'], nonce);
      api.rateShop = false;
      expect(await a.voiceRooms.purchaseCosmetic(item), true);
      expect(api.purchases.last['requestId'], nonce);
      expect(api.coins, 8300);
    },
  );
  test(
    'self and group gifts preserve chosen audience and price preview',
    () async {
      final (a, c, api, _) = await richRoom();
      addTearDown(a.dispose);
      expect(await c.sendGift(a.user!.id, 'diamond', 1), true);
      expect(api.sends.last['recipientId'], a.user!.id);
      expect(await c.sendGift(peerId, 'diamond', 1, audience: 'all'), true);
      expect(api.sends.last['audience'], 'all');
      expect((api.sends.last['recipientIds'] as List).length, 2);
    },
  );
  test('realtime seat change refreshes before polling interval', () async {
    final (a, c, api, _) = await richRoom();
    addTearDown(a.dispose);
    api.features['seats'] = [
      {'seat': 0, 'locked': true, 'muted': true},
    ];
    api.version++;
    a.chats.realtimeEvents.add({
      'type': 'voice_room.changed',
      'roomId': roomId,
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.active!.seatLocked(0), true);
    expect(c.active!.seatMuted(0), true);
  });
  testWidgets(
    'voice UI, paid terms, stage and gift audiences fit Arabic compact screens',
    (t) async {
      final api = CommerceApi(), a = await account(api, MemoryDraftStore());
      addTearDown(a.dispose);
      final c = a.voiceRooms;
      await c.load();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(app(Scaffold(body: VoiceRoomsScreen(accounts: a))));
      await t.pumpAndSettle();
      await capture(t, 'room-list');
      await t.tap(find.byTooltip('متجر الإطارات والدخول'));
      await t.pumpAndSettle();
      await capture(t, 'shop');
      expect(t.takeException(), isNull);
      Navigator.of(t.element(find.text('متجر الإطارات وتأثيرات الدخول'))).pop();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('create-voice-room')));
      await t.pumpAndSettle();
      await t.tap(find.text('متقدمة').last);
      await t.pumpAndSettle();
      await capture(t, 'advanced-terms');
      expect(find.byKey(const Key('advanced-room-terms')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      api.features['events'] = [
        {
          'sequence': 1,
          'kind': 'system',
          'text': 'دخول',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'actor': accountJson(),
          'effect': {'kind': 'entrance', 'styleId': 'fire'},
        },
      ];
      await c.join(roomId);
      await t.pumpWidget(app(VoiceRoomPage(controller: c)));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('room-effect-1')), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-effect-1')), findsNothing);
      await capture(t, 'advanced-stage');
      await t.tap(find.text(api.snapshot['title'] as String).first);
      await t.pumpAndSettle();
      await capture(t, 'room-info');
      expect(t.takeException(), isNull);
      Navigator.of(t.element(find.text('ترتيب الدعم • أعلى 100'))).pop();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      t.view.physicalSize = const Size(320, 760);
      await t.pumpWidget(app(VoiceRoomPage(controller: c), scale: 2));
      await t.pumpAndSettle();
      await capture(t, 'room-large-text');
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('الهدايا'));
      await t.pumpAndSettle();
      expect(find.text('نفسي'), findsOneWidget);
      await capture(t, 'gift-audience');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
