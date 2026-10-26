import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/notifications/push_controller.dart';
import 'package:tomi_app/src/notifications/notification_settings.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';

import 'calls_test.dart' show drain;
import 'media05_test.dart' show PushFakeApi, FakeDevice;
import 'account_fakes.dart' show MemoryTokenVault;
import 'voice13_test.dart' show CommerceApi, account, app, capture;

class RetryFirebase extends FirebasePushDeviceClient {
  int attempts = 0;
  Completer<bool>? gate;
  @override
  Future<bool> initializeFirebase() async {
    attempts++;
    if (gate != null) return gate!.future;
    return attempts > 1;
  }
}

class SetupDevice extends FakeDevice {
  bool available = false;
  int attempts = 0;
  @override
  Future<bool> initialize() async {
    attempts++;
    return available;
  }
}

class SetupApi extends PushFakeApi {
  bool serverReady = true, acceptsDevice = true;
  int registrations = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/push/settings') {
      if (method == 'PUT') enabled = body!['enabled'] as bool;
      return {'configured': serverReady, 'enabled': enabled};
    }
    if (path == '/v1/push/device' && method == 'PUT') {
      registrations++;
      return {'configured': acceptsDevice, 'bindingId': 'binding132'};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<AccountController> ready(SetupApi api) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('session'),
    draftStore: MemoryDraftStore(),
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

class OpeningApi extends CommerceApi {
  Completer<void>? listGate, walletGate;
  bool serviceReady = false, rejectCreation = false;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'GET' && path == '/v1/rooms') {
      await listGate?.future;
      return {
        ...await super.chatRequest(
          token,
          method,
          path,
          body: body,
          query: query,
        ),
        'configured': serviceReady,
      };
    }
    if (method == 'GET' && path == '/v1/rooms/wallet') await walletGate?.future;
    if (method == 'POST' && path == '/v1/rooms' && rejectCreation) {
      throw const AccountFailure(
        'ROOMS_DISABLED',
        'خدمة الصوت غير مفعّلة حاليًا.',
        status: 503,
      );
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['TOMI_VISUAL_QA'] != '1') return;
    final bytes = await File(
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ).readAsBytes();
    for (final name in ['Roboto', 'Ahem']) {
      await (FontLoader(
        name,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'Firebase native initialization shares an active attempt and retries a failed attempt',
    () async {
      final c = RetryFirebase()..gate = Completer<bool>();
      final first = c.initialize(), second = c.initialize();
      expect(c.attempts, 1);
      c.gate!.complete(false);
      expect(await first, isFalse);
      expect(await second, isFalse);
      c.gate = null;
      expect(await c.initialize(), isTrue);
      expect(await c.initialize(), isTrue);
      expect(c.attempts, 2);
    },
  );
  test(
    'notification refresh recovers native setup and registers the device with its session binding',
    () async {
      final api = SetupApi(),
          a = await ready(api),
          device = SetupDevice()..allowed = true;
      final push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await drain();
      await push.connect();
      expect(push.clientReady, isFalse);
      expect(push.configured, isTrue);
      expect(push.registeredToken, isNull);
      device.available = true;
      await push.connect();
      expect(push.clientReady, isTrue);
      expect(push.registeredToken, isNotNull);
      expect(push.registeredBinding, 'binding132');
      expect(push.error, isNull);
    },
  );
  test(
    'a server that declines registration cannot show notifications as activated',
    () async {
      final api = SetupApi()..acceptsDevice = false,
          a = await ready(api),
          device = SetupDevice()
            ..available = true
            ..allowed = true;
      final push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await drain();
      await push.connect();
      expect(api.registrations, greaterThan(0));
      expect(push.registeredToken, isNull);
      expect(push.configured, isFalse);
      expect(push.error, contains('الخادم'));
    },
  );
  test(
    'enabling requests phone permission and disabling unregisters the existing token',
    () async {
      final api = SetupApi()..enabled = false,
          a = await ready(api),
          device = SetupDevice()..available = true;
      final push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await drain();
      await push.connect();
      expect(push.registeredToken, isNull);
      await push.setEnabled(true);
      expect(device.permissionRequests, 1);
      expect(push.registeredToken, isNotNull);
      await push.setEnabled(false);
      expect(api.enabled, isFalse);
      expect(push.registeredToken, isNull);
      expect(device.deleted, 1);
    },
  );
  testWidgets(
    'missing notification setup remains retryable and explains client and server states',
    (t) async {
      if (Platform.environment['TOMI_VISUAL_QA'] == '1') {
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));
      }
      final api = SetupApi()..serverReady = false,
          a = await ready(api),
          device = SetupDevice();
      final push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await t.pump();
      await push.connect();
      await t.pumpWidget(app(NotificationSettingsPage(controller: push)));
      await t.pumpAndSettle();
      expect(find.text('إعداد إشعارات التطبيق غير مكتمل'), findsOneWidget);
      expect(find.text('خدمة إشعارات الخادم غير مفعّلة'), findsOneWidget);
      final before = device.attempts;
      await t.tap(find.byKey(const Key('push-enabled')));
      await t.pumpAndSettle();
      expect(device.attempts, greaterThan(before));
      await capture(t, 'fix132-notifications-setup');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'plus opens immediately during slow room and wallet reads; form survives the late balance',
    (t) async {
      if (Platform.environment['TOMI_VISUAL_QA'] == '1') {
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));
      }
      final api = OpeningApi()
        ..listGate = Completer<void>()
        ..walletGate = Completer<void>();
      final a = await account(api, MemoryDraftStore()), c = a.voiceRooms;
      addTearDown(a.dispose);
      final loading = c.load();
      await t.pumpWidget(
        app(Scaffold(body: VoiceRoomsScreen(accounts: a, visible: false))),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('create-voice-room')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(find.text('غرفة جديدة'), findsOneWidget);
      expect(find.byKey(const Key('voice-room-title')).hitTestable(), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('voice-room-title')),
        'غرفة بدون انتظار',
      );
      await capture(t, 'fix132-room-form-loading');
      api.listGate!.complete();
      api.walletGate!.complete();
      await loading;
      await t.pumpAndSettle();
      expect(find.text('غرفة بدون انتظار'), findsOneWidget);
      expect(find.text('رصيدك: 9000 كوينز'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unconfigured service never makes plus inert; a definitive 503 clears the uncharged intent',
    (t) async {
      if (Platform.environment['TOMI_VISUAL_QA'] == '1') {
        await t.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => t.binding.setSurfaceSize(null));
      }
      final api = OpeningApi()..rejectCreation = true,
          a = await account(api, MemoryDraftStore()),
          c = a.voiceRooms;
      addTearDown(a.dispose);
      await c.load();
      await t.pumpWidget(app(Scaffold(body: VoiceRoomsScreen(accounts: a))));
      await t.pumpAndSettle();
      await capture(t, 'fix132-readable-room-status');
      await t.tap(find.byKey(const Key('create-voice-room')));
      await t.pumpAndSettle();
      expect(find.text('غرفة جديدة'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('voice-room-title')),
        'غرفة الأصدقاء',
      );
      await t.ensureVisible(find.byKey(const Key('submit-voice-room')));
      await t.tap(find.byKey(const Key('submit-voice-room')));
      await t.pumpAndSettle();
      expect(c.pendingCreation, isNull);
      expect(api.coins, 9000);
      expect(api.creations, isEmpty);
      expect(find.text('خدمة الصوت غير مفعّلة حاليًا.'), findsOneWidget);
      api.rejectCreation = false;
      api.serviceReady = true;
      await c.load();
      await t.tap(find.byKey(const Key('create-voice-room')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('voice-room-title')),
        'غرفة الأصدقاء',
      );
      await t.ensureVisible(find.byKey(const Key('submit-voice-room')));
      await t.tap(find.byKey(const Key('submit-voice-room')));
      await t.pumpAndSettle();
      expect(api.creations.single['tier'], 'free');
      expect(c.active, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
