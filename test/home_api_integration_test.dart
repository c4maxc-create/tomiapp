import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '1.1 real HTTP story rings, views, followers, saved posts and activity agree',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/home-client-api.mjs',
      ]);
      final stderr = child.stderr.transform(utf8.decoder).listen((_) {});
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode.timeout(const Duration(seconds: 10));
        await stderr.cancel();
      });
      final first = await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 25)),
          fixture = jsonDecode(first) as Map<String, dynamic>,
          base = Uri.parse(fixture['base'] as String),
          users = fixture['users'] as List;
      Future<AccountController> account(int i) async {
        final a = AccountController(
          api: AccountApi('https://home.tomi.test', client: LocalBridge(base)),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          draftStore: MemoryDraftStore(),
          realtimeEnabled: false,
        );
        await a.restore();
        return a;
      }

      final author = await account(0), viewer = await account(1);
      addTearDown(author.dispose);
      addTearDown(viewer.dispose);
      await viewer.follow(author.user!.id, true);
      final published = await author.chatRequest(
        'POST',
        '/v1/stories',
        body: {'text': 'ستوري حقيقية', 'requestId': newRequestId()},
      );
      final id = (published['story'] as Map)['id'];
      final h = viewer.home;
      for (var i = 0; i < 30 && (h.loadingStories || h.loadingActivity); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await h.loadStories();
      expect(h.hasStory(author.user!.id), true);
      await h.markViewed(h.groups.first.stories.first);
      expect(h.unseen(author.user!.id), false);
      expect(
        ((await author.chatRequest('GET', '/v1/stories/$id'))['story']
            as Map)['viewsCount'],
        1,
      );
      final followers = await author.chatRequest(
        'GET',
        '/v1/users/${author.user!.id}/followers',
      );
      expect(
        ((followers['users'] as List).single as Map)['id'],
        viewer.user!.id,
      );
      final post = await author.publishPost('منشور', newRequestId());
      await viewer.likePost(post.id, true);
      await viewer.chatRequest(
        'PUT',
        '/v1/posts/${post.id}/save',
        body: {'saved': true},
      );
      expect((await viewer.feed(scope: 'saved')).posts.single.saved, true);
      final activity = await author.chatRequest('GET', '/v1/activity');
      expect(activity['unreadCount'], 2);
      await author.chatRequest(
        'PUT',
        '/v1/activity/read',
        body: {'ids': (activity['items'] as List).map((x) => x['id']).toList()},
      );
      expect(
        (await author.chatRequest('GET', '/v1/activity'))['unreadCount'],
        0,
      );
      await author.chatRequest('DELETE', '/v1/stories/$id');
      expect((await viewer.userById(author.user!.id)).hasStory, false);
    },
    skip: Platform.environment['TOMI_HOME_INTEGRATION'] != '1',
  );
}
