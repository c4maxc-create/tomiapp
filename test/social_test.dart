import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/app.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/social/feed_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'package:tomi_app/src/social/social_screens.dart';

import 'account_fakes.dart';

http.Response reply(Map<String, dynamic> d, [int code = 200]) => http.Response(
  jsonEncode(d),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> postJson({
  String id = '22222222-2222-4222-8222-222222222222',
  String text = 'منشور محفوظ',
  bool liked = false,
  int comments = 0,
}) => {
  'id': id,
  'text': text,
  'createdAt': '2026-10-13T00:00:00.000Z',
  'author': {
    'id': accountJson()['id'],
    'username': 'tolo',
    'displayName': 'تولو',
    'avatarPreset': 'panda',
  },
  'image': null,
  'likesCount': liked ? 1 : 0,
  'commentsCount': comments,
  'liked': liked,
  'isMine': true,
};
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void screen(WidgetTester t, Size size) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

class TestGallery extends ImagePickerPlatform {
  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async => [];
}

void main() {
  for (final viewport in [const Size(320, 640), const Size(800, 420)]) {
    testWidgets('comment errors and keyboard remain scrollable on $viewport', (
      t,
    ) async {
      screen(t, viewport);
      final a = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault('token'),
        api: AccountApi(
          'https://tomi.example',
          client: MockClient((r) async {
            if (r.url.path == '/v1/me') return reply({'user': accountJson()});
            return reply({
              'error': {
                'code': 'UNAVAILABLE',
                'message':
                    'تعذّر تحميل التعليقات؛ تأكد من الاتصال وجرّب مرة ثانية.',
              },
            }, 503);
          }),
        ),
      );
      addTearDown(a.dispose);
      await a.restore();
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: viewport,
              viewInsets: const EdgeInsets.only(bottom: 200),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: RealCommentsSheet(
                accounts: a,
                post: SocialPost.fromJson(postJson()),
                onUpdated: (_) {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('comment-input')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('comment-input')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'real publication keeps draft and request ID after a failed response',
    (t) async {
      screen(t, const Size(320, 640));
      var attempts = 0;
      String? firstRequest;
      final posts = <Map<String, dynamic>>[];
      final a = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault('token'),
        api: AccountApi(
          'https://tomi.example',
          client: MockClient((r) async {
            if (r.url.path == '/v1/me') return reply({'user': accountJson()});
            if (r.method == 'GET' && r.url.path == '/v1/posts')
              return reply({
                'posts': posts,
                'nextCursor': null,
                'imageUploadEnabled': false,
              });
            if (r.method == 'POST' && r.url.path == '/v1/posts') {
              final b = jsonDecode(r.body);
              firstRequest ??= b['requestId'] as String;
              expect(b['requestId'], firstRequest);
              attempts++;
              if (attempts == 1)
                return reply({
                  'error': {'code': 'UNAVAILABLE', 'message': 'جرّب مرة ثانية'},
                }, 503);
              final p = postJson(text: b['text'] as String);
              posts.add(p);
              return reply({
                'post': p,
                'user': {...accountJson(), 'postsCount': 1},
              }, 201);
            }
            return reply({
              'error': {'code': 'NOT_FOUND', 'message': 'غير موجود'},
            }, 404);
          }),
        ),
      );
      addTearDown(a.dispose);
      await a.restore();
      await t.pumpWidget(
        TomiApp(accounts: a, textScaler: const TextScaler.linear(1.5)),
      );
      await t.pumpAndSettle();
      final previousPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = TestGallery();
      addTearDown(() => ImagePickerPlatform.instance = previousPicker);
      FlutterSecureStorage.setMockInitialValues({});
      await tapVisible(t, find.byKey(const Key('compose-post')));
      await t.enterText(find.byKey(const Key('post-input')), 'لحظتي الحلوة');
      t.binding.focusManager.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const Key('publish-post')));
      expect(find.text('جرّب مرة ثانية'), findsOneWidget);
      expect(find.text('لحظتي الحلوة'), findsOneWidget);
      await tapVisible(t, find.byKey(const Key('publish-post')));
      expect(a.user!.postsCount, 1);
      await t.scrollUntilVisible(
        find.text('لحظتي الحلوة'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('لحظتي الحلوة'), findsOneWidget);
      expect(attempts, 2);
      expect(t.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 640), const Size(800, 420)]) {
    testWidgets('real feed, likes and comments fit enlarged text on $size', (
      t,
    ) async {
      screen(t, size);
      var p = postJson();
      final comments = <Map<String, dynamic>>[];
      final a = AccountController(
        realtimeEnabled: false,
        vault: MemoryTokenVault('token'),
        api: AccountApi(
          'https://tomi.example',
          client: MockClient((r) async {
            if (r.url.path == '/v1/me') return reply({'user': accountJson()});
            if (r.url.path == '/v1/posts')
              return reply({
                'posts': [p],
                'nextCursor': null,
                'imageUploadEnabled': true,
              });
            if (r.url.path.endsWith('/like')) {
              p = {...p, 'liked': true, 'likesCount': 1};
              return reply({'post': p});
            }
            if (r.url.path.endsWith('/comments')) {
              if (r.method == 'GET')
                return reply({'comments': comments, 'nextCursor': null});
              final b = jsonDecode(r.body);
              final c = {
                'id': '33333333-3333-4333-8333-333333333333',
                'text': b['text'],
                'author': p['author'],
                'createdAt': p['createdAt'],
                'isMine': true,
              };
              comments.add(c);
              p = {...p, 'commentsCount': 1};
              return reply({'comment': c, 'post': p}, 201);
            }
            return reply({'user': accountJson()});
          }),
        ),
      );
      addTearDown(a.dispose);
      await a.restore();
      await t.pumpWidget(
        TomiApp(accounts: a, textScaler: const TextScaler.linear(1.5)),
      );
      await t.pumpAndSettle();
      final id = p['id'] as String;
      final like = find.byKey(Key('like-' + id));
      await t.scrollUntilVisible(
        like,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(t, like);
      expect(p['likesCount'], 1);
      await tapVisible(t, find.byKey(Key('comments-' + id)));
      await t.enterText(find.byKey(const Key('comment-input')), 'تعليق محفوظ');
      t.binding.focusManager.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await tapVisible(t, find.byKey(const Key('send-comment')));
      expect(find.text('تعليق محفوظ'), findsOneWidget);
      expect(p['commentsCount'], 1);
      expect(t.takeException(), isNull);
    });
  }
  test('R2 receives exact bytes and checksum without the account token', () async {
    final bytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
      ),
    );
    final image = ImageDraft(bytes, 'image/png');
    var uploaded = false;
    final api = AccountApi(
      'https://tomi.example',
      client: MockClient((r) async {
        expect(r.method, 'PUT');
        expect(r.url.host, 'a.r2.cloudflarestorage.com');
        expect(r.headers.containsKey('authorization'), false);
        expect(r.headers['content-md5'], image.contentMd5);
        expect(r.headers['if-none-match'], '*');
        expect(r.bodyBytes, bytes);
        uploaded = true;
        return http.Response('', 412);
      }),
    );
    addTearDown(api.close);
    await api.uploadImage(
      ImageUpload(
        id: 'upload',
        url: Uri.parse(
          'https://a.r2.cloudflarestorage.com/bucket/image.png?signature=test',
        ),
        headers: {
          'content-type': 'image/png',
          'content-md5': image.contentMd5,
          'if-none-match': '*',
        },
      ),
      image,
    );
    expect(uploaded, true);
  });
  test('late feed responses cannot replace a newly selected scope', () async {
    final old = Completer<http.Response>();
    final a = AccountController(
      realtimeEnabled: false,
      vault: MemoryTokenVault('token'),
      api: AccountApi(
        'https://tomi.example',
        client: MockClient((r) async {
          if (r.url.path == '/v1/me') return reply({'user': accountJson()});
          if (r.url.queryParameters['scope'] == 'explore') return old.future;
          return reply({
            'posts': [postJson(text: 'متابعاتي')],
            'nextCursor': null,
          });
        }),
      ),
    );
    addTearDown(a.dispose);
    await a.restore();
    final feed = FeedController(accounts: a);
    addTearDown(feed.dispose);
    final first = feed.refresh();
    await Future<void>.delayed(Duration.zero);
    await feed.select('following');
    old.complete(
      reply({
        'posts': [postJson(text: 'قديم')],
        'nextCursor': null,
      }),
    );
    await first;
    expect(feed.posts.single.text, 'متابعاتي');
  });
}
