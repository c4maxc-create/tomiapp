import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/experience/send_invitation_page.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chats;

class InviteApi extends chats.ChatFakeApi {
  final requests = <String>[];
  @override
  Future<List<AccountUser>> search(String token, String query) async => [
    AccountUser.fromJson(
      accountJson(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'صديق الدعوة',
      ),
    ),
  ];
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/me/invitations') {
      requests.add(body!['requestId'] as String);
      if (requests.length == 1)
        throw const AccountFailure('NETWORK', 'النت انقطع');
      return {'item': body};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

void main() {
  testWidgets(
    'room invitation retries the same request and does not send twice after confirmation',
    (t) async {
      final api = InviteApi(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
          );
      await a.restore();
      addTearDown(a.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: SendInvitationPage(
            accounts: a,
            kind: 'room',
            targetId: '33333333-3333-4333-8333-333333333333',
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'friend');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('إرسال الدعوة'));
      await t.pumpAndSettle();
      expect(api.requests.length, 1);
      await t.tap(find.byTooltip('إرسال الدعوة'));
      await t.pumpAndSettle();
      expect(api.requests.length, 2);
      expect(api.requests[0], api.requests[1]);
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'تم إرسال الدعوة',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
