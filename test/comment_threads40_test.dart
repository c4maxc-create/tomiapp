import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/social/social_screens.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'social_test.dart' show postJson;

const root = '22222222-2222-4222-8222-222222222222',
    child = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> item(
  String id,
  String body, {
  String? parentId,
  String? rootId,
  int count = 0,
}) => {
  'id': id,
  'text': body,
  'parentId': parentId,
  'rootId': rootId,
  'replyCount': count,
  'createdAt': '2026-11-07T12:00:00.000Z',
  'author': accountJson(username: 'peer_name', name: 'صاحب التعليق'),
  'isMine': false,
  if (parentId != null) 'replyToUsername': 'original_user',
};
void main() {
  for (final size in [const Size(390, 844), const Size(320, 640)])
    testWidgets(
      'thread replies expand, target a reply and cancel before root send on $size',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final requests = <Map<String, dynamic>>[];
        final api = AccountApi(
          'https://example.com',
          client: MockClient((r) async {
            Map<String, dynamic> data;
            if (r.url.path == '/v1/me')
              data = {'user': accountJson()};
            else if (r.url.path.endsWith('/comments')) {
              if (r.method == 'POST') {
                final body = jsonDecode(r.body) as Map<String, dynamic>;
                requests.add(body);
                data = {
                  'comment': item(
                    '44444444-4444-4444-8444-444444444444',
                    body['text'] as String,
                    parentId: body['parentId'] as String?,
                    rootId: body['parentId'] == null ? null : root,
                  ),
                  'post': postJson(comments: 4),
                };
              } else if (r.url.queryParameters['parentId'] != null)
                data = {
                  'threaded': true,
                  'root': item(root, 'original comment', count: 2),
                  'comments': [
                    item(
                      child,
                      'first nested reply',
                      parentId: root,
                      rootId: root,
                    ),
                  ],
                  'nextCursor': null,
                };
              else
                data = {
                  'threaded': true,
                  'comments': [item(root, 'original comment', count: 2)],
                  'nextCursor': null,
                };
            } else
              data = {
                'error': {'code': 'NOT_FOUND', 'message': 'not available'},
              };
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final account = AccountController(
          api: api,
          vault: MemoryTokenVault('token'),
          realtimeEnabled: false,
        );
        await account.restore();
        addTearDown(account.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RealCommentsSheet(
                accounts: account,
                post: SocialPost.fromJson(postJson()),
                onUpdated: (_) {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.textContaining('first nested reply', findRichText: true),
          findsNothing,
        );
        final toggle = find.byKey(const ValueKey('toggle-replies-$root'));
        await t.ensureVisible(toggle);
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(
          find.textContaining('first nested reply', findRichText: true),
          findsOneWidget,
        );
        final reply = find.byKey(const ValueKey('reply-comment-$child'));
        await t.ensureVisible(reply);
        await t.tap(reply);
        await t.pumpAndSettle();
        final input = find.byKey(const Key('comment-input'));
        await t.ensureVisible(input);
        await t.enterText(input, 'reply to child');
        final send = find.byKey(const Key('send-comment'));
        await t.ensureVisible(send);
        await t.tap(send);
        await t.pumpAndSettle();
        expect(requests.single['parentId'], child);
        await t.ensureVisible(toggle);
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(
          find.textContaining('first nested reply', findRichText: true),
          findsNothing,
        );
        final rootReply = find.byKey(const ValueKey('reply-comment-$root'));
        await t.ensureVisible(rootReply);
        await t.tap(rootReply);
        await t.pumpAndSettle();
        final close = find.byIcon(Icons.close);
        await t.ensureVisible(close);
        await t.tap(close);
        await t.pumpAndSettle();
        await t.ensureVisible(input);
        await t.enterText(input, 'new root comment');
        await t.ensureVisible(send);
        await t.tap(send);
        await t.pumpAndSettle();
        expect(requests.last['parentId'], isNull);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
}
