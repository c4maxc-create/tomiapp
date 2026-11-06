import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/wallet/wallet_page.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'package:tomi_app/src/live/live_pages.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chats;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scale in [1.0, 2.0])
    testWidgets(
      'wallet is six display-only offers in three columns at text scale $scale',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: w!,
            ),
            home: const WalletPage(),
          ),
        );
        await t.pumpAndSettle();
        expect(walletOffers.map((e) => e.total), [
          430,
          810,
          2200,
          3700,
          14000,
          71000,
        ]);
        final first = t.getRect(find.byKey(const ValueKey('wallet-offer-0'))),
            third = t.getRect(find.byKey(const ValueKey('wallet-offer-2'))),
            fourth = t.getRect(find.byKey(const ValueKey('wallet-offer-3')));
        expect(first.top, third.top);
        expect(fourth.top, greaterThan(first.bottom));
        expect(first.width, closeTo(first.height, .5));
        await t.ensureVisible(find.byKey(const ValueKey('wallet-offer-0')));
        await t.tap(find.byKey(const ValueKey('wallet-offer-0')));
        await t.pumpAndSettle();
        expect(find.text('الشراء قريبًا'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  testWidgets('actual chat voice bubble exposes 2x and 3x playback controls', (
    t,
  ) async {
    final (a, api, thread) = await chats.setup();
    api.rows.add({
      ...api.row(1),
      'text': '',
      'audio': {'url': 'https://example.com/test.m4a', 'durationMs': 3000},
    });
    await thread.sync();
    await t.pumpWidget(
      MaterialApp(
        home: PrivateChatPage(
          chats: a.chats,
          conversation: thread.conversation,
        ),
      ),
    );
    await t.pumpAndSettle();
    final key = find.byKey(const ValueKey('chat-voice-speed-message-1'));
    await t.tap(key);
    await t.pumpAndSettle();
    expect(find.text('2×'), findsOneWidget);
    await t.tap(key);
    await t.pumpAndSettle();
    expect(find.text('3×'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    a.dispose();
  });
  testWidgets(
    'permission failure in live preparation cannot create an empty public broadcast',
    (t) async {
      final api = LiveGateApi(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
          );
      await a.restore();
      await t.pumpWidget(MaterialApp(home: LiveHub(accounts: a)));
      await t.pumpAndSettle();
      await t.tap(find.text('بدء بث مباشر'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'بث جديد');
      await t.tap(find.text('متابعة'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('تجهيز البث'), findsOneWidget);
      expect(api.starts, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      a.dispose();
    },
  );
  test(
    'definitively rejected video is repaired with a new request and upload without duplicating an accepted message',
    () async {
      final api = RepairApi(),
          a = AccountController(
            api: api,
            vault: MemoryTokenVault('token'),
            realtimeEnabled: false,
            draftStore: MemoryDraftStore(),
          );
      await a.restore();
      final thread = a.chats.thread(
        DirectConversation.fromJson(api.conversation),
      );
      await thread.sync();
      thread.enqueue(
        'فيديو',
        null,
        video: VideoDraft(
          Uint8List.fromList([1, 2, 3]),
          durationMs: 1000,
          width: 640,
          height: 360,
        ),
      );
      for (
        var i = 0;
        i < 50 && thread.pending.firstOrNull?.videoRepair != true;
        i++
      )
        await Future<void>.delayed(Duration.zero);
      final p = thread.pending.single;
      expect(p.videoRepair, true);
      final old = p.requestId;
      thread.videoRepairer = (_) async => VideoDraft(
        Uint8List.fromList([4, 5, 6]),
        durationMs: 1000,
        width: 640,
        height: 360,
      );
      await thread.retryPending(p, manual: true);
      for (var i = 0; i < 50 && thread.pending.isNotEmpty; i++)
        await Future<void>.delayed(Duration.zero);
      expect(thread.pending, isEmpty);
      expect(api.nonces.length, 2);
      expect(api.nonces.first, old);
      expect(api.nonces.last, isNot(old));
      expect(api.rows.length, 1);
      a.dispose();
    },
  );
}

class LiveGateApi extends chats.ChatFakeApi {
  int starts = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/lives') {
      if (method == 'POST') starts++;
      return {'configured': true, 'lives': []};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class RepairApi extends chats.ChatFakeApi {
  final nonces = <String>[];
  int prepared = 0;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/videos'))
      return {
        'uploadId': 'video-${++prepared}',
        'uploadUrl': 'https://test.r2.cloudflarestorage.com/bucket/video',
        'headers': {
          'content-type': 'video/mp4',
          'content-md5': body!['contentMd5'],
          'if-none-match': '*',
        },
      };
    if (path.endsWith('/messages') && method == 'POST') {
      nonces.add(body!['requestId'] as String);
      if (nonces.length == 1)
        throw const AccountFailure(
          'INVALID_VIDEO',
          'invalid video',
          status: 400,
        );
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}
