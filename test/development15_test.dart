import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/roulette/roulette_page.dart';
import 'chat_test.dart' show ChatFakeApi;
import 'messaging10_test.dart' show chatAccount, thread;

class Tools15Api extends ChatFakeApi {
  Completer<Map<String, dynamic>>? toolGate;
  int toolCalls = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (method == 'PUT' &&
        (path.endsWith('/reaction') || path.endsWith('/pin'))) {
      toolCalls++;
      return toolGate!.future;
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class Roulette15Api extends ChatFakeApi {
  final requestIds = <String>[];
  bool lose = true, allowed = true;
  Map<String, dynamic> get config => {
    'revision': 0,
    'mode': 'everyone',
    'dailyLimit': 5,
    'prizes': [
      {'id': 'a', 'label': 'نجمة', 'icon': '⭐', 'coins': 10, 'weight': 1},
      {'id': 'b', 'label': 'هلال', 'icon': '🌙', 'coins': 20, 'weight': 1},
    ],
  };
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/roulette') && method == 'GET')
      return {
        'config': config,
        'allowed': allowed,
        'remaining': 5,
        'day': '2026-10-29',
        'recent': [],
      };
    if (path.endsWith('/roulette/spin')) {
      requestIds.add(body!['requestId'] as String);
      if (lose) {
        lose = false;
        throw const AccountFailure('NETWORK', 'انقطع الرد.');
      }
      return {
        'requestId': body['requestId'],
        'index': 0,
        'prize': config['prizes'][0],
        'prizes': config['prizes'],
        'coins': 1010,
        'remaining': 4,
        'day': '2026-10-29',
        'createdAt': '2026-10-29T00:00:00Z',
      };
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'reaction preview is immediate, leaves authoritative revisions intact and rolls back to the latest remote state',
    () async {
      final api = Tools15Api();
      final account = await chatAccount(api, MemoryDraftStore());
      addTearDown(account.dispose);
      final t = await thread(account, api), m = api.row(1);
      t.merge([
        {
          ...m,
          'revision': 1,
          'reactions': [
            {'emoji': '👍', 'count': 2, 'mine': true},
          ],
        },
      ]);
      api.toolGate = Completer();
      final pending = t.changeTool(t.messages.single, 'reaction', {
        'emoji': '❤️',
      });
      expect(
        t.messages.single.reactions.firstWhere(
          (r) => r['emoji'] == '❤️',
        )['mine'],
        true,
      );
      expect(t.cache[m['id']]!.revision, 1);
      expect(t.cache[m['id']]!.reactions.single['emoji'], '👍');
      t.merge([
        {
          ...m,
          'revision': 3,
          'reactions': [
            {'emoji': '🔥', 'count': 4, 'mine': false},
          ],
        },
      ]);
      final failed = expectLater(pending, throwsA(isA<AccountFailure>()));
      api.toolGate!.completeError(const AccountFailure('NETWORK', 'offline'));
      await failed;
      expect(t.messages.single.revision, 3);
      expect(t.messages.single.reactions.single['emoji'], '🔥');
      expect(t.pendingReactions, isEmpty);
    },
  );
  test(
    'pin preview rolls back on failure and rapid repeated reaction submits only once',
    () async {
      final api = Tools15Api(), a = await chatAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      final t = await thread(a, api);
      t.merge([api.row(1)]);
      api.toolGate = Completer();
      final pin = t.changeTool(t.messages.single, 'pin', {'pinned': true});
      expect(t.pinnedMessageId, t.messages.single.id);
      final failed = expectLater(pin, throwsA(isA<AccountFailure>()));
      api.toolGate!.completeError(const AccountFailure('NETWORK', 'offline'));
      await failed;
      expect(t.pinnedMessageId, isNull);
      api.toolGate = Completer();
      final m = t.messages.single,
          one = t.changeTool(m, 'reaction', {'emoji': '❤️'});
      await t.changeTool(m, 'reaction', {'emoji': '🔥'});
      expect(api.toolCalls, 2);
      api.toolGate!.complete({
        'message': {
          ...m.data,
          'revision': 1,
          'reactions': [
            {'emoji': '❤️', 'count': 1, 'mine': true},
          ],
        },
        'conversation': api.conversation,
      });
      await one;
      expect(t.pendingTools, isEmpty);
      expect(t.messages.single.reactions.single['emoji'], '❤️');
    },
  );
  const recoveryTest =
      'lost roulette acknowledgement retries the exact saved turn and shows the server prize';
  const recoveryViewports = [
    Size(800, 600),
    Size(400, 900),
    Size(320, 640),
    Size(800, 420),
  ];
  for (var i = 0; i < recoveryViewports.length; i++) {
    final viewport = recoveryViewports[i];
    testWidgets(i == 0 ? recoveryTest : '$recoveryTest on $viewport', (
      tester,
    ) async {
      // MediaQuery alone does not resize the test render surface. Use the
      // actual viewport for both layout and scroll/hit-test calculations.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = Roulette15Api(),
          a = await chatAccount(api, MemoryDraftStore());
      addTearDown(a.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: RoulettePage(accounts: a, roomId: 'room15'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('roulette-spin'));
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('استعادة المحاولة'), findsOneWidget);
      expect(api.requestIds.length, 1);
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.requestIds.length, 2);
      expect(api.requestIds[0], api.requestIds[1]);
      expect(a.voiceRooms.coins, 1010);

      // ListView creates off-screen children lazily. Reach the result just as
      // a user would; finding the fixed spin button cannot scroll this list.
      final balance = find.textContaining('رصيدك 1010');
      await tester.scrollUntilVisible(
        balance,
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      expect(balance, findsOneWidget);
      expect(balance.hitTestable(), findsOneWidget);
      expect(find.text('+10 كوينز • رصيدك 1010'), findsOneWidget);
      expect(api.requestIds.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
  testWidgets('disabled roulette cannot submit even with daily attempts left', (
    tester,
  ) async {
    final api = Roulette15Api()..allowed = false,
        a = await chatAccount(api, MemoryDraftStore());
    addTearDown(a.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RoulettePage(accounts: a, roomId: 'room15'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('roulette-spin')))
          .onPressed,
      isNull,
    );
    expect(api.requestIds, isEmpty);
  });
}
