import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'package:tomi_app/src/social/post_draft_controller.dart';
import 'package:tomi_app/src/social/social_screens.dart';
import 'package:tomi_app/src/messaging/video_media.dart';
import 'package:tomi_app/src/messaging/audio_focus.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'account_fakes.dart';
import 'chat_test.dart' show ChatFakeApi, threadId, flush;
import 'room_features_test.dart' show RichRoomApi;
import 'rooms_test.dart' show FakeRoomAudio, roomId, peerId;
import 'social_test.dart' show postJson, reply;

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
);
Future<void> idle(ChatThreadController t) async {
  for (var i = 0; i < 500 && t.sending; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(t.sending, false);
}

Future<FileDraftStore> disk() async {
  final dir = await Directory.systemTemp.createTemp('tomi-drafts10-');
  addTearDown(() => dir.delete(recursive: true));
  return FileDraftStore(directory: () async => dir);
}

Future<AccountController> chatAccount(
  ChatFakeApi api,
  DraftStore store, {
  String token = 'token',
}) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault(token),
    realtimeEnabled: false,
    draftStore: store,
  );
  await a.restore();
  return a;
}

Future<ChatThreadController> thread(
  AccountController a,
  ChatFakeApi api,
) async {
  final t = a.chats.thread(DirectConversation(api.conversation));
  await t.restored;
  return t;
}

class PostService {
  final posts = <String, Map<String, dynamic>>{};
  bool lose = false;
  int sends = 0, reads = 0;
  Completer<void>? gate;
  AccountApi api() => AccountApi(
    'https://tomi.example',
    client: MockClient((r) async {
      if (r.url.path == '/v1/me') return reply({'user': accountJson()});
      if (r.url.path == '/v1/posts' && r.method == 'POST') {
        sends++;
        final d = jsonDecode(r.body) as Map<String, dynamic>,
            id = d['requestId'] as String;
        posts.putIfAbsent(id, () => postJson(text: d['text'] as String));
        await gate?.future;
        if (lose) {
          lose = false;
          throw http.ClientException('ACK lost');
        }
        return reply({'post': posts[id], 'user': accountJson()}, 201);
      }
      if (r.url.path.startsWith('/v1/posts/requests/')) {
        reads++;
        final p = posts[r.url.pathSegments.last];
        return p == null
            ? reply({
                'error': {'code': 'REQUEST_NOT_FOUND', 'message': 'not sent'},
              }, 404)
            : reply({'post': p});
      }
      return reply({
        'error': {'code': 'NOT_FOUND', 'message': 'missing'},
      }, 404);
    }),
  );
}

