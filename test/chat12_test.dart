import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/messaging/chat_groups.dart';
import 'package:tomi_app/src/messaging/chat_widgets.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as old;
import 'messaging10_test.dart' show chatAccount, thread;

const peer1 = '33333333-3333-4333-8333-333333333333',
    peer2 = '44444444-4444-4444-8444-444444444444',
    gid = '55555555-5555-4555-8555-555555555555';

class Chat12Api extends old.ChatFakeApi {
  final fileNames = <String, String>{};
  bool memberLeft = false;
  int groups = 0;
  bool loseGroupReply = false;
  Completer<void>? groupGate;
  final groupNonces = <String>[];
  Map<String, dynamic>? created;
  Completer<void>? uploadGate;
  @override
  Map<String, dynamic> get conversation => {
    ...super.conversation,
    'peer': {
      'id': peer1,
      'username': 'ali',
      'displayName': 'علي حسن',
      'avatarPreset': 'initials',
    },
    'lastMessage': 'أهلًا، شلونك؟',
    'lastMessageAt': '2026-10-24T12:45:00.000Z',
    'updatedAt': '2026-10-24T12:45:00.000Z',
    'audioUploadEnabled': true,
    'videoUploadEnabled': true,
    'fileUploadEnabled': true,
  };
  Map<String, dynamic> get second => {
    ...conversation,
    'id': '66666666-6666-4666-8666-666666666666',
    'peer': {
      'id': peer2,
      'username': 'maryam',
      'displayName': 'مريم',
      'avatarPreset': 'initials',
    },
    'lastMessage': 'تمام، أشوفك باچر',
    'updatedAt': '2026-10-24T12:32:00.000Z',
    'lastMessageAt': '2026-10-24T12:32:00.000Z',
    'unreadCount': 1,
  };
  Map<String, dynamic> get group => {
    ...conversation,
    'id': gid,
    'type': 'group',
    'isOwner': true,
    'ownerId': '11111111-1111-4111-8111-111111111111',
    'memberCount': 3,
    'peer': {
      'id': gid,
      'username': 'group',
      'displayName': 'فريق التصميم',
      'avatarPreset': 'initials',
    },
    'unreadCount': 0,
    'lastMessage': 'النسخة الجديدة جاهزة',
    'updatedAt': '2026-10-24T11:50:00.000Z',
    'lastMessageAt': '2026-10-24T11:50:00.000Z',
  };
  Map<String, dynamic> forPath(String path) =>
      path.contains('/groups/') ? (created ?? group) : conversation;
  @override
  Future<void> uploadImage(ImageUpload upload, ImageDraft image) async {
    uploads++;
    await uploadGate?.future;
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
        'conversations': [
          conversation,
          second,
          if (!memberLeft) group,
          if (created != null) created!,
        ],
        'totalUnread': (conversation['unreadCount'] as int) + 1,
        'nextCursor': null,
        'removedConversationIds': memberLeft ? [gid] : [],
      };
    if (path == '/v1/chat/blocks') return {'users': []};
    if (path == '/v1/groups' && method == 'POST') {
      groupNonces.add(body!['requestId'] as String);
      if (created != null) {
        await groupGate?.future;
        return {'conversation': created!};
      }
      groups++;
      created = {
        ...group,
        'id': '77777777-7777-4777-8777-777777777777',
        'peer': {
          ...(group['peer'] as Map<String, dynamic>),
          'id': '77777777-7777-4777-8777-777777777777',
          'displayName': body['title'],
        },
        'memberCount': (body['memberIds'] as List).length + 1,
      };
      await groupGate?.future;
      if (loseGroupReply) {
        loseGroupReply = false;
        throw const AccountFailure('NETWORK', 'انقطع الرد بعد الإنشاء.');
      }
      return {'conversation': created!};
    }
    if (path.endsWith('/files') && method == 'POST') {
      prepares++;
      fileNames['file-$prepares'] = body!['fileName'] as String;
      return {
        'uploadId': 'file-$prepares',
        'uploadUrl':
            'https://test.r2.cloudflarestorage.com/bucket/file-$prepares',
        'headers': {
          'content-type': body['contentType'],
          'content-md5': body['contentMd5'],
          'if-none-match': '*',
        },
      };
    }
    if (path.endsWith('/messages') &&
        method == 'POST' &&
        (body!['stickerId'] != null || body['fileUploadId'] != null)) {
      sends++;
      final nonce = body['requestId'] as String;
      if (byNonce.containsKey(nonce))
        return {'conversation': forPath(path), 'message': byNonce[nonce]};
      final m = {
        ...row(rows.length + 1, mine: true, nonce: nonce),
        'text': body['text'],
        'stickerId': body['stickerId'],
        'file': body['fileUploadId'] == null
            ? null
            : {
                'name': fileNames[body['fileUploadId']],
                'byteLength': 23,
                'url':
                    'https://test.r2.cloudflarestorage.com/bucket/private-document',
              },
      };
      rows.add(m);
      byNonce[nonce] = m;
      if (loseReply) {
        loseReply = false;
        throw const AccountFailure('NETWORK', 'انقطع الرد.');
      }
      return {'conversation': forPath(path), 'message': m};
    }
    if (path.startsWith('/v1/groups/')) {
      if (path.endsWith('/messages'))
        return {
          'conversation': forPath(path),
          'messages': [],
          'nextBefore': null,
          'nextAfter': null,
        };
      if (path.endsWith('/members'))
        return {
          'conversation': forPath(path),
          'users': [(conversation['peer'] as Map), (second['peer'] as Map)],
        };
      return {'conversation': forPath(path)};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class OtherChat12Api extends Chat12Api {
  @override
  Future<AccountUser> me(String token) async =>
      AccountUser.fromJson(accountJson(id: peer2, username: 'other'));
}

Future<(AccountController, Chat12Api, ChatThreadController)> ready({
  MemoryDraftStore? store,
  Chat12Api? api,
}) async {
  final service = api ?? Chat12Api(),
      a = await chatAccount(service, store ?? MemoryDraftStore()),
      t = await thread(a, service);
  return (a, service, t);
}

void viewport(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget host(
  Widget child, {
  double scale = 1,
  double keyboard = 0,
  bool dark = true,
  bool visual = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  navigatorObservers: [chatRouteObserver],
  theme: ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: visual ? 'VisualArabic' : null,
    fontFamilyFallback: visual ? const ['VisualEmoji'] : null,
  ),
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: child,
);
Future<void> finish(WidgetTester t, AccountController a) async {
  await t.pumpWidget(const SizedBox.shrink());
  a.dispose();
}

void addExamples(Chat12Api api) {
  api.rows.addAll([
    {...api.row(1), 'text': 'هلا شلونك؟'},
    {...api.row(2, mine: true), 'text': 'هلا علي، تمام الحمد لله!'},
    {
      ...api.row(3),
      'text': '',
      'audio': {
        'url': 'https://test.r2.cloudflarestorage.com/bucket/voice',
        'durationMs': 18000,
      },
    },
    {...api.row(4, mine: true), 'text': '', 'stickerId': 'hello'},
    {
      ...api.row(5),
      'text': 'هذا الملف جاهز',
      'file': {
        'url': 'https://test.r2.cloudflarestorage.com/bucket/report',
        'name': 'الخطة الجديدة.pdf',
        'byteLength': 24000,
      },
    },
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(320, 640), const Size(800, 420)])
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'chat1.2 inbox fits $size at $scale text and filters immediately',
        (t) async {
          viewport(t, size);
          final (a, _, __) = await ready();
          try {
            await t.pumpWidget(
              host(
                Scaffold(body: PrivateChatsScreen(accounts: a)),
                scale: scale,
              ),
            );
            await t.pumpAndSettle();
            expect(
              find.byKey(ValueKey('chat-row-${old.threadId}')),
              findsOneWidget,
            );
            await t.enterText(
              find.byKey(const Key('chat-inbox-search')),
              'مريم',
            );
            await t.pump();
            expect(
              find.byKey(ValueKey('chat-row-${old.threadId}')),
              findsNothing,
            );
            expect(
              find.byKey(
                const ValueKey('chat-row-66666666-6666-4666-8666-666666666666'),
              ),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
          } finally {
            await finish(t, a);
          }
        },
      );
      testWidgets(
        'chat1.2 bubbles and composer fit $size at $scale with keyboard',
        (t) async {
          viewport(t, size);
          final api = Chat12Api();
          addExamples(api);
          final (a, _, thread) = await ready(api: api);
          await thread.sync();
          try {
            await t.pumpWidget(
              host(
                PrivateChatPage(
                  chats: a.chats,
                  conversation: thread.conversation,
                ),
                scale: scale,
                keyboard: 200,
              ),
            );
            await t.pumpAndSettle();
            expect(find.byKey(const Key('private-chat-input')), findsOneWidget);
            expect(find.byKey(const Key('chat-video-call')), findsOneWidget);
            expect(find.byKey(const Key('chat-voice-call')), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            await finish(t, a);
          }
        },
      );
    }
  testWidgets(
    'emoji insertion, sticker sending and unified attachments work from the composer',
    (t) async {
      viewport(t, const Size(360, 780));
      final (a, api, thread) = await ready();
      try {
        await t.pumpWidget(
          host(
            PrivateChatPage(chats: a.chats, conversation: thread.conversation),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('chat-emoji-toggle')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('chat-emoji-0')));
        await t.pump();
        expect(thread.draft, '😀');
        await t.tap(find.text('ملصقات'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('chat-sticker-hello')));
        await t.pumpAndSettle();
        expect(api.rows.single['stickerId'], 'hello');
        expect(find.byType(TomiSticker), findsWidgets);
        await t.tap(find.byKey(const Key('private-chat-attachment')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('private-chat-video')), findsOneWidget);
        expect(find.byKey(const Key('private-chat-document')), findsOneWidget);
        expect(find.text('التقاط صورة'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await finish(t, a);
      }
    },
  );
  testWidgets('inbox menu opens group creation and commits selected people', (
    t,
  ) async {
    viewport(t, const Size(360, 780));
    final (a, api, _) = await ready();
    try {
      await t.pumpWidget(host(Scaffold(body: PrivateChatsScreen(accounts: a))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('chat-inbox-menu')));
      await t.pumpAndSettle();
      expect(find.text('البحث عن شخص'), findsOneWidget);
      expect(find.text('المحظورون'), findsOneWidget);
      await t.tap(find.text('إنشاء مجموعة'));
      await t.pumpAndSettle();
      expect(find.byType(GroupCreatePage), findsOneWidget);
      await t.enterText(find.byKey(const Key('group-name')), 'مجموعة جديدة');
      await t.tap(find.byKey(const ValueKey('group-member-$peer1')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('group-member-$peer2')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('group-create-submit')));
      await t.tap(find.byKey(const Key('group-create-submit')));
      await t.pumpAndSettle();
      expect(api.groups, 1);
      expect(find.byType(PrivateChatPage), findsOneWidget);
      expect(find.text('مجموعة جديدة'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await finish(t, a);
    }
  });
  test(
    'cached history opens before a delayed refresh and stays scoped to its account',
    () async {
      final store = MemoryDraftStore(),
          api = Chat12Api()..rows.addAll([Chat12Api().row(1)]);
      final (a, _, first) = await ready(store: store, api: api);
      await first.sync();
      await first.persist();
      a.dispose();
      final (b, __, second) = await ready(store: store, api: api);
      try {
        expect(second.messages.single.text, 'نص 1');
        final gate = Completer<void>();
        api.pausePage = gate;
        final delayed = second.sync(reconcile: true);
        await old.flush();
        expect(second.messages.single.text, 'نص 1');
        expect(second.loading, true);
        gate.complete();
        await delayed;
      } finally {
        b.dispose();
      }
      final (other, _, isolated) = await ready(
        store: store,
        api: OtherChat12Api(),
      );
      expect(isolated.messages, isEmpty);
      other.dispose();
    },
  );
  test(
    'document lost acknowledgement is reconciled after restart without upload or send duplication',
    () async {
      final store = MemoryDraftStore(), api = Chat12Api()..loseReply = true;
      final (a, _, out) = await ready(store: store, api: api);
      out.enqueue(
        'ملف',
        null,
        document: DocumentDraft(Uint8List.fromList([1, 2, 3]), 'note.txt'),
      );
      await old.flush();
      expect(out.pending.length, 1);
      expect(api.uploads, 1);
      a.dispose();
      final (b, __, restored) = await ready(store: store, api: api);
      try {
        await restored.sync(reconcile: true);
        await old.flush();
        expect(restored.pending, isEmpty);
        expect(restored.messages.single.document!.name, 'note.txt');
        expect(api.uploads, 1);
        expect(api.sends, 1);
      } finally {
        b.dispose();
      }
    },
  );
  test(
    'a sticker can queue behind a slow document upload and both send once',
    () async {
      final api = Chat12Api()..uploadGate = Completer<void>();
      final (a, _, out) = await ready(api: api);
      try {
        out.enqueue(
          '',
          null,
          document: DocumentDraft(Uint8List.fromList([1, 2, 3]), 'note.txt'),
        );
        await old.flush();
        out.enqueue('', null, stickerId: 'love');
        expect(out.pending.length, 2);
        api.uploadGate!.complete();
        for (var i = 0; i < 100 && out.pending.isNotEmpty; i++)
          await Future<void>.delayed(Duration.zero);
        expect(out.pending, isEmpty);
        expect(api.rows.length, 2);
        expect(api.rows.last['stickerId'], 'love');
        expect(api.uploads, 1);
        expect(api.sends, 2);
      } finally {
        a.dispose();
      }
    },
  );
  test(
    'a group removed while offline disappears on refresh and cannot send',
    () async {
      final (a, api, _) = await ready();
      try {
        await a.chats.refresh();
        final g = a.chats.thread(DirectConversation(api.group));
        await g.restored;
        api.memberLeft = true;
        await a.chats.refresh();
        expect(a.chats.conversations.where((c) => c.id == gid), isEmpty);
        expect(g.conversation.canSend, false);
      } finally {
        a.dispose();
      }
    },
  );
  test(
    'fresh private media plays from the valid cached URL without an HTTP refresh',
    () async {
      final (a, api, t) = await ready();
      try {
        t.merge([
          {
            ...api.row(1),
            'audio': {
              'url': 'https://test.r2.cloudflarestorage.com/bucket/audio',
              'durationMs': 18000,
            },
          },
        ]);
        api.pauseMetadata = Completer<void>();
        final uri = await t.mediaSource('message-1', 'audio');
        expect(uri!.path, '/bucket/audio');
        expect(api.pauseMetadata!.isCompleted, false);
        api.pauseMetadata!.complete();
      } finally {
        a.dispose();
      }
    },
  );
  testWidgets(
    'group creation retries the saved request after closing the page without duplicating the group',
    (t) async {
      viewport(t, const Size(360, 780));
      final api = Chat12Api()..loseGroupReply = true;
      final (a, _, __) = await ready(api: api);
      try {
        await t.pumpWidget(
          host(Scaffold(body: PrivateChatsScreen(accounts: a))),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('chat-inbox-menu')));
        await t.pumpAndSettle();
        await t.tap(find.text('إنشاء مجموعة'));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('group-name')), 'محاولة محفوظة');
        await t.tap(find.byKey(const ValueKey('group-member-$peer1')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('group-member-$peer2')));
        await t.pump();
        await t.tap(find.byKey(const Key('group-create-submit')));
        await t.pumpAndSettle();
        expect(api.groups, 1);
        expect(find.byType(GroupCreatePage), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('chat-inbox-menu')));
        await t.pumpAndSettle();
        await t.tap(find.text('إنشاء مجموعة'));
        await t.pumpAndSettle();
        expect(
          (t.widget<TextField>(
            find.byKey(const Key('group-name')),
          )).controller!.text,
          'محاولة محفوظة',
        );
        await t.tap(find.byKey(const Key('group-create-submit')));
        await t.pumpAndSettle();
        expect(api.groups, 1);
        expect(api.groupNonces.length, 2);
        expect(api.groupNonces.toSet().length, 1);
        expect(find.byType(PrivateChatPage), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await finish(t, a);
      }
    },
  );
  test(
    'a late group response cannot restore conversations after logout',
    () async {
      final api = Chat12Api()..groupGate = Completer<void>();
      final (a, _, __) = await ready(api: api);
      try {
        final pending = a.chats.createGroup('مجموعة', [
          peer1,
          peer2,
        ], newRequestId());
        await old.flush();
        await a.logout();
        api.groupGate!.complete();
        await expectLater(pending, throwsA(isA<AccountFailure>()));
        expect(a.chats.conversations, isEmpty);
      } finally {
        a.dispose();
      }
    },
  );
  if (Platform.environment['TOMI_RENDER_CHAT'] == '1') {
    setUpAll(() async {
      final bytes = await File(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ).readAsBytes();
      await (FontLoader(
        'VisualArabic',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final emoji = File('/tmp/tomi-qa-emoji.ttf');
      if (await emoji.exists()) {
        final b = await emoji.readAsBytes();
        await (FontLoader(
          'VisualEmoji',
        )..addFont(Future.value(ByteData.sublistView(b)))).load();
      }
    });
    for (final screen in ['inbox', 'thread', 'inbox-light', 'thread-light'])
      testWidgets('render chat $screen reference', (t) async {
        viewport(t, const Size(390, 844));
        final api = Chat12Api();
        addExamples(api);
        final (a, _, thread) = await ready(api: api);
        await thread.sync();
        try {
          await t.pumpWidget(
            RepaintBoundary(
              key: const Key('visual'),
              child: host(
                screen.startsWith('inbox')
                    ? Scaffold(body: PrivateChatsScreen(accounts: a))
                    : PrivateChatPage(
                        chats: a.chats,
                        conversation: thread.conversation,
                      ),
                visual: true,
                dark: !screen.endsWith('light'),
              ),
            ),
          );
          await t.pumpAndSettle();
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('visual')),
          );
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2),
                bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('validation/1.2-chat/previews');
            await dir.create(recursive: true);
            await File(
              '${dir.path}/$screen.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(t.takeException(), isNull);
        } finally {
          await finish(t, a);
        }
      });
  }
}
