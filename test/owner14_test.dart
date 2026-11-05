import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_widgets.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/moderation/moderation_controller.dart';
import 'package:tomi_app/src/moderation/admin_page.dart';
import 'account_fakes.dart';
import 'moderation12_test.dart' show ModerationApi, post;
import 'voice13_test.dart' show app, capture;

const managedId = '55555555-5555-4555-8555-555555555555';

class OwnerApi extends ModerationApi {
  List<String>? permissions;
  int coins = 1000, charisma = 100, revision = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/moderation/access')
      return {
        'role': role,
        'ownerConfigured': true,
        if (permissions != null) 'permissions': permissions,
      };
    if (path == '/v1/admin/users' || path == '/v1/admin/staff')
      return {
        'items': [
          {
            'user': accountJson(
              id: managedId,
              username: 'managed14',
              name: 'عضو الاختبار',
            ),
            'state': {
              'role': 'member',
              'suspended': false,
              'roleRevision': 0,
              'restrictionRevision': 0,
              'permissions': [],
              'coins': coins,
              'charisma': charisma,
              'adminRevision': revision,
              'special': false,
            },
          },
        ],
        'nextBefore': null,
      };
    if (path == '/v1/admin/posts')
      return {
        'items': [
          {
            'id': post,
            'text': 'منشور للإدارة',
            'user': accountJson(id: managedId),
            'hidden': false,
            'revision': 0,
            'protected': false,
          },
        ],
        'nextBefore': null,
      };
    if (path == '/v1/admin/actions' &&
        [
          'add_coins',
          'withdraw_coins',
          'add_charisma',
          'withdraw_charisma',
          'create_account',
          'grant_moderator',
        ].contains(body?['action'])) {
      commands.add({...body!});
      final key = body['requestId'] as String;
      if (commandReceipts[key] != null)
        return {...commandReceipts[key]!, 'replayed': true};
      applied++;
      revision++;
      if (body['action'] == 'add_coins')
        coins += (body['amount'] as num).toInt();
      if (body['action'] == 'withdraw_coins')
        coins -= (body['amount'] as num).toInt();
      final response = <String, dynamic>{
        'applied': true,
        'receiptId': 'admin-$applied',
        'revision': revision,
        if (body['action'] == 'create_account')
          'recoveryCode': 'ONE-TIME-TEST-RECOVERY',
      };
      commandReceipts[key] = {...response}..remove('recoveryCode');
      if (dropCommandAck) {
        dropCommandAck = false;
        throw const AccountFailure('NETWORK', 'ضاع التأكيد');
      }
      return response;
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class FailedStore extends MemoryDraftStore {
  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) async => false;
}

Future<AccountController> ownerAccount(OwnerApi api, DraftStore store) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('session'),
    draftStore: store,
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['TOMI_VISUAL_QA'] != '1') return;
    final data = await File(
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ).readAsBytes();
    for (final family in ['Roboto', 'Ahem'])
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'accepted balance intent survives controller restart and reuses its original nonce',
    () async {
      final api = OwnerApi(),
          store = MemoryDraftStore(),
          a = await ownerAccount(api, store);
      addTearDown(a.dispose);
      var c = ModerationController(a);
      await c.loadAccess();
      api.dropCommandAck = true;
      expect(
        await c.runCommand({
          'action': 'add_coins',
          'targetId': managedId,
          'amount': 500,
          'expectedRevision': 0,
          'reason': 'إضافة موثقة',
        }),
        false,
      );
      final nonce = c.pendingCommand!['requestId'];
      expect(api.coins, 1500);
      c.dispose();
      c = ModerationController(a);
      addTearDown(c.dispose);
      await c.loadAccess();
      expect(c.pendingCommand!['requestId'], nonce);
      expect(await c.retryCommand(), true);
      expect(api.coins, 1500);
      expect(api.applied, 1);
      expect(
        store.records.values.where((v) => v['action'] == 'add_coins'),
        isEmpty,
      );
    },
  );
  test(
    'failed local financial intent persistence prevents a server mutation even on retry',
    () async {
      final api = OwnerApi(),
          a = await ownerAccount(api, FailedStore()),
          c = ModerationController(a);
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.loadAccess();
      expect(
        await c.runCommand({
          'action': 'add_coins',
          'targetId': managedId,
          'amount': 500,
          'expectedRevision': 0,
          'reason': 'لا تتكرر',
        }),
        false,
      );
      expect(await c.retryCommand(), false);
      expect(api.commands, isEmpty);
      expect(api.coins, 1000);
    },
  );
  test(
    'managed account credentials remain out of drafts and creation does not change owner session',
    () async {
      final api = OwnerApi(),
          store = MemoryDraftStore(),
          a = await ownerAccount(api, store),
          c = ModerationController(a);
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.loadAccess();
      final id = a.user!.id;
      api.dropCommandAck = true;
      expect(
        await c.runCommand({
          'action': 'create_account',
          'targetId': managedId,
          'expectedRevision': 0,
          'username': 'managed14',
          'displayName': 'عضو جديد',
          'password': 'managed account test secret',
          'special': true,
          'reason': 'إنشاء بطلب المالك',
        }),
        false,
      );
      expect(
        jsonEncode(store.records),
        isNot(contains('managed account test secret')),
      );
      expect(await c.retryCommand(), true);
      expect(c.createdRecoveryCode, isNull);
      expect(api.applied, 1);
      expect(a.user!.id, id);
      expect(c.role, 'owner');
    },
  );
  testWidgets(
    'owner account tools show balances, finance form and explicit moderator permission selection',
    (t) async {
      final api = OwnerApi(), a = await ownerAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(app(AdminPage(accounts: a)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('admin-tab-users')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('admin-balance-$managedId')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await capture(t, 'owner14-account-tools');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('admin-balance-$managedId')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('admin-balance-amount')), '500');
      await t.enterText(
        find.byKey(const Key('admin-action-reason')),
        'إضافة بطلب المالك',
      );
      await t.pumpAndSettle();
      await capture(t, 'owner14-balance-dialog');
      await t.tap(find.byKey(const Key('confirm-balance')));
      await t.pumpAndSettle();
      expect(api.coins, 1500);
      expect(api.commands.single['amount'], 500);
      await t.ensureVisible(find.text('تعيين مشرف'));
      await t.tap(find.text('تعيين مشرف'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('permission-bans')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('permission-bans')));
      await t.enterText(
        find.byKey(const Key('admin-action-reason')),
        'إشراف محدود للحساب',
      );
      await t.pumpAndSettle();
      await capture(t, 'owner14-permissions-dialog');
      await t.tap(find.byKey(const Key('save-staff-permissions')));
      await t.pumpAndSettle();
      expect(api.commands.last['permissions'], contains('bans'));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'owner controls remain reachable on a compact enlarged-text screen',
    (t) async {
      final api = OwnerApi(), a = await ownerAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      await t.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(app(AdminPage(accounts: a), scale: 2));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('admin-create-account')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('admin-create-account')));
      await t.pumpAndSettle();
      await capture(t, 'owner14-create-compact');
      expect(t.takeException(), isNull);
      await t.tap(find.text('رجوع').last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('admin-tab-users')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('admin-tab-users')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('admin-balance-$managedId')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('admin-balance-$managedId')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('admin-action-reason')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('admin-action-reason')).hitTestable(),
        findsOneWidget,
      );
      await capture(t, 'owner14-balance-compact');
      expect(find.byKey(const Key('confirm-balance')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'report-only staff cannot see finance, staff assignment or post moderation controls',
    (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = OwnerApi()
            ..role = 'moderator'
            ..permissions = ['reports'],
          a = await ownerAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      await t.pumpWidget(app(AdminPage(accounts: a)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-tab-users')), findsNothing);
      expect(find.byKey(const ValueKey('admin-tab-metrics')), findsNothing);
      expect(find.byKey(const Key('admin-create-account')), findsNothing);
      await t.tap(find.byKey(const ValueKey('admin-tab-reports')));
      await t.pumpAndSettle();
      await t.tap(find.text('فتح البلاغ والمراجعة'));
      await t.pumpAndSettle();
      expect(find.text('إخفاء المنشور'), findsNothing);
      expect(find.text('مراجعة الحالة والملاحظات'), findsOneWidget);
      await capture(t, 'owner14-report-only');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'posts-only staff have a usable posts tab without report access',
    (t) async {
      final api = OwnerApi()
            ..role = 'moderator'
            ..permissions = ['posts'],
          a = await ownerAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      await t.pumpWidget(app(AdminPage(accounts: a)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-tab-posts')), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-tab-reports')), findsNothing);
      await t.tap(find.byKey(const ValueKey('admin-tab-posts')));
      await t.pumpAndSettle();
      expect(find.text('إخفاء المنشور'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'special identity has an accessible public badge without a frame',
    (t) async {
      final user = accountJson()..['identity'] = {'special': true};
      await t.pumpWidget(
        app(
          Scaffold(
            body: Center(child: AccountAvatar(AccountUser.fromJson(user))),
          ),
        ),
      );
      expect(find.bySemanticsLabel('حساب مميز'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
