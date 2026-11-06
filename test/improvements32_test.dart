import 'package:tomi_app/src/gaming/chat_game_invite.dart';
import 'package:tomi_app/src/accounts/account_api.dart'
    show AccountFailure, AccountApi;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/messaging/upload_transfer.dart';
import 'package:tomi_app/src/preferences/preferences_page.dart';
import 'package:tomi_app/src/preferences/media_preferences.dart';
import 'package:tomi_app/src/social/story_screens.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chats;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'upload streams bytes with progress, cancellation interrupts consumption and sends no account bearer',
    () async {
      final media = ImageDraft(Uint8List(200000), 'image/png'),
          transfer = UploadTransfer();
      UploadTransfer.owners[media] = transfer;
      final sent = <int>[];
      transfer.addListener(() => sent.add(transfer.sent));
      final api = AccountApi(
        'https://api.example.com',
        client: MockClient.streaming((request, stream) async {
          expect(request.headers.containsKey('authorization'), false);
          await stream.toBytes();
          return http.StreamedResponse(Stream.value(<int>[]), 200);
        }),
      );
      await api.uploadImage(
        ImageUpload(
          id: 'test',
          url: Uri.parse('https://test.r2.cloudflarestorage.com/test'),
          headers: {
            'content-type': 'image/png',
            'content-md5': media.contentMd5,
            'if-none-match': '*',
          },
        ),
        media,
      );
      expect(sent.length, greaterThan(1));
      expect(transfer.sent, media.bytes.length);
      final cancel = UploadTransfer();
      final r = ProgressUploadRequest(
        'PUT',
        Uri.parse('https://test.example.com'),
        media.bytes,
        cancel,
      );
      final chunks = <List<int>>[];
      await expectLater(
        r.finalize().map((bytes) {
          chunks.add(bytes);
          cancel.cancel();
          return bytes;
        }).drain<void>(),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(chunks.length, 1);
    },
  );
  testWidgets(
    'story draft restores text and audience after leaving and reopening without publishing',
    (t) async {
      final api = PreferencesFake(),
          store = MemoryDraftStore(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
            draftStore: store,
          );
      await a.restore();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => StoryComposerPage(accounts: a),
                  ),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('افتح'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('story-text')), 300);
      await t.enterText(find.byKey(const Key('story-text')), 'مسودة لا تضيع');
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pumpAndSettle();
      await t.tap(find.text('افتح'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('story-text')), 300);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('story-text')))
            .controller!
            .text,
        'مسودة لا تضيع',
      );
      expect(api.stories, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'chat game invitation recovers the same private table after a lost creation response and sends one invitation',
    (t) async {
      final api = InviteFake(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
            draftStore: MemoryDraftStore(),
          );
      await a.restore();
      final conversation = await a.chats.open(
        '22222222-2222-4222-8222-222222222222',
      );
      final thread = a.chats.thread(conversation);
      await thread.restored;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showModalBottomSheet(
                  context: c,
                  builder: (_) => ChatGameInvite(thread: thread),
                ),
                child: const Text('دعوة'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('دعوة'));
      await t.pumpAndSettle();
      await t.tap(find.text('إنشاء الغرفة وإرسال الدعوة'));
      await t.pumpAndSettle();
      expect(api.creations.length, 1);
      await t.tap(find.text('إنشاء الغرفة وإرسال الدعوة'));
      await t.pumpAndSettle();
      expect(api.creations.length, 2);
      expect(api.creations.first, api.creations.last);
      await t.runAsync(() async {
        for (var i = 0; i < 20 && api.rows.isEmpty; i++)
          await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(api.rows.length, 1);
      expect(api.invitations.single['targetId'], 'room-test');
      expect(api.rows.single['text'], contains('ABCDEF12'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'contact and data settings fit compact enlarged text, save policies and preserve private drafts when cleaning',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = PreferencesFake(),
          store = MemoryDraftStore(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
            draftStore: store,
          );
      await a.restore();
      await store.write(a.draftOwnerId!, 'post', {'text': 'مسودة مهمة'});
      await t.pumpWidget(
        MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: w!,
          ),
          home: PreferencesPage(accounts: a),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('من يگدر يتواصل وياك؟'), findsOneWidget);
      await MediaPreferences.instance.update(saver: true);
      await MediaPreferences.instance.clearPreviews();
      expect(
        (await store.read(a.draftOwnerId!, 'post'))!['text'],
        'مسودة مهمة',
      );
      expect(t.takeException(), isNull);
      await MediaPreferences.instance.update(saver: false);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}

class PreferencesFake extends chats.ChatFakeApi {
  Map<String, dynamic> preferences = {
    'messages': 'everyone',
    'calls': 'everyone',
    'roomInvites': 'everyone',
  };
  int stories = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/me/contact-preferences') {
      if (method == 'PUT') preferences = body!;
      return {'preferences': preferences};
    }
    if (path == '/v1/stories' && method == 'POST') {
      stories++;
      return {'story': {}};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class InviteFake extends chats.ChatFakeApi {
  final creations = <String>[];
  final invitations = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/me/invitations' && method == 'POST') {
      invitations.add({...body!});
      return {
        'invitation': {'id': 'invite-test'},
      };
    }
    if (path == '/v1/games/matches' && method == 'POST') {
      creations.add(body!['requestId'] as String);
      if (creations.length == 1)
        throw const AccountFailure('NETWORK', 'ack lost');
      return {
        'match': {'id': 'room-test', 'code': 'ABCDEF12', 'kind': 'uno'},
      };
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}
