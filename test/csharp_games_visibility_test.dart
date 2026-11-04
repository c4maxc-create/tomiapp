import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/gaming/csharp_games_page.dart';
import 'account_fakes.dart';

void main() {
  testWidgets(
    'hidden CSharp games do not initialize WebView or keep other tabs animating',
    (tester) async {
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault(),
        api: AccountApi(
          'https://unused.example',
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      addTearDown(accounts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: IndexedStack(
            index: 0,
            children: [
              const Text('صفحة الحساب'),
              CSharpGamesPage(accounts: accounts, visible: false),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('صفحة الحساب'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator, skipOffstage: false),
        findsNothing,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
