import 'package:tomi_app/src/design/tomi_theme.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/experience/experience_pages.dart';
import 'package:tomi_app/src/experience/performance_monitor.dart';
import 'package:tomi_app/src/preferences/media_preferences.dart';
import 'package:tomi_app/src/messaging/video_editor.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chats;

Future<AccountController> account(ExperienceFake api) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('token'),
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'unified search returns people rooms and posts and switches categories without losing its query',
    (t) async {
      final api = ExperienceFake(), a = await account(api);
      await t.pumpWidget(MaterialApp(home: UnifiedSearchPage(accounts: a)));
      await t.enterText(
        find.byKey(const Key('account-search-input')),
        'needle',
      );
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(find.text('needle room'), findsOneWidget);
      expect(find.text('needle post'), findsOneWidget);
      expect(find.text('صديق البحث'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'منشورات'));
      await t.pumpAndSettle();
      expect(find.text('needle room'), findsNothing);
      expect(find.text('needle post'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('account-search-input')))
            .controller!
            .text,
        'needle',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'device page revokes another session after confirmation and refreshes the actual list',
    (t) async {
      final api = ExperienceFake(), a = await account(api);
      await t.pumpWidget(MaterialApp(home: SessionSecurityPage(accounts: a)));
      await t.pumpAndSettle();
      expect(find.text('هاتف آخر'), findsOneWidget);
      await t.tap(find.byTooltip('تسجيل خروج الجهاز'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'تسجيل الخروج'));
      await t.pumpAndSettle();
      expect(api.revoked, 1);
      expect(find.text('هاتف آخر'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'saving to a named collection commits the selected post and closes the chooser',
    (t) async {
      final api = ExperienceFake(), a = await account(api);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SavedCollectionsPage(accounts: a, postId: 'post-test'),
                  ),
                ),
                child: const Text('مجموعاتي'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('مجموعاتي'));
      await t.pumpAndSettle();
      await t.tap(find.text('تعليم'));
      await t.pumpAndSettle();
      expect(api.addedPost, 'post-test');
      expect(find.text('مجموعاتي'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'new account tools fit a compact screen with doubled Arabic text',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = ExperienceFake(), a = await account(api);
      for (final page in [
        UnifiedSearchPage(accounts: a),
        SessionSecurityPage(accounts: a),
        SavedCollectionsPage(accounts: a),
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
            home: page,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      await t.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  test(
    'performance collection is opt-in and its payload contains no URL token response body or account identifier',
    () async {
      final prefs = MediaPreferences.instance,
          monitor = PerformanceMonitor.instance;
      final batches = <List<Map<String, dynamic>>>[];
      await prefs.update(reports: false);
      monitor.bind((m) async => batches.add(m));
      monitor.record('flutter_error', 'ui', 0);
      expect(monitor.pending, isEmpty);
      await prefs.update(reports: true);
      monitor.bind((m) async => batches.add(m));
      final api = AccountApi(
        'https://example.com',
        client: MockClient(
          (r) async => http.Response(
            '{"private":"hidden-message"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await api.chatRequest(
        'secret-token',
        'GET',
        '/v1/chats/private-account-id',
      );
      await monitor.flush();
      expect(batches.single.single['area'], 'chat');
      final raw = jsonEncode(batches);
      for (final secret in [
        'secret-token',
        'private-account-id',
        'hidden-message',
        'https://',
      ])
        expect(raw.contains(secret), false);
      monitor.bind(null);
      await prefs.update(reports: false);
    },
  );
  testWidgets(
    'video editor bounds a five-minute source to three minutes and selects a cover without autoplay',
    (t) async {
      final old = VideoPlayerPlatform.instance, fake = VideoFake();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      await t.pumpWidget(
        MaterialApp(
          home: VideoEditorPage(
            file: XFile.fromData(Uint8List(100), name: 'movie.mp4'),
          ),
        ),
      );
      await t.pumpAndSettle();
      final range = t.widget<RangeSlider>(
        find.byKey(const Key('video-trim-range')),
      );
      expect(range.values.end - range.values.start, 180);
      expect(fake.plays, 0);
      await t.scrollUntilVisible(
        find.byKey(const Key('video-cover-frame')),
        250,
      );
      final slider = t.widget<Slider>(
        find.byKey(const Key('video-cover-frame')),
      );
      slider.onChanged!(45);
      await t.pump();
      slider.onChangeEnd!(45);
      await t.pump();
      expect(fake.position.inSeconds, 45);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}

class ExperienceFake extends chats.ChatFakeApi {
  int revoked = 0;
  String? addedPost;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/search')
      return {
        'users': [
          accountJson(
            id: '22222222-2222-4222-8222-222222222222',
            name: 'صديق البحث',
          ),
        ],
        'rooms': [
          {'id': 'room-test', 'title': 'needle room'},
        ],
        'posts': [
          {
            'id': 'post-test',
            'text': 'needle post',
            'createdAt': '2026-11-06T00:00:00Z',
            'author': {'displayName': 'كاتب'},
          },
        ],
      };
    if (path.startsWith('/v1/me/sessions')) {
      if (method == 'DELETE') revoked++;
      return {
        'sessions': [
          {
            'id': 'current',
            'label': 'هاتفي',
            'platform': 'android',
            'current': true,
            'createdAt': '2026-11-06T00:00:00Z',
            'lastSeenAt': '2026-11-06T00:00:00Z',
          },
          if (revoked == 0)
            {
              'id': 'other',
              'label': 'هاتف آخر',
              'platform': 'android',
              'current': false,
              'createdAt': '2026-11-06T00:00:00Z',
              'lastSeenAt': '2026-11-06T00:00:00Z',
            },
        ],
      };
    }
    if (path == '/v1/me/collections')
      return {
        'collections': [
          {'id': 'collection-test', 'name': 'تعليم', 'count': 0},
        ],
      };
    if (path.startsWith('/v1/me/collections/') && method == 'PUT') {
      addedPost = path.split('/').last;
      return {'saved': true};
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

class VideoFake extends VideoPlayerPlatform {
  int plays = 0;
  Duration position = Duration.zero;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int id) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 5),
      size: const Size(320, 180),
    ),
  );
  @override
  Future<void> dispose(int id) async {}
  @override
  Future<void> play(int id) async {
    plays++;
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool value) async {}
  @override
  Future<void> seekTo(int id, Duration value) async {
    position = value;
  }

  @override
  Future<Duration> getPosition(int id) async => position;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}
