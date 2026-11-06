import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/accounts/account_widgets.dart';
import 'package:tomi_app/src/identity/identity_controller.dart';
import 'package:tomi_app/src/identity/identity_screens.dart';
import 'package:tomi_app/src/identity/ranking_controller.dart';
import 'package:tomi_app/src/identity/ranking_screen.dart';
import 'package:tomi_app/src/identity/room_effects.dart';
import 'package:tomi_app/src/voice_rooms/room_models.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';

import 'account_fakes.dart';
import 'room_features_test.dart' show RichRoomApi;
import 'rooms_test.dart' show FakeRoomAudio, roomId;

Map<String, dynamic> identityData({int level = 3, int revision = 0}) => {
  'level': level,
  'xp': 200,
  'floor': 200,
  'next': 500,
  'remaining': 300,
  'progress': 0,
  'revision': revision,
  'frameId': 'none',
  'portraitId': 'none',
  'entranceId': 'none',
  'badges': [
    {'id': 'first_gift', 'name': 'أول هدية', 'icon': 'gift'},
  ],
};
Map<String, dynamic> catalogData() => {
  'thresholds': [0, 50, 200, 500, 1200, 2500, 5000, 10000, 20000, 40000],
  'styles': {
    'frames': [
      {'id': 'none', 'name': 'بلا إطار', 'level': 1},
      {'id': 'rose', 'name': 'وهج الورد', 'level': 3},
      {'id': 'royal', 'name': 'التاج الملكي', 'level': 5},
    ],
    'portraits': [
      {'id': 'none', 'name': 'صورتي الحالية', 'level': 1},
      {'id': 'panda', 'name': 'باندا تومي', 'level': 3},
    ],
    'entrances': [
      {'id': 'none', 'name': 'دخول هادئ', 'level': 1},
      {'id': 'glow', 'name': 'هالة ترحيب', 'level': 2},
    ],
  },
};

class IdentityApi extends RichRoomApi {
  Map<String, dynamic> identity = identityData();
  Map<String, dynamic> preferences = {
    'favorite': false,
    'following': false,
    'followers': 0,
    'revision': 0,
  };
  final preferenceWrites = <Map<String, dynamic>>[];
  final identityWrites = <Map<String, dynamic>>[];
  final scopes = <String>[];
  final rankGates = <String, Completer<void>>{};
  Completer<void>? preferenceGate, listGate, identityGate;
  AccountFailure? identityFailure;
  bool failMe = false;
  Map<String, dynamic> get person => {
    ...accountJson(),
    'identity': {...identity},
  };
  @override
  Future<AccountUser> me(String token) async {
    if (failMe) throw const AccountFailure('NETWORK', 'Offline');
    return AccountUser.fromJson(person);
  }

  @override
  Map<String, dynamic> get snapshot => {
    ...super.snapshot,
    'preferences': {...preferences},
  };
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/identity/catalog') return catalogData();
    if (path == '/v1/me/identity') {
      identityWrites.add({...body!});
      await identityGate?.future;
      if (identityFailure != null) throw identityFailure!;
      identity = {...identity, ...body, 'revision': identity['revision'] + 1};
      return {'user': person};
    }
    if (path == '/v1/rooms' && method == 'GET') {
      final selected = query?['scope'] ?? 'all';
      scopes.add(selected);
      final data = {
        'configured': true,
        'rooms': [
          if (selected == 'all' ||
              preferences[selected == 'favorites' ? 'favorite' : 'following'] ==
                  true)
            snapshot,
        ],
        'nextBefore': null,
      };
      final gate = listGate;
      listGate = null;
      await gate?.future;
      return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    }
    if (path.endsWith('/preferences')) {
      preferenceWrites.add({...body!});
      await preferenceGate?.future;
      preferences = {
        ...preferences,
        ...body,
        'revision': preferences['revision'] + 1,
      };
      return {
        'preferences': {...preferences},
      };
    }
    if (path.contains('/ranking')) {
      final period = query?['period'] ?? 'all';
      await rankGates[period]?.future;
      return {
        'timeZone': 'Asia/Baghdad',
        'period': period,
        'leaders': [
          {
            'rank': 1,
            'user': person,
            'points': period == 'daily' ? 100 : 200,
            'gifts': 2,
          },
        ],
      };
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<AccountController> identityAccount(IdentityApi api) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('identity-test-token'),
    realtimeEnabled: false,
    roomAudioFactory: FakeRoomAudio.new,
  );
  await a.restore();
  return a;
}

