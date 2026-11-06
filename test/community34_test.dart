import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/experience/community_pages.dart';
import 'package:tomi_app/src/design/tomi_theme.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chat;

class ToolsFake extends chat.ChatFakeApi {
  int choice = -1;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/polls/poll/vote') {
      choice = body!['choice'] as int;
      return {'ok': true};
    }
    if (path == '/v1/polls')
      return {
        'items': [
          {
            'id': 'poll',
            'question': 'شنو نلعب اليوم؟',
            'options': ['أونو', 'جاكارو'],
            'counts': [choice == 0 ? 1 : 0, choice == 1 ? 1 : 0],
            'mine': choice == -1 ? null : choice,
            'endsAt': '2026-11-07',
            'closed': false,
          },
        ],
      };
    if (path == '/v1/me/support')
      return {
        'items': [
          {
            'id': 'ticket',
            'subject': 'فيديو ما ينرفع',
            'body': 'توقف الرفع عند النهاية',
            'status': 'answered',
            'reply': 'أعد تجهيز الفيديو ثم حاول مجدداً',
            'revision': 1,
          },
        ],
      };
    if (path == '/v1/me/explore-preferences')
      return {
        'keywords': ['spam'],
        'topics': [],
        'hidden': [],
      };
    if (path == '/v1/me/contact-exceptions' ||
        path == '/v1/me/invitations' ||
        path == '/v1/me/gift-history')
      return {'items': []};
    if (path == '/v1/me/connection-check')
      return {
        'configured': {
          'calls': false,
          'rooms': false,
          'live': false,
          'media': false,
        },
      };
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<AccountController> account(ToolsFake api) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('token'),
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

void main() {
  testWidgets(
    'support shows actual private reply and polls commit a choice then refresh counts',
    (t) async {
      final api = ToolsFake(), a = await account(api);
      await t.pumpWidget(
        MaterialApp(
          home: CommunityPage(accounts: a, kind: 'support', title: 'الدعم'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('تم الرد'), findsOneWidget);
      expect(find.textContaining('رد الإدارة:'), findsOneWidget);
      await t.pumpWidget(
        MaterialApp(
          home: CommunityPage(
            key: const ValueKey('polls'),
            accounts: a,
            kind: 'polls',
            title: 'التصويت',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('جاكارو · 0'));
      await t.pumpAndSettle();
      expect(api.choice, 1);
      expect(find.text('✓ جاكارو · 1'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'community pages fit 320 pixels with doubled Arabic text including loading diagnostic fallback',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final a = await account(ToolsFake());
      for (final kind in [
        'support',
        'polls',
        'explore',
        'exceptions',
        'invitations',
        'gifts',
        'diagnostics',
      ]) {
        await t.pumpWidget(
          MaterialApp(
            theme: TomiTheme.dark(),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: w!,
            ),
            home: CommunityPage(
              key: ValueKey(kind),
              accounts: a,
              kind: kind,
              title: 'أدوات التطبيق',
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: kind);
      }
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}
