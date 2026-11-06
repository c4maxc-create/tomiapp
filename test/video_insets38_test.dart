import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:tomi_app/src/app.dart';
import 'package:tomi_app/src/model.dart';
import 'package:tomi_app/src/messaging/video_editor.dart';
import 'experience33_test.dart' show VideoFake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a native compression exception never locks the next video attempt',
    () async {
      const channel = MethodChannel('video_compress');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      int calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'compressVideo') {
          if (++calls == 1)
            throw MissingPluginException('simulated native failure');
          return jsonEncode({'path': '/tmp/prepared.mp4', 'duration': 17000});
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        VideoCompress.dispose();
      });
      await expectLater(
        VideoCompress.compressVideo('/tmp/source.mp4'),
        throwsA(isA<MissingPluginException>()),
      );
      expect(VideoCompress.isCompressing, false);
      final result = await VideoCompress.compressVideo('/tmp/source.mp4');
      expect(result?.duration, 17000);
      expect(calls, 2);
      expect(VideoCompress.isCompressing, false);
    },
  );
  for (final viewport in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(800, 420),
  ]) {
    for (final bottom in [24.0, 48.0]) {
      testWidgets(
        'all root tabs stay above system controls at $viewport bottom $bottom',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = viewport;
          t.view.padding = FakeViewPadding(
            top: 24,
            bottom: bottom,
            left: viewport.width > 600 ? 30 : 0,
          );
          t.view.viewPadding = t.view.padding;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetPadding);
          addTearDown(t.view.resetViewPadding);
          await t.pumpWidget(
            const TomiApp(
              previewMode: true,
              textScaler: TextScaler.linear(2.0),
            ),
          );
          await t.pumpAndSettle();
          for (final key in [
            'nav-chats',
            'nav-rooms',
            'nav-games',
            'nav-profile',
            'nav-home',
          ]) {
            final target = find.byKey(Key(key));
            expect(
              t.getRect(target).bottom,
              lessThanOrEqualTo(viewport.height - bottom + .1),
            );
            expect(
              t.getRect(target).left,
              greaterThanOrEqualTo(viewport.width > 600 ? 30 : 0),
            );
            await t.tap(target);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: key);
          }
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'chat send stays accessible when keyboard and system insets change',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 640);
      t.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      t.view.viewPadding = t.view.padding;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      addTearDown(t.view.resetViewInsets);
      final store = TomiStore();
      addTearDown(store.dispose);
      await t.pumpWidget(TomiApp(store: store));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nav-chats')));
      await t.pumpAndSettle();
      await t.tap(find.text('علي').first);
      await t.pumpAndSettle();
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      t.view.padding = const FakeViewPadding(top: 24);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('message-input')),
        'تجربة الإرسال',
      );
      await t.pumpAndSettle();
      final send = find.byKey(const Key('send-message'));
      expect(t.getRect(send).bottom, lessThanOrEqualTo(380));
      await t.tap(send);
      await t.pumpAndSettle();
      expect(store.chats.first.messages.last.text, 'تجربة الإرسال');
      t.view.viewInsets = const FakeViewPadding();
      t.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      await t.pumpAndSettle();
      expect(t.getRect(send).bottom, lessThanOrEqualTo(592));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'video cover and final instructions remain scrollable above three-button navigation',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 640);
      t.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      t.view.viewPadding = t.view.padding;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = VideoFake();
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      await t.pumpWidget(
        MaterialApp(
          home: VideoEditorPage(
            file: XFile.fromData(Uint8List(100), name: 'movie.mp4'),
          ),
        ),
      );
      await t.pumpAndSettle();
      final cover = find.byKey(const Key('video-cover-frame'));
      await t.ensureVisible(cover);
      await t.pumpAndSettle();
      expect(t.getRect(cover).bottom, lessThanOrEqualTo(592));
      await t.tap(cover);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        t.getRect(find.text('استخدام المقطع')).top,
        greaterThanOrEqualTo(24),
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
