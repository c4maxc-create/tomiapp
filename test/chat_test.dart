import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/messaging/chat_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';

const threadId = '22222222-2222-4222-8222-222222222222';

class ChatFakeApi extends AccountApi {
  ChatFakeApi() : super('https://example.com');
  List<Map<String, dynamic>> rows = [];
  final byNonce = <String, Map<String, dynamic>>{};
  int ownRead = 0, peerRead = 0, puts = 0, uploads = 0, prepares = 0, sends = 0;
  bool blocked = false, loseReply = false, invalidUpload = false;
  Completer<void>? pausePage, pauseMetadata;
  Map<String, dynamic> get conversation => {
    'id': threadId,
    'peer': {
      'id': 'peer',
      'username': 'friend',
      'displayName': 'صديق',
      'avatarPreset': 'panda',
    },
    'updatedAt': '2026-10-13T10:00:00.000Z',
    'sequence': rows.length,
    'myReadSequence': ownRead,
    'peerReadSequence': peerRead,
    'unreadCount': rows
        .where(
          (m) =>
              m['isMine'] == false &&
              m['deleted'] == false &&
              (m['sequence'] as int) > ownRead,
        )
        .length,
    'lastMessage': rows.isEmpty ? '' : rows.last['text'],
    'blockedByMe': blocked,
    'blockedByPeer': false,
    'imageUploadEnabled': true,
  };
  Map<String, dynamic> row(int seq, {bool mine = false, String? nonce}) => {
    'id': 'message-$seq',
    'sequence': seq,
    'text': 'نص $seq',
    'requestId': nonce,
    'conversationId': threadId,
    'isMine': mine,
    'deleted': false,
    'image': null,
    'createdAt': '2026-10-13T10:00:00.000Z',
  };
  @override
  Future<AccountUser> me(String token) async =>
      AccountUser.fromJson(accountJson());
  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> uploadImage(ImageUpload upload, ImageDraft image) async {
    uploads++;
  }

  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/chats' && method == 'GET')
      return {
        'conversations': [conversation],
        'totalUnread': conversation['unreadCount'],
        'nextCursor': null,
      };
    if (path == '/v1/chats' && method == 'POST')
      return {'conversation': conversation};
    if (path.startsWith('/v1/chat/blocks/') && method == 'PUT') {
      blocked = body!['blocked'] as bool;
      return {'conversation': conversation};
    }
    if (path == '/v1/chats/$threadId' && method == 'GET') {
      final saved = {'conversation': conversation};
      final gate = pauseMetadata;
      pauseMetadata = null;
      if (gate != null) await gate.future;
      return saved;
    }
    if (path.contains('/requests/')) {
      final found = byNonce[path.split('/').last];
      if (found == null)
        throw const AccountFailure(
          'REQUEST_NOT_FOUND',
          'Not sent',
          status: 404,
        );
      return {'message': found, 'conversation': conversation};
    }
    if (path.endsWith('/read')) {
      puts++;
      ownRead = body!['sequence'] as int;
      return {'conversation': conversation};
    }
    if (path.endsWith('/images')) {
      prepares++;
      return {
        'uploadId': 'upload-$prepares',
        'uploadUrl':
            'https://test.r2.cloudflarestorage.com/bucket/image-$prepares',
        'headers': {
          'content-type': body!['contentType'],
          'content-md5': body['contentMd5'],
          'if-none-match': '*',
        },
      };
    }
    if (path.endsWith('/messages') && method == 'POST') {
      sends++;
      final nonce = body!['requestId'] as String;
      if (byNonce.containsKey(nonce))
        return {'message': byNonce[nonce], 'conversation': conversation};
      if (invalidUpload) {
        invalidUpload = false;
        throw const AccountFailure('UPLOAD_INVALID', 'جهّز الصورة مرة ثانية.');
      }
      if (blocked)
        throw const AccountFailure('CHAT_BLOCKED', 'محظور.', status: 403);
      final m = {
        ...row(rows.length + 1, mine: true, nonce: nonce),
        'text': body['text'],
        'stickerId': body['stickerId'],
      };
      rows.add(m);
      byNonce[nonce] = m;
      if (loseReply) {
        loseReply = false;
        throw const AccountFailure('NETWORK', 'انقطع الرد.');
      }
      return {'message': m, 'conversation': conversation};
    }
    if (path.endsWith('/messages') && method == 'GET') {
      final before = int.tryParse(query?['before'] ?? ''),
          after = int.tryParse(query?['after'] ?? ''),
          limit = int.parse(query?['limit'] ?? '40');
      final filtered = rows
          .where(
            (r) =>
                (before == null || (r['sequence'] as int) < before) &&
                (after == null || (r['sequence'] as int) > after),
          )
          .toList();
      final selected = after == null
          ? filtered.reversed.take(limit).toList().reversed.toList()
          : filtered.take(limit).toList();
      final result = {
        'conversation': conversation,
        'messages': jsonDecode(jsonEncode(selected)),
        'nextBefore': after == null && filtered.length > limit
            ? selected.first['sequence']
            : null,
        'nextAfter': after != null && filtered.length > limit
            ? selected.last['sequence']
            : null,
      };
      final gate = pausePage;
      pausePage = null;
      if (gate != null) await gate.future;
      return result;
    }
    if (path.contains('/messages/')) {
      final id = path.split('/').last,
          index = rows.indexWhere((m) => m['id'] == id);
      if (method == 'DELETE') {
        rows[index] = {
          ...rows[index],
          'deleted': true,
          'text': '',
          'image': null,
        };
        final nonce = rows[index]['requestId'];
        if (nonce is String) byNonce[nonce] = rows[index];
      }
      return {'conversation': conversation, 'message': rows[index]};
    }
    throw StateError('Unexpected fake route $method $path');
  }
}

