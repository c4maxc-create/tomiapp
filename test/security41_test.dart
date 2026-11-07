import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/auth_screen.dart';
import 'package:tomi_app/src/experience/security_page.dart';
import 'account_fakes.dart';

http.Response response(Map<String, dynamic> body, [int code = 200]) =>
    http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
void main() {
  testWidgets(
    '41 authenticator challenge stays on login and sends the entered second factor only on retry',
    (t) async {
      final bodies = <Map<String, dynamic>>[];
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault(),
        api: AccountApi(
          'https://api.example.test',
          client: MockClient((r) async {
            if (r.url.path == '/v1/auth/login') {
              bodies.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
              return response({
                'error': {
                  'code': 'MFA_REQUIRED',
                  'message': 'أدخل رمز المصادقة',
                },
              }, 401);
            }
            return response({});
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await t.pumpWidget(MaterialApp(home: AuthScreen(accounts: accounts)));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('account-username')), 'person41');
      await t.enterText(
        find.byKey(const Key('account-password')),
        'test-only long password',
      );
      await t.ensureVisible(find.byKey(const Key('account-submit')));
      await t.tap(find.byKey(const Key('account-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('account-mfa')), findsOneWidget);
      expect(bodies.single.containsKey('mfaCode'), false);
      await t.enterText(find.byKey(const Key('account-mfa')), '123456');
      await t.ensureVisible(find.byKey(const Key('account-submit')));
      await t.tap(find.byKey(const Key('account-submit')));
      await t.pumpAndSettle();
      expect(bodies.last['mfaCode'], '123456');
      expect(accounts.user, isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    '41 authenticator page fits compact enlarged text, confirms setup and shows one-time backup codes',
    (t) async {
      Future<void> reveal(Finder finder) => t.scrollUntilVisible(
        finder,
        150,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      bool enabled = false;
      final sent = <String>[];
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault('test-token'),
        api: AccountApi(
          'https://api.example.test',
          client: MockClient((r) async {
            if (r.url.path == '/v1/me')
              return response({'user': accountJson()});
            if (r.method == 'GET')
              return response({
                'available': true,
                'enabled': enabled,
                'recent': false,
                'events': [],
              });
            sent.add(r.url.path);
            if (r.url.path.endsWith('/setup'))
              return response({'secret': 'TESTONLYSETUPSECRET'});
            if (r.url.path.endsWith('/enable')) {
              enabled = true;
              return response({
                'recoveryCodes': ['TEST-ONLY-BACKUP'],
              });
            }
            return response({'ok': true});
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await t.pumpWidget(
        MaterialApp(
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: w!,
          ),
          home: SecurityProtectionPage(accounts: accounts),
        ),
      );
      await t.pumpAndSettle();
      await reveal(find.byKey(const Key('security-password')));
      await t.enterText(
        find.byKey(const Key('security-password')),
        'test-only long password',
      );
      await t.ensureVisible(find.text('بدء إعداد المصادقة'));
      await t.tap(find.text('بدء إعداد المصادقة'));
      await t.pumpAndSettle();
      expect(sent.single, '/v1/me/security/setup');
      await t.drag(find.byType(ListView), const Offset(0, 1500));
      await t.pumpAndSettle();
      await reveal(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'TESTONLYSETUPSECRET',
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'TESTONLYSETUPSECRET',
        ),
        findsOneWidget,
      );
      await reveal(find.byKey(const Key('security-code')));
      await t.enterText(find.byKey(const Key('security-code')), '123456');
      await t.ensureVisible(find.text('تفعيل المصادقة'));
      await t.tap(find.text('تفعيل المصادقة'));
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, 1500));
      await t.pumpAndSettle();
      await reveal(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'TEST-ONLY-BACKUP',
        ),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'TEST-ONLY-BACKUP',
        ),
        findsOneWidget,
      );
      expect(sent, ['/v1/me/security/setup', '/v1/me/security/enable']);
      expect(t.takeException(), isNull);
    },
  );
}
