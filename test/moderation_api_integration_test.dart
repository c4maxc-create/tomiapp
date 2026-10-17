import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/moderation/moderation_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '0.12 real HTTP report tracking, staff review, content actions and role revocation',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/moderation-client-api.mjs',
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
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(first) as Map<String, dynamic>,
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
        );
        await a.restore();
        return a;
      }

      final owner = await account(0),
          member = await account(1),
          moderator = await account(2),
          reporter = await account(3);
      for (final a in [owner, member, moderator, reporter])
        addTearDown(a.dispose);
      final post = (data['post'] as Map)['id'] as String;
      final report =
          (await reporter.chatRequest(
                'POST',
                '/v1/reports',
                body: {
                  'requestId': newRequestId(),
                  'targetType': 'post',
                  'targetId': post,
                  'reason': 'harassment',
                  'description': 'بلاغ عقد HTTP',
                },
              ))['report']
              as Map<String, dynamic>;
      final mine = ModerationController(reporter),
          admin = ModerationController(owner),
          mod = ModerationController(moderator);
      for (final c in [mine, admin, mod]) addTearDown(c.dispose);
      await mine.load(selected: 'mine');
      expect(mine.items.single['id'], report['id']);
      await admin.loadAccess();
      await admin.load();
      await admin.loadDetail(report['id'] as String);
      expect(admin.staff, true);
      await mod.loadAccess();
      expect(mod.role, 'moderator');
      expect(
        await mod.runCommand({
          'action': 'review_report',
          'targetId': report['id'],
          'reason': 'مراجعة الاختبار',
          'expectedRevision': 0,
          'status': 'reviewing',
          'note': 'ملاحظة داخلية',
          'publicMessage': 'بدأت المراجعة',
        }),
        true,
      );
      await mine.load();
      expect(mine.items.single['publicMessage'], 'بدأت المراجعة');
      expect(mine.items.single.containsKey('note'), false);
      expect(
        await admin.runCommand({
          'action': 'hide_post',
          'targetId': post,
          'reason': 'سبب إخفاء الاختبار',
          'expectedRevision': 0,
          'reportId': report['id'],
        }),
        true,
      );
      expect((await member.chatRequest('GET', '/v1/posts'))['posts'], isEmpty);
      expect(
        await admin.runCommand({
          'action': 'restore_post',
          'targetId': post,
          'reason': 'سبب استعادة الاختبار',
          'expectedRevision': 1,
        }),
        true,
      );
      expect(
        ((await member.chatRequest('GET', '/v1/posts'))['posts'] as List)
            .length,
        1,
      );
      expect(
        await admin.runCommand({
          'action': 'revoke_moderator',
          'targetId': moderator.user!.id,
          'reason': 'إنهاء صلاحية الاختبار',
          'expectedRevision': 1,
        }),
        true,
      );
      await mod.load();
      expect(mod.staff, false);
      expect(mod.items, isEmpty);
      expect(
        await admin.runCommand({
          'action': 'suspend_user',
          'targetId': member.user!.id,
          'reason': 'إيقاف حساب الاختبار',
          'expectedRevision': 0,
        }),
        true,
      );
      await expectLater(
        member.chatRequest('GET', '/v1/me'),
        throwsA(isA<AccountFailure>()),
      );
      expect(member.user, isNull);
    },
    skip: Platform.environment['TOMI_MODERATION_INTEGRATION'] != '1',
  );
}