class ReceiptRoomApi extends RichRoomApi {
  bool acknowledge = false;
  int receipts = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.contains('/requests/')) {
      receipts++;
      if (acknowledge)
        return {
          'kind': 'gift',
          'receiptId': 'saved',
          'wallet': {'coins': 900, 'nextClaim': '2030-01-01T00:00:00Z'},
        };
      throw const AccountFailure('REQUEST_NOT_FOUND', 'not sent', status: 404);
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'a pending video play cannot resume after a background interruption',
    (tester) async {
      final old = VideoPlayerPlatform.instance, fake = _VideoPlatform();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPage(
            source: () async => Uri.parse('https://media.example/movie.mp4'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final key = Object(), gate = Completer<void>();
      voiceMediaStops[key] = () => gate.future;
      addTearDown(() => voiceMediaStops.remove(key));
      await tester.tap(find.byTooltip('تشغيل'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      gate.complete();
      await tester.pump();
      expect(fake.plays, 0);
      voiceMediaStops.remove(key);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    },
  );
  test(
    'a gift can be reconciled from the room list without joining the old room or resending',
    () async {
      final store = MemoryDraftStore(), api = ReceiptRoomApi()..failGift = true;
      final a = AccountController(
        api: api,
        vault: MemoryTokenVault('token'),
        draftStore: store,
        realtimeEnabled: false,
        roomAudioFactory: FakeRoomAudio.new,
      );
      await a.restore();
      addTearDown(a.dispose);
      final c = a.voiceRooms;
      await c.join(roomId);
      await c.sendGift(peerId, 'diamond', 1);
      await c.leave();
      expect(c.active, isNull);
      final joins = api.joins, sends = api.sends.length;
      api.acknowledge = true;
      expect(await c.resolveSavedRoom(roomId, 'gift'), true);
      expect(api.joins, joins);
      expect(api.sends.length, sends);
      expect(c.coins, 900);
      expect(c.savedRoomRequests[roomId]!['gift'], isNull);
      expect(
        (await store.read(a.draftOwnerId!, 'room:$roomId'))!['gift'],
        isNull,
      );
    },
  );
  testWidgets(
    'video never autoplays, pauses on background and releases audio for a call',
    (tester) async {
      final old = VideoPlayerPlatform.instance, fake = _VideoPlatform();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPage(
            source: () async => Uri.parse('https://media.example/movie.mp4'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.plays, 0);
      await tester.tap(find.byTooltip('تشغيل'));
      await tester.pump();
      expect(fake.plays, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(fake.playing, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.playing, false);
      await tester.tap(find.byTooltip('تشغيل'));
      await tester.pump();
      expect(fake.playing, true);
      await stopVoiceForCall();
      await tester.pump();
      expect(fake.playing, false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(fake.disposals, 1);
    },
  );
  testWidgets(
    'compact private chat retains reply and video controls above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _VideoChatApi(),
          a = await chatAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      final t = await thread(a, api);
      t.conversation = DirectConversation({
        ...api.conversation,
        'videoUploadEnabled': true,
        'pinnedMessageId': 'pinned',
      });
      t.chooseReply(ChatMessage(api.row(1)));
      await t.setAttachment(
        VideoDraft(png, durationMs: 1000, width: 320, height: 180),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatRouteObserver],
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 200),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: PrivateChatPage(chats: a.chats, conversation: t.conversation),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('إلغاء الرد'), findsOneWidget);
      await tester.tap(find.byKey(const Key('private-chat-attachment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('private-chat-video')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'disk drafts survive a new store with immutable media, cross-scope references and account isolation',
    () async {
      final store = await disk(),
          owner = draftOwner('https://tomi.example', 'one'),
          other = draftOwner('https://tomi.example', 'two'),
          media = ImageDraft(png, 'image/png'),
          key = media.contentSha256;
      await Future.wait([
        store.write(
          owner,
          'chat:a',
          {'mediaKey': key, 'text': 'أهلًا'},
          blobs: {key: png},
        ),
        store.write(owner, 'post', {'mediaKey': key}, blobs: {key: png}),
      ]);
      final reopened = FileDraftStore(directory: store.directory);
      expect((await reopened.read(owner, 'chat:a'))!['text'], 'أهلًا');
      expect(await reopened.read(other, 'chat:a'), isNull);
      await reopened.write(owner, 'chat:a', null);
      expect(await reopened.bytes(owner, key), png);
      await reopened.write(owner, 'post', null);
      await expectLater(
        reopened.bytes(owner, key),
        throwsA(isA<DraftStorageFailure>()),
      );
    },
  );
  test(
    'storage rejects missing or changed media without overwriting an older committed draft',
    () async {
      final store = await disk(), owner = draftOwner('origin', 'user');
      await store.write(owner, 'post', {'text': 'last good'});
      await expectLater(
        store.write(owner, 'post', {'mediaKey': 'a' * 64}),
        throwsA(isA<DraftStorageFailure>()),
      );
      expect((await store.read(owner, 'post'))!['text'], 'last good');
      await expectLater(
        store.write(
          owner,
          'post',
          {'mediaKey': 'a' * 64},
          blobs: {'a' * 64: png},
        ),
        throwsA(isA<DraftStorageFailure>()),
      );
      expect((await store.read(owner, 'post'))!['text'], 'last good');
    },
  );
  test(
    'a revoked storage guard cannot replace a committed account draft',
    () async {
      final store = await disk(), owner = draftOwner('origin', 'user');
      await store.write(owner, 'post', {'text': 'keep'});
      expect(
        await store.write(owner, 'post', {'text': 'late'}, valid: () => false),
        false,
      );
      expect((await store.read(owner, 'post'))!['text'], 'keep');
    },
  );
  test(
    'a corrupt journal reports an error and leaves its media intact',
    () async {
      final store = await disk(),
          owner = draftOwner('origin', 'user'),
          key = ImageDraft(png, 'image/png').contentSha256;
      await store.write(owner, 'post', {'mediaKey': key}, blobs: {key: png});
      final root = await store.directory();
      final json = File(
        '${root.path}/tomi-drafts-v1/$owner/${store.filename('post')}.json',
      );
      await json.writeAsString('{broken');
      await expectLater(
        store.read(owner, 'post'),
        throwsA(isA<DraftStorageFailure>()),
      );
      await store.write(owner, 'chat:a', {'text': 'other'});
      expect(await store.bytes(owner, key), png);
    },
  );
  test(
    'process restart reconciles a lost image send ACK without uploading or sending again',
    () async {
      final store = await disk(),
          api = ChatFakeApi()..loseReply = true,
          a = await chatAccount(api, store),
          t = await thread(a, api);
      t.enqueue('محفوظة', ImageDraft(png, 'image/png'));
      await flush();
      await idle(t);
      await t.persist();
      expect(t.pending.length, 1);
      final nonce = t.pending.single.requestId;
      a.dispose();
      final b = await chatAccount(
        api,
        FileDraftStore(directory: store.directory),
      );
      addTearDown(b.dispose);
      final restored = await thread(b, api);
      expect(restored.pending.single.requestId, nonce);
      expect(restored.pending.single.image, isNull);
      expect(restored.pending.single.hasImage, true);
      await restored.retryPending(restored.pending.single, manual: true);
      expect(
        restored.pending,
        isEmpty,
        reason: restored.pending.map((p) => p.error).join(', '),
      );
      expect(api.rows.length, 1);
      expect(api.sends, 1);
      expect(api.uploads, 1);
      expect(
        (await store.read(b.draftOwnerId!, 'chat:$threadId'))!['pending'],
        isEmpty,
      );
    },
  );
  test(
    'chat composer text, reply and selected attachment survive closing and reopening the process',
    () async {
      final store = await disk(),
          api = ChatFakeApi(),
          a = await chatAccount(api, store),
          t = await thread(a, api);
      t.setDraft('نص لم يُرسل', reply: 'reply-target');
      await t.setAttachment(ImageDraft(png, 'image/png'));
      await t.persist();
      a.dispose();
      final b = await chatAccount(
        api,
        FileDraftStore(directory: store.directory),
      );
      addTearDown(b.dispose);
      final restored = await thread(b, api);
      expect(restored.draft, 'نص لم يُرسل');
      expect(restored.replyToId, 'reply-target');
      expect(restored.draftAttachment!.media!.bytes, png);
      expect(api.sends, 0);
    },
  );
  test(
    'new login restores the old draft but disables automatic resend',
    () async {
      final store = MemoryDraftStore(),
          api = ChatFakeApi()..loseReply = true,
          a = await chatAccount(api, store),
          t = await thread(a, api);
      t.enqueue('pending', null);
      await flush();
      await t.persist();
      a.dispose();
      final b = await chatAccount(api, store, token: 'fresh-token');
      addTearDown(b.dispose);
      final restored = await thread(b, api);
      expect(restored.pending.single.autoRetry, false);
      expect(api.sends, 1);
    },
  );
  test(
    'no network send starts before the local durable commit succeeds',
    () async {
      final api = ChatFakeApi(),
          a = await chatAccount(api, _FailingStore()),
          t = await thread(a, api);
      addTearDown(a.dispose);
      t.enqueue('must keep', ImageDraft(png, 'image/png'));
      await flush();
      expect(api.prepares, 0);
      expect(api.sends, 0);
      expect(t.pending.single.text, 'must keep');
      expect(t.pending.single.error, isNotNull);
    },
  );
  test(
    'reaction revisions, quote deletion and pin revisions cannot regress after a stale refresh',
    () async {
      final api = ChatFakeApi(),
          a = await chatAccount(api, MemoryDraftStore()),
          t = await thread(a, api);
      addTearDown(a.dispose);
      t.merge([
        {
          ...api.row(1),
          'revision': 2,
          'reply': {
            'id': 'original',
            'text': 'تم حذف الرسالة',
            'deleted': true,
          },
          'reactions': [
            {'emoji': '🔥', 'count': 1, 'mine': true},
          ],
        },
      ]);
      t.merge([
        {
          ...api.row(1),
          'revision': 1,
          'reply': {'id': 'original', 'text': 'secret', 'deleted': false},
          'reactions': [],
        },
      ]);
      expect(t.messages.single.reactions.single['emoji'], '🔥');
      t.merge([
        {
          ...api.row(1),
          'revision': 2,
          'reply': {'id': 'original', 'text': 'secret', 'deleted': false},
        },
      ]);
      expect(t.messages.single.reply!['deleted'], true);
      t.apply({
        'conversation': {
          ...api.conversation,
          'featuresRevision': 2,
          'pinnedMessageId': 'new',
        },
      }, t.metadataEpoch);
      t.apply({
        'conversation': {
          ...api.conversation,
          'featuresRevision': 1,
          'pinnedMessageId': 'old',
        },
      }, t.metadataEpoch);
      expect(t.conversation.pinnedMessageId, 'new');
    },
  );
  test(
    'an uncertain post survives process restart and reconciles without a second publish',
    () async {
      final store = await disk(), service = PostService()..lose = true;
      final a = AccountController(
        api: service.api(),
        vault: MemoryTokenVault('token'),
        draftStore: store,
        realtimeEnabled: false,
      );
      await a.restore();
      final first = PostDraftController(a);
      await first.restored;
      first.editText('منشوري');
      await first.persist();
      expect(await first.publish(), isNull);
      final nonce = first.item.requestId;
      expect(first.locked, true);
      first.dispose();
      a.dispose();
      final b = AccountController(
        api: service.api(),
        vault: MemoryTokenVault('token'),
        draftStore: FileDraftStore(directory: store.directory),
        realtimeEnabled: false,
      );
      await b.restore();
      addTearDown(b.dispose);
      final restored = PostDraftController(b);
      addTearDown(restored.dispose);
      await restored.restored;
      expect(restored.item.requestId, nonce);
      restored.editText('must not mutate');
      expect(restored.item.text, 'منشوري');
      expect((await restored.publish())!.text, 'منشوري');
      expect(service.sends, 1);
      expect(service.reads, 1);
      expect(await store.read(b.draftOwnerId!, 'post'), isNull);
    },
  );
  test(
    'unsent post text and video metadata restore without publishing automatically',
    () async {
      final store = await disk(),
          service = PostService(),
          a = AccountController(
            api: service.api(),
            vault: MemoryTokenVault('token'),
            draftStore: store,
            realtimeEnabled: false,
          );
      await a.restore();
      addTearDown(a.dispose);
      final first = PostDraftController(a);
      await first.restored;
      first.editText('مسودة');
      await first.attachment(
        VideoDraft(png, durationMs: 1200, width: 320, height: 180),
      );
      await first.persist();
      first.dispose();
      final restored = PostDraftController(a);
      addTearDown(restored.dispose);
      await restored.restored;
      expect(restored.item.text, 'مسودة');
      expect(restored.item.video!.durationMs, 1200);
      expect(service.sends, 0);
    },
  );
  test(
    'restored gifts require an explicit retry and use the original receipt, nonce and amount',
    () async {
      final store = await disk(), api = ReceiptRoomApi()..failGift = true;
      Future<AccountController> account() async {
        final a = AccountController(
          api: api,
          vault: MemoryTokenVault('token'),
          draftStore: store,
          realtimeEnabled: false,
          roomAudioFactory: FakeRoomAudio.new,
        );
        await a.restore();
        return a;
      }

      final a = await account(), c = a.voiceRooms;
      expect(await c.join(roomId), true);
      expect(await c.sendGift(peerId, 'diamond', 1), false);
      final nonce = c.pendingGift!['requestId'];
      await c.persistRoom();
      a.dispose();
      api.acknowledge = true;
      api.failGift = false;
      final b = await account();
      addTearDown(b.dispose);
      expect(await b.voiceRooms.join(roomId), true);
      expect(b.voiceRooms.pendingGift!['requestId'], nonce);
      expect(api.sends.length, 2);
      expect(await b.voiceRooms.retrySend('gift'), true);
      expect(api.sends.length, 2);
      expect(b.voiceRooms.pendingGift, isNull);
      expect(b.voiceRooms.coins, 900);
    },
  );
  testWidgets(
    'the post sheet saves on close and restores editable text when reopened',
    (t) async {
      final service = PostService(),
          a = AccountController(
            api: service.api(),
            vault: MemoryTokenVault('token'),
            draftStore: MemoryDraftStore(),
            realtimeEnabled: false,
          );
      await a.restore();
      addTearDown(a.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: c,
                  isScrollControlled: true,
                  builder: (_) => SocialComposer(
                    accounts: a,
                    imageEnabled: true,
                    videoEnabled: true,
                  ),
                ),
                child: const Text('compose'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('compose'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('post-input')), 'ارجع لي');
      await t.tap(find.byTooltip('حفظ وإغلاق'));
      await t.pumpAndSettle();
      await t.tap(find.text('compose'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('post-input')))
            .controller!
            .text,
        'ارجع لي',
      );
      expect(service.sends, 0);
      await t.tap(find.byTooltip('حفظ وإغلاق'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
    },
  );
}

class _FailingStore extends MemoryDraftStore {
  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) async => throw const DraftStorageFailure('disk full');
}

class _VideoPlatform extends VideoPlayerPlatform {
  int next = 0, plays = 0, disposals = 0;
  bool playing = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => ++next;
  @override
  Stream<VideoEvent> videoEventsFor(int id) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(320, 180),
    ),
  );
  @override
  Future<void> dispose(int id) async {
    disposals++;
    playing = false;
  }

  @override
  Future<void> play(int id) async {
    plays++;
    playing = true;
  }

  @override
  Future<void> pause(int id) async {
    playing = false;
  }

  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool value) async {}
  @override
  Future<void> seekTo(int id, Duration value) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

class _VideoChatApi extends ChatFakeApi {
  @override
  Map<String, dynamic> get conversation => {
    ...super.conversation,
    'videoUploadEnabled': true,
    'pinnedMessageId': 'pinned',
  };
}
