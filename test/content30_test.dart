import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/chat_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/messaging/voice_note.dart';
import 'package:tomi_app/src/social/post_draft_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'package:tomi_app/src/live/live_pages.dart';
import 'account_fakes.dart';
import 'chat_test.dart' show ChatFakeApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'gallery wallpaper is durable and account scoped without copying the blob on each draft edit',
    () async {
      final store = MemoryDraftStore(),
          a = AccountController(
            api: ChatFakeApi(),
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
            draftStore: store,
          );
      await a.restore();
      final api = a.api as ChatFakeApi,
          t = a.chats.thread(DirectConversation.fromJson(api.conversation));
      await t.restored;
      final image = ImageDraft(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
        ),
        'image/png',
      );
      await t.setWallpaperImage(image);
      t.draft = 'new text';
      await t.persist();
      final restored = ChatThreadController(
        chats: a.chats,
        conversation: t.conversation,
      );
      await restored.restored;
      expect(restored.wallpaperImage!.contentSha256, image.contentSha256);
      expect(restored.draft, 'new text');
      expect(store.media.length, 1);
      await a.draftStore.erase(a.draftOwnerId!);
      expect(store.media, isEmpty);
      restored.dispose();
      a.dispose();
    },
  );
  test(
    'publishing audience persists with the saved draft and cannot change an uncertain committed request',
    () async {
      final a = AccountController(
        api: ChatFakeApi(),
        vault: MemoryTokenVault('token'),
        realtimeEnabled: false,
        draftStore: MemoryDraftStore(),
      );
      await a.restore();
      final draft = PostDraftController(a);
      await draft.restored;
      draft.editText('وصف');
      draft.selectAudience('followers');
      await draft.persist();
      draft.dispose();
      final restored = PostDraftController(a);
      await restored.restored;
      expect(restored.audience, 'followers');
      restored.item.commitAttempted = true;
      restored.selectAudience('public');
      expect(restored.audience, 'followers');
      restored.dispose();
      a.dispose();
    },
  );
  testWidgets(
    'voice messages expose 1x 2x and 3x speed without changing the recording',
    (t) async {
      final playback = VoicePlayback();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoicePlayer(
              playback: playback,
              id: 'fixture',
              durationMs: 4000,
              source: () async => null,
            ),
          ),
        ),
      );
      expect(find.text('1×'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('voice-speed-fixture')));
      await t.pump();
      expect(find.text('2×'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('voice-speed-fixture')));
      await t.pump();
      expect(find.text('3×'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      playback.dispose();
    },
  );
  testWidgets(
    'live screen explains missing service and leaves real money charging disabled',
    (t) async {
      final a = AccountController(
        api: LiveStatusApi(),
        vault: MemoryTokenVault('token'),
        realtimeEnabled: false,
      );
      await a.restore();
      await t.pumpWidget(MaterialApp(home: LiveHub(accounts: a)));
      await t.pumpAndSettle();
      expect(find.textContaining('خدمة البث غير مفعّلة'), findsOneWidget);
      expect(find.textContaining('الشحن الحقيقي غير مفعّل'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}

class LiveStatusApi extends ChatFakeApi {
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/lives') return {'configured': false, 'lives': []};
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}
