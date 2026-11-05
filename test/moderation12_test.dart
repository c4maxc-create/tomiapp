import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/moderation/moderation_controller.dart';
import 'package:tomi_app/src/moderation/admin_page.dart';
import 'package:tomi_app/src/moderation/report_dialog.dart';
import 'package:tomi_app/src/moderation/reports_page.dart';
import 'account_fakes.dart';
import 'identity11_test.dart' show IdentityApi, identityAccount;
import 'room_features_test.dart' show roomApp;

const rid = '33333333-3333-4333-8333-333333333333',
    post = '44444444-4444-4444-8444-444444444444';

class ModerationApi extends IdentityApi {
  String role = 'owner';
  bool dropCommandAck = false, dropReportAck = false;
  Completer<void>? commandGate, listGate12, detailGate;
  final commands = <Map<String, dynamic>>[], reports = <Map<String, dynamic>>[];
  final commandReceipts = <String, Map<String, dynamic>>{},
      reportReceipts = <String, Map<String, dynamic>>{};
  int applied = 0, reportsCreated = 0;
  Map<String, dynamic> report = {
    'id': rid,
    'targetType': 'post',
    'targetId': post,
    'reason': 'harassment',
    'description': 'تفاصيل صاحب البلاغ',
    'status': 'open',
    'revision': 0,
    'publicMessage': '',
    'createdAt': '2026-10-16T20:00:00.000Z',
    'updatedAt': '2026-10-16T20:00:00.000Z',
  };
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/moderation/access')
      return {'role': role, 'ownerConfigured': true};
    if (path == '/v1/admin/actions') {
      commands.add({...body!});
      await commandGate?.future;
      if (role == 'member')
        throw const AccountFailure(
          'ADMIN_FORBIDDEN',
          'سُحبت الصلاحية',
          status: 403,
        );
      final key = body['requestId'] as String;
      if (commandReceipts[key] != null)
        return {...commandReceipts[key]!, 'replayed': true};
      applied++;
      final response = {'receiptId': 'receipt-$applied', 'applied': true};
      commandReceipts[key] = response;
      if (body['action'] == 'review_report')
        report = {
          ...report,
          'status': body['status'],
          'publicMessage': body['publicMessage'] ?? '',
          'revision': 1,
        };
      if (dropCommandAck) {
        dropCommandAck = false;
        throw const AccountFailure('NETWORK', 'انقطع التأكيد');
      }
      return response;
    }
    if (path == '/v1/reports' && method == 'POST') {
      reports.add({...body!});
      final key = body['requestId'] as String;
      if (reportReceipts[key] != null) return reportReceipts[key]!;
      reportsCreated++;
      final response = {'report': report};
      reportReceipts[key] = response;
      if (dropReportAck) {
        dropReportAck = false;
        throw const AccountFailure('NETWORK', 'انقطع التأكيد');
      }
      return response;
    }
    if (path == '/v1/reports')
      return {
        'items': [report],
        'nextBefore': null,
      };
    if (path.startsWith('/v1/admin/') && role == 'member')
      throw const AccountFailure(
        'ADMIN_FORBIDDEN',
        'سُحبت الصلاحية',
        status: 403,
      );
    if (path == '/v1/admin/reports') {
      final captured = {
        'items': [
          {
            ...report,
            'status': query?['status'] ?? 'open',
            'note': 'ملاحظة إدارة خاصة',
            'snapshot': {
              'user': {'username': 'reported_user'},
              'text': 'نص المحتوى',
              'title': '',
            },
          },
        ],
        'nextBefore': null,
      };
      final gate = listGate12;
      listGate12 = null;
      await gate?.future;
      return jsonDecode(jsonEncode(captured)) as Map<String, dynamic>;
    }
    if (path == '/v1/admin/reports/$rid') {
      await detailGate?.future;
      return {
        'report': {
          ...report,
          'note': 'ملاحظة إدارة خاصة',
          'snapshot': {
            'user': {'username': 'reported_user'},
            'text': 'نص المحتوى',
          },
        },
        'reporter': accountJson(),
        'target': {
          'state': {'hidden': false, 'revision': 0},
          'text': 'نص المحتوى',
        },
      };
    }
    if (path == '/v1/admin/users' || path == '/v1/admin/staff')
      return {
        'items': [
          {
            'user': person,
            'state': {
              'role': 'member',
              'suspended': false,
              'roleRevision': 0,
              'restrictionRevision': 0,
            },
          },
        ],
        'nextBefore': null,
      };
    if (path == '/v1/admin/rooms')
      return {
        'items': [
          {
            'id': rid,
            'title': 'غرفة بلاغات',
            'state': 'open',
            'memberCount': 2,
            'moderation': {'revision': 0},
          },
        ],
        'nextBefore': null,
      };
    if (path == '/v1/admin/audit')
      return {
        'items': [
          {
            'id': rid,
            'action': 'hide_post',
            'reason': 'سبب محفوظ',
            'actorId': 'admin',
            'targetId': post,
            'createdAt': '2026-10-16T20:00:00Z',
          },
        ],
        'nextBefore': null,
      };
    if (path == '/v1/admin/metrics')
      return {
        'requests': {
          'count': 10,
          'serverErrors': 0,
          'averageMs': 20,
          'p95UpperMs': 50,
        },
        'process': {'rssBytes': 1048576},
        'database': {'open_rooms': 2, 'users': 4},
        'databaseSampleAt': '2026-10-16T20:00:00Z',
      };
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'admin retries freeze the original nonce and cannot apply an accepted action twice',
    () async {
      final api = ModerationApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = ModerationController(a);
      addTearDown(c.dispose);
      await c.loadAccess();
      api.dropCommandAck = true;
      expect(
        await c.runCommand({
          'action': 'hide_post',
          'targetId': post,
          'reason': 'سبب للمراجعة',
          'expectedRevision': 0,
        }),
        false,
      );
      expect(c.pendingCommand, isNotNull);
      expect(api.applied, 1);
      expect(
        await c.runCommand({
          'action': 'restore_post',
          'targetId': post,
          'reason': 'تغيير جديد',
          'expectedRevision': 1,
        }),
        false,
      );
      expect(api.commands.length, 1);
      expect(await c.retryCommand(), true);
      expect(api.applied, 1);
      expect(api.commands[0], api.commands[1]);
      expect(c.pendingCommand, isNull);
    },
  );
  test(
    'revoked platform role clears all staff data and cannot execute a pending command',
    () async {
      final api = ModerationApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = ModerationController(a);
      addTearDown(c.dispose);
      await c.loadAccess();
      await c.load();
      expect(c.items, isNotEmpty);
      api.dropCommandAck = true;
      await c.runCommand({
        'action': 'hide_post',
        'targetId': post,
        'reason': 'سبب للمراجعة',
        'expectedRevision': 0,
      });
      final gate = api.detailGate = Completer<void>();
      final lateDetail = c.loadDetail(rid);
      api.role = 'member';
      await c.retryCommand();
      gate.complete();
      await lateDetail;
      expect(c.staff, false);
      expect(c.items, isEmpty);
      expect(c.detail, isNull);
      expect(c.pendingCommand, isNull);
    },
  );
  test(
    'late privileged response after logout cannot restore staff content',
    () async {
      final api = ModerationApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      final c = ModerationController(a);
      addTearDown(c.dispose);
      await c.loadAccess();
      final gate = api.commandGate = Completer<void>();
      final pending = c.runCommand({
        'action': 'hide_post',
        'targetId': post,
        'reason': 'سبب للمراجعة',
        'expectedRevision': 0,
      });
      await a.logout();
      gate.complete();
      await pending;
      expect(c.current, false);
      expect(c.items, isEmpty);
      expect(c.pendingCommand, isNull);
      expect(a.user, isNull);
    },
  );
  test('new report queue filter wins over an older response', () async {
    final api = ModerationApi(), a = await identityAccount(api);
    addTearDown(a.dispose);
    final c = ModerationController(a);
    addTearDown(c.dispose);
    await c.loadAccess();
    final gate = api.listGate12 = Completer<void>(), old = c.load();
    await c.load(selectedFilter: 'resolved');
    gate.complete();
    await old;
    expect(c.items.single['status'], 'resolved');
    expect(c.loading, false);
  });
  testWidgets(
    'a report with a lost accepted ACK retries the same frozen request and creates once',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ModerationApi()..dropReportAck = true,
          a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(
        roomApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showReportDialog(
                    context,
                    a,
                    targetType: 'post',
                    targetId: post,
                    title: 'منشور اختبار',
                  ),
                  child: const Text('إبلاغ'),
                ),
              ),
            ),
          ),
          scale: 1.4,
        ),
      );
      await tester.tap(find.text('إبلاغ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('report-description')),
        'وصف ثابت للبلاغ',
      );
      await tester.tap(find.byKey(const Key('send-report')));
      await tester.pumpAndSettle();
      expect(api.reportsCreated, 1);
      expect(find.text('إعادة التحقق'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('report-description')))
            .enabled,
        false,
      );
      await tester.tap(find.byKey(const Key('send-report')));
      await tester.pumpAndSettle();
      expect(api.reportsCreated, 1);
      expect(api.reports[0], api.reports[1]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('ordinary reporter sees public status but never staff notes', (
    tester,
  ) async {
    final api = ModerationApi()..role = 'member',
        a = await identityAccount(api);
    addTearDown(a.dispose);
    await tester.pumpWidget(roomApp(MyReportsPage(accounts: a), scale: 1.5));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار المراجعة'), findsOneWidget);
    expect(find.textContaining('ملاحظة إدارة خاصة'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'admin tabs, status filters and metrics fit a compact Arabic screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ModerationApi(), a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(roomApp(AdminPage(accounts: a), scale: 1.4));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('admin-tab-staff')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('admin-tab-staff')), findsOneWidget);
      final tab = find.byKey(const Key('admin-tab-metrics'));
      await tester.scrollUntilVisible(
        tab,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.text('المكالمات الحالية'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a room moderator account without a platform role cannot see the admin dashboard',
    (tester) async {
      final api = ModerationApi()..role = 'member',
          a = await identityAccount(api);
      addTearDown(a.dispose);
      await tester.pumpWidget(
        roomApp(Scaffold(body: ModerationSettingsEntry(accounts: a))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-reports')), findsOneWidget);
      expect(find.byKey(const Key('platform-admin')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
