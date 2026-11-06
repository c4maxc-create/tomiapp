import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/app.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_models.dart';
import 'package:tomi_app/src/accounts/account_profile.dart';
import 'package:tomi_app/src/accounts/social_profile.dart';
import 'package:tomi_app/src/social/home_controller.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'package:tomi_app/src/social/story_screens.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/notifications/push_controller.dart';

import 'account_fakes.dart';
import 'media05_test.dart' show FakeDevice;

const peerId = '22222222-2222-4222-8222-222222222222';
const storyId = '33333333-3333-4333-8333-333333333333';
const postId = '44444444-4444-4444-8444-444444444444';
http.Response response(Map<String, dynamic> d, [int status = 200]) =>
    http.Response(
      jsonEncode(d),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
Map<String, dynamic> storyJson({
  String id = storyId,
  String text = 'الستوري الأولى',
}) => {
  'id': id,
  'text': text,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 24))
      .toIso8601String(),
  'author': accountJson(id: peerId, username: 'friend', name: 'صديق'),
  'seen': false,
  'isMine': false,
  'image': null,
  'video': null,
  'viewsCount': null,
};

class HomeService {
  List<Map<String, dynamic>> stories = [storyJson()];
  Completer<http.Response>? delayedStories;
  int views = 0, saves = 0, storyReads = 0;
  bool saved = false;
  List<String> publishedIds = [];
  Map<String, dynamic> get peer => {
    ...accountJson(
      id: peerId,
      username: 'friend',
      name: 'صديق',
      followers: 2,
      following: 1,
    ),
    'storyExpiresAt': stories.isEmpty ? null : stories.first['expiresAt'],
  };
  Map<String, dynamic> get post => {
    'id': postId,
    'text': 'منشور حقيقي',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'author': peer,
    'image': null,
    'video': null,
    'likesCount': 0,
    'commentsCount': 0,
    'liked': false,
    'isMine': false,
    'saved': saved,
  };
  AccountApi api() => AccountApi(
    'https://home.tomi.test',
    client: MockClient((r) async {
      final path = r.url.path;
      if (path == '/v1/me')
        return response({'user': accountJson(followers: 2, following: 1)});
      if (path == '/v1/stories' && r.method == 'GET') {
        storyReads++;
        if (delayedStories != null) return delayedStories!.future;
        return response({
          'groups': stories.isEmpty
              ? []
              : [
                  {'author': peer, 'stories': stories},
                ],
        });
      }
      if (path == '/v1/stories' && r.method == 'POST') {
        publishedIds.add((jsonDecode(r.body) as Map)['requestId'] as String);
        return response({'story': storyJson()}, 201);
      }
      if (path.endsWith('/view')) {
        views++;
        return response({'ok': true});
      }
      if (path == '/v1/posts')
        return response({
          'posts': r.url.queryParameters['userId'] != null ? [] : [post],
          'nextCursor': null,
          'imageUploadEnabled': false,
          'videoUploadEnabled': false,
        });
      if (path.endsWith('/save')) {
        saves++;
        saved = (jsonDecode(r.body) as Map)['saved'] == true;
        return response({'post': post});
      }
      if (path == '/v1/activity')
        return response({'items': [], 'unreadCount': 0, 'nextCursor': null});
      if (path.endsWith('/followers') || path.endsWith('/following'))
        return response({
          'users': [peer],
          'nextCursor': null,
        });
      if (path == '/v1/subscriptions/catalog')
        return response({
          'services': [
            for (final e in {
              'vip': 'VIP',
              'monthly': 'الباقة الشهرية',
              'tumble': 'تومبل',
              'username': 'يوزر مميز',
            }.entries)
              {
                'id': e.key,
                'name': e.value,
                'available': false,
                'price': null,
                'description': 'التفاصيل عند الإطلاق',
              },
          ],
          'purchasesEnabled': false,
        });
      if (path.startsWith('/v1/users/'))
        return response({
          'user': path.contains(peerId)
              ? peer
              : accountJson(followers: 2, following: 1),
        });
      if (path == '/v1/push/settings')
        return response({'configured': true, 'enabled': true});
      if (path == '/v1/push/device')
        return response({'configured': true, 'bindingId': 'home-binding'});
      if (path == '/v1/auth/logout') return response({'ok': true});
      return response({
        'error': {'code': 'NOT_FOUND', 'message': 'غير متاح'},
      }, 404);
    }),
  );
}

