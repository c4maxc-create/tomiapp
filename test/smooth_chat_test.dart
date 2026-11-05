import 'dart:async';
import 'dart:convert';
import 'package:tomi_app/src/social/social_models.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_connection.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_widgets.dart';
import 'account_fakes.dart';
import 'chat_test.dart' show ChatFakeApi, threadId, flush, setup;

class FastConnection implements ChatConnection {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  int? get closeCode => null;
  @override
  void typing(String id, bool active) {}
  @override
  Future<void> close() async {
    await bus.close();
  }
}

class FastChatApi extends ChatFakeApi {
  final socket = FastConnection();
  int inboxReads = 0, messageReads = 0;
  @override
  Future<ChatConnection> openChatConnection(String token) async => socket;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) {
    if (method == 'GET' && path == '/v1/chats') inboxReads++;
    if (method == 'GET' && path == '/v1/chats/$threadId/messages')
      messageReads++;
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class PriorityApi extends FastChatApi {
  final uploading = Completer<void>(), release = Completer<void>();
  @override
  Future<void> uploadImage(ImageUpload upload, ImageDraft image) async {
    uploading.complete();
    await release.future;
    await super.uploadImage(upload, image);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'game and room realtime events do not trigger chat inbox network refreshes',
    () async {
      final api = FastChatApi();
      final account = AccountController(
        api: api,
        vault: MemoryTokenVault('token'),
      );
      addTearDown(account.dispose);
      await account.restore();
      final chats = account.chats;
      await flush();
      api.socket.bus.add({'type': 'chat.ready'});
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final seen = <String>[];
      final sub = chats.realtimeEvents.stream.listen(
        (e) => seen.add(e['type'] as String),
      );
      addTearDown(sub.cancel);
      final before = api.inboxReads;
      for (final type in [
        'games.changed',
        'games.search.changed',
        'roulette.live',
        'voice_room.changed',
        'call.changed',
      ])
        api.socket.bus.add({'type': type});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.inboxReads, before);
      expect(seen, contains('games.changed'));
    },
  );
  test(
    'a delivered websocket message is shown without waiting for another history HTTP request',
    () async {
      final api = FastChatApi();
      api.rows.add(api.row(1));
      final account = AccountController(
        api: api,
        vault: MemoryTokenVault('token'),
        realtimeEnabled: false,
      );
      addTearDown(account.dispose);
      await account.restore();
      final thread = account.chats.thread(
        DirectConversation.fromJson(api.conversation),
      );
      await thread.sync();
      final before = api.messageReads;
      final next = api.row(2);
      thread.event({
        'type': 'chat.message',
        'conversationId': threadId,
        'message': next,
      });
      await flush();
      expect(thread.messages.map((m) => m.sequence), [1, 2]);
      expect(api.messageReads, before);
      thread.event({
        'type': 'chat.message',
        'conversationId': threadId,
        'message': next,
      });
      await flush();
      expect(thread.messages.length, 2);
    },
  );
  test('bundled GIF stickers contain multiple animation frames', () async {
    for (final id in animatedStickerIds) {
      final bytes = await rootBundle.load('assets/stickers/$id.gif');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      expect(codec.frameCount, greaterThan(1));
      codec.dispose();
    }
  });
  test(
    'a text message can finish while a large attachment upload is still pending',
    () async {
      final api = PriorityApi();
      final account = AccountController(
        api: api,
        vault: MemoryTokenVault('token'),
        realtimeEnabled: false,
      );
      addTearDown(account.dispose);
      await account.restore();
      final thread = account.chats.thread(
        DirectConversation.fromJson(api.conversation),
      );
      await thread.restored;
      thread.enqueue(
        '',
        ImageDraft(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
          ),
          'image/png',
        ),
      );
      await api.uploading.future;
      thread.enqueue('رسالة سريعة', null);
      await flush();
      expect(api.rows.any((m) => m['text'] == 'رسالة سريعة'), isTrue);
      expect(thread.pending.any((p) => p.hasMedia && p.busy), isTrue);
      api.release.complete();
      await flush();
    },
  );
  testWidgets(
    'GIF picker fits a compact enlarged-text conversation and sends an animated sticker',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (account, api, thread) = await setup();
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: PrivateChatPage(
              chats: account.chats,
              conversation: thread.conversation,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-emoji-toggle')));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text('GIF'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('GIF من جهازك'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('chat-sticker-gif_heart')));
        await tester.pump(const Duration(milliseconds: 500));
        expect(api.rows.any((m) => m['stickerId'] == 'gif_heart'), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        account.dispose();
      }
    },
  );
}
