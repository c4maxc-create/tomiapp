import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/feed_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Flutter publishing audience, profile posts, message edits and real delivery/read receipts round-trip through the Node API',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/calls-client-api.mjs',
      ]);
      final stderr = child.stderr.transform(utf8.decoder).listen((_) {});
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode;
        await stderr.cancel();
      });
      final line = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final data = jsonDecode(line) as Map<String, dynamic>,
          base = Uri.parse(data['base'] as String),
          users = data['users'] as List;
      Future<AccountController> account(int i) async {
        final a = AccountController(
          api: AccountApi(
            'https://contract.tomi.test',
            client: LocalBridge(base),
          ),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          realtimeEnabled: false,
          draftStore: MemoryDraftStore(),
        );
        await a.restore();
        addTearDown(a.dispose);
        return a;
      }

      final a = await account(0), b = await account(1);
      final post = await a.publishPost(
        'منشور للمتابعين',
        newRequestId(),
        audience: 'followers',
      );
      expect(post.audience, 'followers');
      final own = FeedController(
            accounts: a,
            userId: a.user!.id,
            scope: 'mine',
          ),
          profile = FeedController(accounts: b, userId: a.user!.id),
          explore = FeedController(accounts: b);
      addTearDown(own.dispose);
      addTearDown(profile.dispose);
      addTearDown(explore.dispose);
      await own.refresh();
      await profile.refresh();
      await explore.refresh();
      expect(own.posts.single.id, post.id);
      expect(profile.posts.single.id, post.id);
      expect(explore.posts, isEmpty);
      final d = await a.chatRequest(
        'POST',
        '/v1/chats',
        body: {'userId': b.user!.id},
      );
      final ca = DirectConversation.fromJson(
            Map<String, dynamic>.from(d['conversation'] as Map),
          ),
          ta = a.chats.thread(ca);
      await ta.sync();
      ta.enqueue('قبل التعديل', null);
      for (var n = 0; n < 80 && ta.pending.isNotEmpty; n++)
        await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ta.pending, isEmpty);
      final m = ta.messages.single;
      final db = await b.chatRequest('GET', '/v1/chats/${ca.id}'),
          tb = b.chats.thread(
            DirectConversation.fromJson(
              Map<String, dynamic>.from(db['conversation'] as Map),
            ),
          );
      await tb.sync();
      tb.visible = true;
      await tb.markVisibleRead();
      Map<String, dynamic> info = {};
      for (var n = 0; n < 80; n++) {
        info = await ta.request('GET', '/messages/${m.id}/info');
        if ((info['receipts'] as List).any((r) => r['readAt'] != null)) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((info['receipts'] as List).single['readAt'], isNotNull);
      await ta.request(
        'PUT',
        '/messages/${m.id}/edit',
        body: {'text': 'بعد التعديل', 'expectedRevision': m.revision},
      );
      await ta.refreshMessage(m.id);
      await tb.sync(reconcile: true);
      expect(ta.messages.single.text, 'بعد التعديل');
      expect(tb.messages.single.text, 'بعد التعديل');
    },
    skip: Platform.environment['TOMI_CONTENT_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