RoomEvent effectEvent(int seq, {String kind = 'gift', int age = 0}) =>
    RoomEvent({
      'sequence': seq,
      'kind': kind,
      'text': kind == 'gift' ? 'ألماسة' : 'انضم',
      'actor': {
        ...accountJson(),
        'identity': {...identityData(), 'frameId': 'rose'},
      },
      'createdAt': DateTime.now()
          .subtract(Duration(seconds: age))
          .toIso8601String(),
      'gift': kind == 'gift'
          ? {
              'giftId': 'diamond',
              'quantity': 3,
              'recipient': accountJson(
                id: '22222222-2222-4222-8222-222222222222',
                name: 'نور',
              ),
            }
          : null,
      'effect': {
        'kind': kind == 'gift' ? 'gift' : 'entrance',
        'styleId': kind == 'gift' ? 'crystal' : 'royal',
      },
    });

final captureKey = GlobalKey();
Widget identityApp(Widget home, {double scale = 1, bool reduce = true}) =>
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        textTheme: ThemeData.dark(useMaterial3: true).textTheme.apply(
          fontFamily: Platform.environment['TOMI_VISUAL_QA'] == '1'
              ? 'TomiVisualArabic'
              : null,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduce,
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(key: captureKey, child: child!),
      ),
      home: home,
    );
Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['TOMI_VISUAL_QA'] != '1') return;
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../tomi11-visual');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
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
    final loader = FontLoader('TomiVisualArabic')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  test('legacy account and room snapshots retain usable defaults', () {
    final user = AccountUser.fromJson(accountJson());
    expect(user.identity.available, false);
    expect(user.identity.frameId, 'none');
    expect(user.identity.level, 1);
    final room = VoiceRoom(IdentityApi().snapshot..remove('preferences'));
    expect(room.favorite, false);
    expect(room.following, false);
    expect(room.preferenceRevision, 0);
  });
  test(
    'favorites survive a delayed list and removal is not resurrected in the filtered list',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = a.voiceRooms;
      await c.load();
      final gate = api.listGate = Completer<void>(), old = c.load();
      await c.setPreference(c.rooms.single, favorite: true);
      gate.complete();
      await old;
      expect(c.rooms.single.favorite, true);
      await c.selectScope('favorites');
      final gate2 = api.listGate = Completer<void>(), stale = c.load();
      await c.setPreference(c.rooms.single, favorite: false);
      expect(c.rooms, isEmpty);
      gate2.complete();
      await stale;
      expect(c.rooms, isEmpty);
    },
  );
  test(
    'changing room scope discards an older response and sends the selected filter',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = a.voiceRooms, gate = api.listGate = Completer<void>();
      final old = c.load();
      await c.selectScope('following');
      expect(api.scopes, ['all', 'following']);
      expect(c.rooms, isEmpty);
      gate.complete();
      await old;
      expect(c.scope, 'following');
      expect(c.rooms, isEmpty);
      expect(c.loading, false);
    },
  );
  test(
    'rapid preference taps send once and leaving clears busy state without applying the late response',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = a.voiceRooms;
      await c.load();
      await c.join(roomId);
      final gate = api.preferenceGate = Completer<void>();
      final saving = c.setPreference(c.active!, following: true);
      await c.setPreference(c.active!, favorite: true);
      expect(api.preferenceWrites.length, 1);
      expect(api.preferenceWrites.single['expectedRevision'], 0);
      expect(c.preferenceBusy, contains(roomId));
      await c.leave();
      expect(c.preferenceBusy, isEmpty);
      gate.complete();
      await saving;
      expect(c.active, isNull);
      expect(c.rooms.single.following, false);
      await c.load();
      expect(c.rooms.single.following, true);
    },
  );
  test('preference cache is cleared when the account signs out', () async {
    final api = IdentityApi(), a = await identityAccount(api);
    addTearDown(a.dispose);
    final c = a.voiceRooms;
    await c.load();
    await c.setPreference(c.rooms.single, favorite: true);
    expect(c.preferenceCache, isNotEmpty);
    await a.logout();
    expect(c.preferenceCache, isEmpty);
    expect(c.scope, 'all');
  });
  test(
    'period changes show only the latest ranking even when responses reverse',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final model = RankingController(a);
      addTearDown(model.dispose);
      final gate = api.rankGates['all'] = Completer<void>();
      final slow = model.load();
      await model.load(selected: 'daily');
      expect(model.leaders.single['points'], 100);
      gate.complete();
      await slow;
      expect(model.data!['period'], 'daily');
      expect(model.loading, false);
    },
  );
  test(
    'a failed identity save keeps the confirmed style and includes its revision',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final model = IdentityController(a);
      addTearDown(model.dispose);
      await model.load();
      api.identityFailure = const AccountFailure(
        'IDENTITY_LOCKED',
        'مغلق',
        status: 403,
      );
      await model.select('frameId', 'royal');
      expect(a.user!.identity.frameId, 'none');
      expect(model.error, 'مغلق');
      expect(api.identityWrites.single['expectedRevision'], 0);
      expect(model.saving, false);
    },
  );
  test(
    'identity revision conflict reloads the confirmed choice and handles an offline refresh',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final model = IdentityController(a);
      addTearDown(model.dispose);
      api.identity = {...identityData(revision: 2), 'frameId': 'rose'};
      api.identityFailure = const AccountFailure(
        'IDENTITY_CHANGED',
        'اختيار أحدث',
        status: 409,
      );
      await model.select('portraitId', 'panda');
      expect(a.user!.identity.revision, 2);
      expect(a.user!.identity.frameId, 'rose');
      api.failMe = true;
      await model.select('portraitId', 'panda');
      expect(model.error, contains('حدّث الصفحة'));
      expect(model.saving, false);
    },
  );
  test(
    'an identity save arriving after logout cannot restore the signed out user',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final model = IdentityController(a);
      addTearDown(model.dispose);
      final gate = api.identityGate = Completer<void>();
      final saving = model.select('frameId', 'rose');
      await a.logout();
      gate.complete();
      await saving;
      expect(a.user, isNull);
      expect(model.current, false);
    },
  );
  test(
    'room identity updates advance the level while older style and account snapshots cannot regress it',
    () async {
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final savedBio = a.user!.bio;
      a.applyRoomIdentity(
        AccountUser.fromJson({
          ...accountJson(bio: 'لقطة قديمة'),
          'identity': {
            ...identityData(level: 4, revision: 2),
            'xp': 500,
            'frameId': 'rose',
          },
        }),
      );
      expect(a.user!.identity.xp, 500);
      expect(a.user!.identity.frameId, 'rose');
      expect(a.user!.bio, savedBio);
      a.applyRoomIdentity(
        AccountUser.fromJson({...accountJson(), 'identity': identityData()}),
      );
      a.applyRoomIdentity(
        AccountUser.fromJson({
          ...accountJson(id: 'other'),
          'identity': {...identityData(level: 10, revision: 9), 'xp': 40000},
        }),
      );
      expect(a.user!.identity.xp, 500);
      expect(a.user!.identity.revision, 2);
    },
  );
  testWidgets(
    'effects skip initial history and duplicate snapshots, and cap their waiting queue',
    (tester) async {
      final c = RoomEffectsController([effectEvent(8)]);
      addTearDown(c.dispose);
      c.ingest([effectEvent(8), effectEvent(7)]);
      expect(c.active, isNull);
      c.ingest([for (var i = 9; i <= 20; i++) effectEvent(i)]);
      expect(c.waiting.length, 3);
      expect(c.active!.sequence, 17);
      c.ingest([effectEvent(20)]);
      expect(c.waiting.length, 3);
      await tester.pump(const Duration(seconds: 3));
      expect(c.active!.sequence, 18);
      c.visibility(false);
      expect(c.active, isNull);
      expect(c.waiting, isEmpty);
      c.ingest([effectEvent(21)]);
      c.visibility(true);
      c.ingest([effectEvent(21), effectEvent(22, age: 60)]);
      expect(c.active, isNull);
      c.ingest([effectEvent(23, kind: 'system')]);
      expect(c.active!.sequence, 23);
      await tester.pump(const Duration(seconds: 3));
      expect(c.active, isNull);
    },
  );
  testWidgets(
    'identity studio locks unavailable styles and saves available choices at compact size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(identityApp(IdentityStudioPage(accounts: a)));
      await tester.pumpAndSettle();
      final locked = find.byKey(const Key('identity-frames-royal'));
      await tester.ensureVisible(locked);
      await tester.tap(locked);
      await tester.pumpAndSettle();
      expect(api.identityWrites, isEmpty);
      final rose = find.byKey(const Key('identity-frames-rose'));
      await Scrollable.ensureVisible(tester.element(rose), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(rose);
      await tester.pumpAndSettle();
      expect(api.identityWrites, isEmpty);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(api.identityWrites, isEmpty);
      await tester.tap(rose);
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ الاختيار'));
      await tester.pumpAndSettle();
      expect(a.user!.identity.frameId, 'rose');
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await capture(tester, 'identity-studio');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'ranking filters fetch the selected Baghdad period and render long text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(
        identityApp(ContributionRankingPage(accounts: a), scale: 1.4),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ranking-daily')));
      await tester.pumpAndSettle();
      expect(find.textContaining('100 كوينز'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'ranking-daily');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'identity summary chips are usable outside a scaffold and respect large text',
    (tester) async {
      await tester.pumpWidget(
        identityApp(
          SingleChildScrollView(
            child: IdentitySummary(
              AccountUser.fromJson({
                ...accountJson(),
                'identity': identityData(),
              }),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('أول هدية'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'animated avatar settles with reduced motion and pauses on a disabled route',
    (tester) async {
      final user = AccountUser.fromJson({
        ...accountJson(),
        'identity': {
          ...identityData(),
          'frameId': 'rose',
          'portraitId': 'panda',
        },
      });
      await tester.pumpWidget(
        identityApp(Center(child: AccountAvatar(user, size: 100))),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(
        identityApp(
          TickerMode(
            enabled: false,
            child: Center(child: AccountAvatar(user, size: 100)),
          ),
          reduce: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'room effects fit compact screens with reduced motion and do not intercept input',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(
        identityApp(
          Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: FilledButton(
                    onPressed: () => taps++,
                    child: const Text('المايك'),
                  ),
                ),
                RoomEffectOverlay(event: effectEvent(31)),
              ],
            ),
          ),
          scale: 1.6,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('المايك'));
      expect(taps, 1);
      expect(find.text('إلى نور'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'gift-effect');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'room list favorite and follow actions use real controller state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = IdentityApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(
        identityApp(
          Scaffold(body: VoiceRoomsScreen(accounts: a, visible: true)),
        ),
      );
      await tester.pumpAndSettle();
      final star = find.byKey(const Key('favorite-room-$roomId'));
      await tester.ensureVisible(star);
      await tester.pumpAndSettle();
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(a.voiceRooms.rooms.single.favorite, true);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('room-scope-favorites'))),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room-scope-favorites')));
      await tester.pumpAndSettle();
      expect(a.voiceRooms.scope, 'favorites');
      expect(api.scopes.last, 'favorites');
      expect(tester.takeException(), isNull);
      await capture(tester, 'favorite-rooms');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
