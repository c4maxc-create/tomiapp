import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/avatar_editor.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/notifications/push_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'chat_test.dart' show ChatFakeApi, threadId, flush;

class MediaFake extends ChatFakeApi {
  final bodies = <Map<String, dynamic>>[];
  bool failUpload = false, failAvatar = false;
  @override
  Map<String, dynamic> get conversation => {
    ...super.conversation,
    'audioUploadEnabled': true,
  };
  @override
  Future<void> uploadImage(ImageUpload u, ImageDraft d) async {
    if (failUpload) throw const AccountFailure('NETWORK', 'انقطع الرفع.');
    await super.uploadImage(u, d);
  }

  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/audio') || path == '/v1/me/avatar/uploads') {
      prepares++;
      return {
        'uploadId': 'upload-$prepares',
        'uploadUrl': 'https://test.r2.cloudflarestorage.com/bucket/media',
        'headers': {
          'content-type': body!['contentType'],
          'content-md5': body['contentMd5'],
          'if-none-match': '*',
        },
      };
    }
    if (path == '/v1/me/avatar') {
      bodies.add({...body!});
      if (failAvatar) {
        failAvatar = false;
        throw const AccountFailure('NETWORK', 'انقطع الرد.');
      }
      return {
        'user': {...accountJson(), 'avatarId': body['imageUploadId']},
      };
    }
    try {
      return await super.chatRequest(
        token,
        method,
        path,
        body: body,
        query: query,
      );
    } finally {
      if (method == 'POST' &&
          path.endsWith('/messages') &&
          body?['audioUploadId'] != null) {
        bodies.add({...body!});
        for (final row in rows) {
          if (row['requestId'] == body['requestId'])
            row['audio'] = {
              'url': 'https://test.r2.cloudflarestorage.com/bucket/voice',
              'durationMs': 5000,
            };
        }
      }
    }
  }
}

Future<AccountController> ready(ChatFakeApi api) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('session'),
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

