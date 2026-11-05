import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/app.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_search.dart';

import 'account_fakes.dart';

http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<void> revealWidget(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    // Scroll the page's vertical ListView when its target is not onstage.
    // Text fields may have their own horizontal Scrollables.
    final page = find.byType(ListView).last;
    final scrollable = find
        .descendant(
          of: page,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    await tester.scrollUntilVisible(finder, 150, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> visibleTap(WidgetTester tester, Finder finder) async {
  await revealWidget(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void smallScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'login, registration and recovery forms fit a compact screen with enlarged text',
    (tester) async {
      smallScreen(tester);
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault(),
        api: AccountApi(
          'https://accounts.example',
          client: MockClient((_) async => response({})),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await tester.pumpWidget(
        TomiApp(accounts: accounts, textScaler: const TextScaler.linear(1.5)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await visibleTap(tester, find.byKey(const Key('auth-switch-register')));
      expect(find.byKey(const Key('account-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await visibleTap(tester, find.byKey(const Key('auth-switch-recover')));
      expect(find.byKey(const Key('account-recovery')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration presents recovery before opening the signed-in app',
    (tester) async {
      smallScreen(tester);
      const recoveryCodeValue = '12345678-ABCDEF12-12345678-ABCDEF12-12345678';
      final vault = MemoryTokenVault();
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: vault,
        api: AccountApi(
          'https://accounts.example',
          client: MockClient((request) async {
            if (request.url.path == '/health')
              return response({'status': 'ok'});
            if (request.url.path == '/v1/moderation/access')
              return response({'role': 'member', 'ownerConfigured': false});
            if (request.url.path == '/v1/posts')
              return response({
                'posts': [],
                'nextCursor': null,
                'imageUploadEnabled': false,
              });
            if (request.method == 'GET' && request.url.path == '/v1/stories')
              return response({'groups': []});
            if (request.method == 'GET' && request.url.path == '/v1/activity')
              return response({
                'items': [],
                'unreadCount': 0,
                'nextCursor': null,
              });
            if (request.method == 'GET' &&
                request.url.path ==
                    '/v1/users/11111111-1111-4111-8111-111111111111')
              return response({
                'user': accountJson(username: 'new_user', name: 'مستخدم جديد'),
              });
            expect(request.url.path, '/v1/auth/register');
            expect(request.method, 'POST');
            final body = jsonDecode(request.body);
            expect(body['username'], 'new_user');
            return response({
              'token': 'new-token',
              'user': accountJson(username: 'new_user', name: 'مستخدم جديد'),
              'recoveryCode': recoveryCodeValue,
            }, 201);
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await tester.pumpWidget(
        TomiApp(accounts: accounts, textScaler: const TextScaler.linear(1.5)),
      );
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byKey(const Key('auth-switch-register')));
      await tester.ensureVisible(find.byKey(const Key('account-name')));
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'مستخدم جديد',
      );
      await tester.ensureVisible(find.byKey(const Key('account-username')));
      await tester.enterText(
        find.byKey(const Key('account-username')),
        'new_user',
      );
      await tester.ensureVisible(find.byKey(const Key('account-password')));
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'my very long passphrase',
      );
      await tester.ensureVisible(find.byKey(const Key('account-confirmation')));
      await tester.enterText(
        find.byKey(const Key('account-confirmation')),
        'my very long passphrase',
      );
      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byKey(const Key('account-submit')));
      expect(
        accounts.phase,
        AccountPhase.signedIn,
        reason:
            'Registration must succeed before checking the recovery screen.',
      );
      expect(vault.token, 'new-token');
      expect(accounts.pendingRecoveryCode, recoveryCodeValue);
      final recoveryCode = find.byKey(const Key('recovery-code'));
      await revealWidget(tester, recoveryCode);
      expect(recoveryCode, findsOneWidget);
      expect(find.byKey(const Key('nav-home')), findsNothing);
      expect(tester.takeException(), isNull);
      await visibleTap(tester, find.byKey(const Key('recovery-saved')));
      expect(accounts.pendingRecoveryCode, isNull);
      for (final key in [
        'nav-chats',
        'nav-rooms',
        'nav-games',
        'nav-profile',
        'nav-home',
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: key);
      }
    },
  );

  testWidgets(
    'profile edit waits for server success and keeps text when username is taken',
    (tester) async {
      smallScreen(tester);
      var saved = accountJson();
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault('token'),
        api: AccountApi(
          'https://accounts.example',
          client: MockClient((request) async {
            if (request.method == 'PATCH') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              if (body['username'] == 'taken_user')
                return response({
                  'error': {
                    'code': 'USERNAME_TAKEN',
                    'message': 'هذا اليوزر مستخدم؛ اختَر غيره.',
                  },
                }, 409);
              saved = {...saved, ...body};
            }
            return response({'user': saved});
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await tester.pumpWidget(
        TomiApp(accounts: accounts, textScaler: const TextScaler.linear(1.5)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-profile')));
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byKey(const Key('edit-account')));
      await tester.ensureVisible(find.byKey(const Key('edit-account-name')));
      await tester.enterText(
        find.byKey(const Key('edit-account-name')),
        'اسم جديد',
      );
      await tester.ensureVisible(
        find.byKey(const Key('edit-account-username')),
      );
      await tester.enterText(
        find.byKey(const Key('edit-account-username')),
        'taken_user',
      );
      tester.binding.focusManager.primaryFocus?.unfocus();
      await visibleTap(tester, find.byKey(const Key('save-account')));
      expect(find.text('هذا اليوزر مستخدم؛ اختَر غيره.'), findsOneWidget);
      expect(accounts.user!.username, 'tolo');
      expect(find.text('اسم جديد'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('edit-account-username')),
      );
      await tester.enterText(
        find.byKey(const Key('edit-account-username')),
        'new_handle',
      );
      tester.binding.focusManager.primaryFocus?.unfocus();
      await visibleTap(tester, find.byKey(const Key('save-account')));
      expect(accounts.user!.username, 'new_handle');
      expect(accounts.user!.displayName, 'اسم جديد');
      expect(find.byKey(const Key('saved-profile-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late search responses cannot replace a newer query result', (
    tester,
  ) async {
    final older = Completer<http.Response>();
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: MemoryTokenVault('token'),
      api: AccountApi(
        'https://accounts.example',
        client: MockClient((request) async {
          if (request.url.path == '/v1/me')
            return response({'user': accountJson()});
          if (request.url.queryParameters['q'] == 'ali') return older.future;
          return response({
            'users': [accountJson(username: 'fatima', name: 'فاطمة')],
          });
        }),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: AccountSearchPage(accounts: accounts),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('account-search-input')),
      'ali',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const Key('account-search-input')),
      'fatima',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('فاطمة'), findsOneWidget);
    older.complete(
      response({
        'users': [accountJson(username: 'ali', name: 'علي')],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('فاطمة'), findsOneWidget);
    expect(find.text('علي'), findsNothing);
  });

  testWidgets(
    'expired session removes pushed account pages and returns to login',
    (tester) async {
      var expired = false;
      final vault = MemoryTokenVault('token');
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: vault,
        api: AccountApi(
          'https://accounts.example',
          client: MockClient((request) async {
            if (expired)
              return response({
                'error': {'code': 'UNAUTHORIZED', 'message': 'انتهت الجلسة'},
              }, 401);
            return response({'user': accountJson()});
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await tester.pumpWidget(TomiApp(accounts: accounts));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('البحث'));

      await tester.pumpAndSettle();
      expired = true;
      await tester.enterText(
        find.byKey(const Key('account-search-input')),
        'ali',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-username')), findsOneWidget);
      expect(find.byKey(const Key('account-search-input')), findsNothing);
      expect(vault.token, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