Future<AccountController> account(HomeService s) async {
  final a = AccountController(
    api: s.api(),
    vault: MemoryTokenVault('token'),
    draftStore: MemoryDraftStore(),
    realtimeEnabled: false,
  );
  await a.restore();
  addTearDown(a.dispose);
  return a;
}

Future<void> settleHome(HomeController h) async {
  for (var i = 0; i < 20 && (h.loadingStories || h.loadingActivity); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void screen(WidgetTester t, [Size size = const Size(360, 780)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(320, 640), const Size(800, 420)]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'story labels fit at ${size.width}x${size.height} with text scale $scale',
        (t) async {
          screen(t, size);
          final s = HomeService(), a = await account(s);
          await a.home.refresh();
          await t.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  boldText: scale == 2.0,
                ),
                child: child!,
              ),
              home: Scaffold(body: StoriesStrip(accounts: a)),
            ),
          );
          await t.pumpAndSettle();
          final strip = t.getRect(find.byKey(const Key('story-strip')));
          for (final id in [a.user!.id, peerId]) {
            final label = t.getRect(find.byKey(ValueKey('story-label-$id')));
            expect(label.top, greaterThanOrEqualTo(strip.top));
            expect(label.bottom, lessThanOrEqualTo(strip.bottom));
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('disabled realtime keeps manual story refresh available', (
    t,
  ) async {
    final s = HomeService(), a = await account(s), h = a.home;
    await h.refresh();
    final initialReads = s.storyReads;
    expect(initialReads, greaterThan(0));
    await t.pump(const Duration(seconds: 46));
    expect(s.storyReads, initialReads);
    await h.loadStories();
    expect(s.storyReads, initialReads + 1);
  });
  testWidgets('live home polling refreshes and stops on logout', (t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final s = HomeService(), a = await account(s), h = HomeController(a);
    try {
      await h.refresh();
      final initialReads = s.storyReads;
      await t.pump(const Duration(seconds: 45));
      await t.pump();
      expect(s.storyReads, initialReads + 1);
      await a.logout();
      final readsAtLogout = s.storyReads;
      await t.pump(const Duration(seconds: 45));
      expect(s.storyReads, readsAtLogout);
      expect(h.groups, isEmpty);
    } finally {
      h.dispose();
    }
  });
  test(
    'old story/activity responses after logout cannot restore another session',
    () async {
      final s = HomeService(), a = await account(s), h = a.home;
      await settleHome(h);
      expect(h.groups.length, 1);
      s.delayedStories = Completer<http.Response>();
      final loading = h.loadStories();
      await Future<void>.delayed(Duration.zero);
      await a.logout();
      s.delayedStories!.complete(
        response({
          'groups': [
            {'author': s.peer, 'stories': s.stories},
          ],
        }),
      );
      await loading;
      expect(h.groups, isEmpty);
      expect(h.activity, isEmpty);
      expect(h.unreadCount, 0);
    },
  );
  test(
    'view receipts update the shared ring and expired items do not count',
    () async {
      final s = HomeService(), a = await account(s), h = a.home;
      await settleHome(h);
      expect(h.unseen(peerId), true);
      await h.markViewed(h.groups.first.stories.first);
      expect(h.unseen(peerId), false);
      expect(s.views, 1);
      h.groups.first.stories.first.data['expiresAt'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      expect(h.hasStory(peerId), false);
    },
  );
  test('story metadata stays compatible with older users and posts', () {
    final u = AccountUser.fromJson(accountJson());
    expect(u.hasStory, false);
    final p = PostAuthor.fromJson(accountJson());
    expect(p.hasStory, false);
    final old = StoryItem(storyJson());
    expect(old.active, true);
    expect(old.video, isNull);
  });
  test('social push opening is bound to the signed-in account', () async {
    final a = await account(HomeService()),
        device = FakeDevice()..allowed = true,
        push = PushController(accounts: a, client: device);
    addTearDown(push.dispose);
    addTearDown(device.close);
    for (var i = 0; i < 20 && push.busy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    int opened = 0;
    push.onOpenActivity = (id) async {
      opened++;
      expect(id, a.user!.id);
    };
    push.handleOpen({'type': 'activity', 'accountId': peerId});
    await Future<void>.delayed(Duration.zero);
    expect(opened, 0);
    push.handleOpen({'type': 'activity', 'accountId': a.user!.id});
    await Future<void>.delayed(Duration.zero);
    expect(opened, 1);
    String? exactActivity;
    push.onOpenActivityItem = (id, activity) async {
      expect(id, a.user!.id);
      exactActivity = activity;
    };
    push.handleOpen({
      'type': 'activity',
      'accountId': peerId,
      'activityId': peerId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(exactActivity, isNull);
    push.handleOpen({
      'type': 'activity',
      'accountId': a.user!.id,
      'activityId': peerId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(exactActivity, peerId);
    expect(opened, 1);
    String? exactNotice;
    push.onOpenNotice = (id, notice) async {
      expect(id, a.user!.id);
      exactNotice = notice;
    };
    push.handleOpen({
      'type': 'notice',
      'accountId': peerId,
      'noticeId': peerId,
    });
    push.handleOpen({
      'type': 'notice',
      'accountId': a.user!.id,
      'noticeId': 'bad',
    });
    await Future<void>.delayed(Duration.zero);
    expect(exactNotice, isNull);
    push.handleOpen({
      'type': 'notice',
      'accountId': a.user!.id,
      'noticeId': peerId,
    });
    await Future<void>.delayed(Duration.zero);
    expect(exactNotice, peerId);
  });
  testWidgets(
    'avatar opens an active story and no-story avatar opens its full picture',
    (t) async {
      screen(t);
      final s = HomeService(), a = await account(s);
      late BuildContext c;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              c = context;
              return Scaffold(
                body: TextButton(
                  onPressed: () =>
                      openStoryAvatar(c, a, AccountUser.fromJson(s.peer)),
                  child: const Text('افتح الصورة'),
                ),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('افتح الصورة'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(find.byType(StoryViewerPage), findsOneWidget);
      expect(find.text('الستوري الأولى'), findsOneWidget);
      await t.tap(find.byTooltip('إغلاق'));
      await t.pumpAndSettle();
      s.stories = [];
      await t.tap(find.text('افتح الصورة'));
      await t.pumpAndSettle();
      expect(find.byType(StoryViewerPage), findsNothing);
      expect(find.text('friend'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('story tap advances and long hold pauses automatic progress', (
    t,
  ) async {
    screen(t);
    final s = HomeService(), a = await account(s);
    final group = StoryGroup(
      author: PostAuthor.fromJson(s.peer),
      stories: [
        StoryItem(storyJson()),
        StoryItem(storyJson(id: postId, text: 'الستوري الثانية')),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StoryViewerPage(accounts: a, groups: [group]),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final gesture = await t.startGesture(const Offset(180, 360));
    await t.pump(const Duration(milliseconds: 650));
    await t.pump(const Duration(seconds: 8));
    expect(find.text('الستوري الأولى'), findsOneWidget);
    await gesture.up();
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(const Offset(300, 360));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('الستوري الثانية'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'profile menu exposes settings and the four upcoming subscriptions',
    (t) async {
      screen(t);
      final s = HomeService(), a = await account(s);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: AccountProfileScreen(accounts: a)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('متابعون'), findsOneWidget);
      await t.tap(find.byKey(const Key('profile-menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profile-menu-settings')));
      await t.pumpAndSettle();
      expect(find.text('تغيير كلمة المرور'), findsOneWidget);
      expect(find.text('تغيير الصورة الشخصية'), findsOneWidget);
      Navigator.pop(t.element(find.byType(AccountSettingsPage)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profile-menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profile-menu-subscriptions')));
      await t.pumpAndSettle();
      for (final name in ['VIP', 'الباقة الشهرية', 'تومبل', 'يوزر مميز']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'following count opens actual accounts instead of a decorative number',
    (t) async {
      screen(t);
      final s = HomeService(), a = await account(s);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: AccountProfileScreen(accounts: a)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('متابعون'));
      await t.pumpAndSettle();
      expect(find.byType(FollowersPage), findsOneWidget);
      expect(find.text('friend'), findsOneWidget);
      await t.tap(find.text('friend'));
      await t.pumpAndSettle();
      expect(find.byType(UserAccountPage), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('home saving uses the authenticated endpoint', (t) async {
    screen(t);
    final s = HomeService(), a = await account(s);
    await t.pumpWidget(TomiApp(accounts: a));
    await t.pumpAndSettle();
    final target = find.byKey(const Key('save-$postId'));
    await t.ensureVisible(target);
    await t.tap(target);
    await t.pumpAndSettle();
    expect(s.saves, 1);
    expect(s.saved, true);
    expect(t.takeException(), isNull);
  });
}