class PushFakeApi extends ChatFakeApi {
  bool enabled = true;
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.startsWith('/v1/push/')) {
      requests.add('$method $path');
      if (path.endsWith('/settings')) {
        if (method == 'PUT') enabled = body!['enabled'] as bool;
        return {'configured': true, 'enabled': enabled};
      }
      return {'configured': true, 'ok': true};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class FakeDevice implements PushDeviceClient {
  bool allowed = false;
  int permissionRequests = 0, deleted = 0;
  Completer<String?>? delayedToken;
  final changes = StreamController<String>.broadcast(),
      opens = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Future<bool> initialize() async => true;
  @override
  Future<bool> permission({bool request = false}) async {
    if (request) {
      permissionRequests++;
      allowed = true;
    }
    return allowed;
  }

  @override
  Future<String?> token() async => delayedToken != null
      ? await delayedToken!.future
      : 'test_device_token_123456789';
  @override
  Future<void> deleteToken() async {
    deleted++;
  }

  @override
  Stream<String> get tokenChanges => changes.stream;
  @override
  Stream<Map<String, dynamic>> get opened => opens.stream;
  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;
  @override
  String get platform => 'android';
  Future<void> close() async {
    await changes.close();
    await opens.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('voice lost replies retry the same upload and nonce', () async {
    final api = MediaFake(), a = await ready(api);
    addTearDown(a.dispose);
    final t = a.chats.thread(DirectConversation(api.conversation));
    await t.sync();
    api.loseReply = true;
    t.enqueue('', null, audio: AudioDraft(Uint8List.fromList([1, 2, 3]), 5000));
    await flush();
    expect(t.pending.single.audio, isNotNull);
    final nonce = t.pending.single.requestId;
    await t.retryPending(t.pending.single);
    expect(api.prepares, 1);
    expect(api.uploads, 1);
    expect(api.rows.length, 1);
    expect(api.bodies.map((x) => x['requestId']).toSet(), {nonce});
    expect(api.bodies.map((x) => x['audioUploadId']).toSet(), {'upload-1'});
    expect(t.pending, isEmpty);
    expect(t.messages.single.audio!.durationMs, 5000);
  });
  test('pending voices share the bounded private-draft memory limit', () async {
    final api = MediaFake()..failUpload = true, a = await ready(api);
    addTearDown(a.dispose);
    final t = a.chats.thread(DirectConversation(api.conversation));
    await t.sync();
    final bytes = Uint8List(6 * 1024 * 1024);
    for (var i = 0; i < 3; i++) {
      t.enqueue('', null, audio: AudioDraft(bytes, 5000));
      await flush();
    }
    expect(
      () => t.enqueue('', null, audio: AudioDraft(bytes, 5000)),
      throwsA(isA<AccountFailure>()),
    );
    expect(t.pending.length, 3);
  });
  testWidgets(
    'voice controls fit a compact chat with enlarged text without initializing a player',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = MediaFake();
      api.rows.add({
        ...api.row(1),
        'audio': {
          'url': 'https://test.r2.cloudflarestorage.com/bucket/voice',
          'durationMs': 5000,
        },
      });
      final a = await ready(api);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: PrivateChatPage(
            chats: a.chats,
            conversation: DirectConversation(api.conversation),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('رسالة صوتية'), findsOneWidget);
      expect(find.byKey(const Key('private-chat-voice')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  test(
    'push asks permission explicitly, registers and detaches when disabled',
    () async {
      final api = PushFakeApi(),
          a = await ready(api),
          device = FakeDevice(),
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await flush();
      expect(device.permissionRequests, 0);
      expect(api.requests.where((r) => r == 'PUT /v1/push/device'), isEmpty);
      await push.setEnabled(true);
      expect(device.permissionRequests, 1);
      expect(api.requests.where((r) => r == 'PUT /v1/push/device').length, 1);
      await push.setEnabled(false);
      expect(device.deleted, 1);
      expect(api.requests, contains('DELETE /v1/push/device'));
    },
  );
  test(
    'notification taps match the signed-in account and validate the thread',
    () async {
      final api = PushFakeApi(),
          a = await ready(api),
          device = FakeDevice(),
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await flush();
      var opened = 0;
      push.onOpen = (id, user) async {
        opened++;
      };
      push.handleOpen({
        'type': 'chat',
        'conversationId': threadId,
        'accountId': 'someone-else',
      });
      push.handleOpen({
        'type': 'chat',
        'conversationId': 'bad',
        'accountId': a.user!.id,
      });
      await flush();
      expect(opened, 0);
      push.handleOpen({
        'type': 'chat',
        'conversationId': threadId,
        'accountId': a.user!.id,
      });
      await flush();
      expect(opened, 1);
    },
  );
  test(
    'a late FCM token after logout cannot attach to the previous account',
    () async {
      final api = PushFakeApi(),
          a = await ready(api),
          device = FakeDevice()
            ..allowed = true
            ..delayedToken = Completer<String?>(),
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await flush();
      await a.logout();
      device.delayedToken!.complete('late_device_token_123456789');
      await flush();
      expect(api.requests.where((r) => r == 'PUT /v1/push/device'), isEmpty);
      expect(push.registeredToken, isNull);
    },
  );
  testWidgets(
    'avatar retries a lost save reply using the same uploaded image and nonce',
    (tester) async {
      final api = MediaFake()..failAvatar = true, a = await ready(api);
      final image = XFile.fromData(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
        ),
        name: 'avatar.png',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AvatarEditorPage(accounts: a, initialImage: image),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar-save')));
      await tester.pumpAndSettle();
      expect(find.text('انقطع الرد.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('avatar-save')));
      await tester.pumpAndSettle();
      expect(api.uploads, 1);
      expect(api.prepares, 1);
      expect(api.bodies.map((d) => d['requestId']).toSet().length, 1);
      expect(a.user!.avatarId, 'upload-1');
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}