Future<(AccountController, ChatFakeApi, ChatThreadController)> setup({
  int count = 0,
}) async {
  final api = ChatFakeApi();
  for (var i = 1; i <= count; i++) {
    api.rows.add(api.row(i));
  }
  final accounts = AccountController(
    api: api,
    vault: MemoryTokenVault('token'),
    realtimeEnabled: false,
  );
  await accounts.restore();
  final thread = accounts.chats.thread(
    DirectConversation.fromJson(api.conversation),
  );
  await thread.sync();
  return (accounts, api, thread);
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a lost send reply retries the original nonce without duplicating the saved message',
    () async {
      final (a, api, t) = await setup();
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      api.loseReply = true;
      t.enqueue('ثابت', null);
      await flush();
      expect(t.pending.length, 1);
      final nonce = t.pending.single.requestId;
      expect(t.pending.single.error, isNotNull);
      await t.retryPending(t.pending.single);
      expect(api.rows.length, 1);
      expect(api.rows.single['requestId'], nonce);
      expect(t.pending, isEmpty);
      expect(t.messages.single.text, 'ثابت');
    },
  );
  test('fetching in the background does not mark messages read', () async {
    final (a, api, t) = await setup(count: 2);
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    await t.markVisibleRead();
    expect(api.puts, 0);
    t.visible = true;
    a.chats.foreground = false;
    await t.markVisibleRead();
    expect(api.puts, 0);
    a.chats.foreground = true;
    t.atLatest = false;
    await t.markVisibleRead();
    expect(api.puts, 0);
    t.atLatest = true;
    await t.markVisibleRead();
    expect(api.ownRead, 2);
  });
  test(
    'an unseen later arrival remains unread until synced and viewed',
    () async {
      final (a, api, t) = await setup(count: 1);
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      t.visible = true;
      api.rows.add(api.row(2));
      await t.markVisibleRead();
      expect(api.ownRead, 1);
      await t.sync();
      await t.markVisibleRead();
      expect(api.ownRead, 2);
    },
  );
  test('image reply loss reuses its verified upload', () async {
    final (a, api, t) = await setup();
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    api.loseReply = true;
    t.enqueue(
      '',
      ImageDraft(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
        ),
        'image/png',
      ),
    );
    await flush();
    expect(t.pending.length, 1);
    await t.retryPending(t.pending.single);
    expect(api.uploads, 1);
    expect(api.prepares, 1);
    expect(api.rows.length, 1);
  });
  test('an explicit invalid upload permits preparation again', () async {
    final (a, api, t) = await setup();
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    api.invalidUpload = true;
    t.enqueue(
      '',
      ImageDraft(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
        ),
        'image/png',
      ),
    );
    await flush();
    expect(t.pending.single.upload, isNull);
    await t.retryPending(t.pending.single);
    expect(api.prepares, 2);
    expect(api.rows.length, 1);
  });
  test('blocking disables sending while retaining history', () async {
    final (a, api, t) = await setup(count: 1);
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    await t.setBlocked(true);
    t.enqueue('ممنوع', null);
    expect(t.conversation.canSend, isFalse);
    expect(t.pending, isEmpty);
    expect(t.messages.length, 1);
    await t.setBlocked(false);
    expect(t.conversation.canSend, isTrue);
  });
  test('a stale history response cannot restore a deleted message', () async {
    final (a, api, t) = await setup();
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    t.enqueue('احذفني', null);
    await flush();
    final gate = Completer<void>();
    api.pausePage = gate;
    final stale = t.sync(reconcile: true);
    await flush();
    await t.deleteMessage(t.messages.single);
    gate.complete();
    await stale;
    expect(t.messages.single.deleted, isTrue);
    expect(t.messages.single.text, isEmpty);
  });
  test('stale metadata cannot undo a newer block', () async {
    final (a, api, t) = await setup(count: 600);
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    for (var i = 0; i < 13; i++) {
      await t.loadOlder();
    }
    expect(t.historyWindow, isTrue);
    final gate = Completer<void>();
    api.pauseMetadata = gate;
    final stale = t.sync();
    await flush();
    await t.setBlocked(true);
    gate.complete();
    await stale;
    expect(t.conversation.blockedByMe, isTrue);
  });
  test(
    'bounded history reaches the oldest message and returns to latest',
    () async {
      final (a, api, t) = await setup(count: 600);
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      while (t.nextBefore != null) {
        await t.loadOlder();
        expect(t.messages.length, lessThanOrEqualTo(500));
      }
      expect(t.messages.first.sequence, 1);
      expect(t.historyWindow, isTrue);
      await t.showLatest();
      expect(t.highestSequence, 600);
      expect(t.historyWindow, isFalse);
    },
  );
  test(
    'logout discards private cached history and ignores a late response',
    () async {
      final (a, api, t) = await setup(count: 1);
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      final gate = Completer<void>();
      api.pausePage = gate;
      final stale = t.sync(reconcile: true);
      await flush();
      await a.logout();
      gate.complete();
      await stale;
      expect(t.disposed, isTrue);
      expect(t.messages, isEmpty);
      expect(a.chats.totalUnread, 0);
    },
  );
  testWidgets(
    'compact chat sends, reads and deletes with the keyboard visible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (a, api, t) = await setup(count: 1);
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatRouteObserver],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 250),
              textScaler: const TextScaler.linear(1.4),
            ),
            child: child!,
          ),
          home: PrivateChatPage(chats: a.chats, conversation: t.conversation),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.ownRead, 1);
      await tester.enterText(
        find.byKey(const Key('private-chat-input')),
        'مرحبا',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('private-chat-send')));
      await tester.pumpAndSettle();
      expect(api.rows.last['text'], 'مرحبا');
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(ValueKey('message-options:${api.rows.last['id']}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف الرسالة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(api.rows.last['deleted'], isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets('a failed bubble can retry and clear the error', (tester) async {
    final (a, api, t) = await setup();
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    api.loseReply = true;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [chatRouteObserver],
        home: PrivateChatPage(chats: a.chats, conversation: t.conversation),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('private-chat-input')),
      'retry',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('private-chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(api.rows.length, 1);
    expect(t.pending, isEmpty);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
  });
  testWidgets('old history has a compact route back to latest messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (a, api, t) = await setup(count: 600);
    addTearDown(() {
      if (!a.chats.disposed) a.dispose();
    });
    for (var i = 0; i < 13; i++) {
      await t.loadOlder();
    }
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [chatRouteObserver],
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: PrivateChatPage(chats: a.chats, conversation: t.conversation),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.ownRead, 0);
    expect(find.byKey(const Key('chat-show-latest')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('chat-show-latest')));
    await tester.pumpAndSettle();
    expect(t.highestSequence, 600);
    expect(t.historyWindow, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
  });
  testWidgets(
    'landscape attachment composer fits large text above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (a, api, t) = await setup();
      addTearDown(() {
        if (!a.chats.disposed) a.dispose();
      });
      final picture = XFile.fromData(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
        ),
        mimeType: 'image/png',
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatRouteObserver],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 190),
              textScaler: const TextScaler.linear(1.8),
            ),
            child: child!,
          ),
          home: PrivateChatPage(
            chats: a.chats,
            conversation: t.conversation,
            initialImage: picture,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('private-chat-input')),
        'رسالة طويلة\nأكثر من سطر\nوتجربة الكيبورد',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump();
      await tester.tap(find.byKey(const Key('private-chat-send')));
      await tester.pumpAndSettle();
      expect(api.rows.length, 1);
      expect(api.uploads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}
