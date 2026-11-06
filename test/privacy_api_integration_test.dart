import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/privacy/deletion_controller.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '1.0 real HTTP erasure revokes sessions, removes posts and messages and verifies its private receipt signed out',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/privacy-client-api.mjs',
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
          api: AccountApi(
            'https://privacy.tomi.test',
            client: LocalBridge(base),
          ),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          draftStore: MemoryDraftStore(),
          realtimeEnabled: false,
        );
        await a.restore();
        return a;
      }

      final author = await account(0), peer = await account(1);
      addTearDown(author.dispose);
      addTearDown(peer.dispose);
      final c = AccountDeletionController(author);
      addTearDown(c.dispose);
      await c.restore();
      expect(c.preview!['canDelete'], true);
      await c.send(fixture['password'] as String, 'حذف حسابي');
      expect(c.accepted, true);
      expect(author.user, isNull);
      await c.check();
      expect(c.status!['personalDataErased'], true);
      final posts = await peer.chatRequest('GET', '/v1/posts');
      expect(posts['posts'], isEmpty);
      final thread = (fixture['thread'] as Map)['id'],
          messages = await peer.chatRequest(
            'GET',
            '/v1/chats/$thread/messages',
          );
      expect(((messages['messages'] as List).single as Map)['deleted'], true);
      final api = author.api;
      await expectLater(
        api.chatRequest((users[0] as Map)['token'] as String, 'GET', '/v1/me'),
        throwsA(isA<AccountFailure>()),
      );
      expect(
        (await api.publicRequest('GET', '/v1/privacy/documents'))['version'],
        fixture['policyVersion'],
      );
    },
    skip: Platform.environment['TOMI_PRIVACY_INTEGRATION'] != '1',
  );
}
