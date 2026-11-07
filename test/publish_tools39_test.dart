import 'package:tomi_app/src/messaging/video_preparation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:tomi_app/src/messaging/direct_mp4.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'package:tomi_app/src/social/social_screens.dart';
import 'package:tomi_app/src/social/story_screens.dart';
import 'package:tomi_app/src/voice_rooms/room_tools_sheet.dart';
import 'chat_test.dart' as chats;
import 'experience33_test.dart' show VideoFake;

class ShortVideo extends VideoFake {
  @override
  Stream<VideoEvent> videoEventsFor(int id) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 1),
      size: const Size(320, 180),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only compatible MP4 headers take the original-file path', () async {
    final source = XFile('server/test/fixtures/video10.mp4');
    expect(await canSendOriginalMp4(source), true);
    final dir = await Directory.systemTemp.createTemp('tomi39-');
    try {
      final bytes = await File(source.path).readAsBytes();
      for (final pair in [('avc1', 'hvc1'), ('mp4a', 'ac-3')]) {
        final changed = Uint8List.fromList(bytes);
        for (var i = 0; i <= changed.length - 4; i++) {
          if (String.fromCharCodes(changed.sublist(i, i + 4)) == pair.$1)
            changed.setRange(i, i + 4, pair.$2.codeUnits);
        }
        final path = '${dir.path}/bad.mp4';
        await File(path).writeAsBytes(changed);
        expect(await canSendOriginalMp4(XFile(path)), false);
      }
      final path = '${dir.path}/short.mp4';
      await File(path).writeAsBytes(bytes.sublist(0, 30));
      expect(await canSendOriginalMp4(XFile(path)), false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  for (final kind in ['post', 'story', 'chat'])
    testWidgets(
      '$kind attaches a selected video without a trim or cover-selection route',
      (t) async {
        VideoPreparation.tail = Future.value();
        final (account, api, thread) = await chats.setup();
        addTearDown(account.dispose);
        final old = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = ShortVideo();
        addTearDown(() => VideoPlayerPlatform.instance = old);
        final bytes = (await t.runAsync(
          () => File('server/test/fixtures/video10.mp4').readAsBytes(),
        ))!;
        final file = XFile.fromData(
          bytes,
          name: 'selected.mp4',
          mimeType: 'video/mp4',
        );
        await t.pumpWidget(
          MaterialApp(
            home: kind == 'post'
                ? Scaffold(
                    body: SocialComposer(
                      accounts: account,
                      imageEnabled: true,
                      videoEnabled: true,
                      initialVideo: file,
                    ),
                  )
                : kind == 'story'
                ? StoryComposerPage(accounts: account, initialVideo: file)
                : PrivateChatPage(
                    chats: account.chats,
                    conversation: thread.conversation,
                    initialVideo: file,
                  ),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.pumpAndSettle();
        expect(find.text('تجهيز الفيديو'), findsNothing);
        expect(find.byKey(const Key('video-trim-range')), findsNothing);
        expect(find.byKey(const Key('video-cover-frame')), findsNothing);
        if (kind == 'chat')
          expect(thread.draftAttachment?.video, isNotNull);
        else if (kind == 'story')
          expect(find.text('فيديو جاهز للنشر'), findsOneWidget);
        else
          expect(find.textContaining('0:01'), findsWidgets);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  for (final viewport in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(800, 420),
  ]) {
    for (final scale in [1.0, 2.0])
      testWidgets(
        'all twelve room tools remain reachable at $viewport text $scale',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = viewport;
          t.view.padding = const FakeViewPadding(top: 24, bottom: 48);
          t.view.viewPadding = t.view.padding;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetPadding);
          addTearDown(t.view.resetViewPadding);
          final pressed = <String>[];
          const labels = [
            'دعوة صديق',
            'مشاركة الغرفة',
            'تصويت الغرفة',
            'مدار الحظ',
            'معلومات الغرفة',
            'الأعضاء',
            'مساهمو الغرفة',
            'الهدايا',
            'متجر الغرفة',
            'طلبات المايك',
            'إعدادات الغرفة',
            'خروج',
          ];
          await t.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) => RoomToolsSheet(
                        accent: Colors.teal,
                        actions: [
                          for (final label in labels)
                            (Icons.apps, label, () => pressed.add(label)),
                        ],
                      ),
                    ),
                    child: const Text('افتح'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('افتح'));
          await t.pumpAndSettle();
          for (final label in labels) {
            final target = find.byKey(ValueKey('room-tool-$label'));
            await t.scrollUntilVisible(
              target,
              100,
              scrollable: find.descendant(
                of: find.byKey(const Key('room-tools-grid')),
                matching: find.byType(Scrollable),
              ),
            );
            await t.ensureVisible(target);
            await t.pumpAndSettle();
            expect(
              t.getRect(target).bottom,
              lessThanOrEqualTo(viewport.height - 48 + .1),
            );
            await t.tap(target);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: label);
          }
          expect(pressed, labels);
          await t.pumpWidget(const SizedBox());
        },
      );
  }
}
