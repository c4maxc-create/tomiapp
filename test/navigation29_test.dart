import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/voice_rooms/room_screens.dart';
import 'package:tomi_app/src/messaging/chat_screens.dart';
import 'rooms_test.dart' as rooms;
import 'chat_test.dart' as chats;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'room minimize keeps its audio session alive across navigation; explicit exit releases it',
    (t) async {
      final (account, c, api, audio) = await rooms.setup();
      try {
        expect(await c.join(rooms.roomId), true);
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VoiceRoomPage(controller: c),
                    ),
                  ),
                  child: const Text('الغرفة'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('الغرفة'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('تصغير الغرفة'));
        await t.pumpAndSettle();
        expect(find.text('الغرفة'), findsOneWidget);
        expect(c.minimized, true);
        expect(c.active, isNotNull);
        expect(audio.disposed, false);
        expect(api.leaves, 0);
        c.expand();
        await t.tap(find.text('الغرفة'));
        await t.pumpAndSettle();
        expect(c.active, isNotNull);
        expect(audio.disposals, 0);
        await c.leave();
        await t.pumpAndSettle();
        expect(audio.disposed, true);
        expect(c.minimized, false);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );
  testWidgets(
    'wallpaper selection survives reopening the same account conversation',
    (t) async {
      final (account, api, thread) = await chats.setup();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PrivateChatPage(
              chats: account.chats,
              conversation: thread.conversation,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('chat-thread-menu')));
        await t.pumpAndSettle();
        await t.tap(find.text('خلفية المحادثة'));
        await t.pumpAndSettle();
        await t.tap(find.text('محيط'));
        await t.pumpAndSettle();
        expect(thread.wallpaper, 0);
        await t.ensureVisible(find.text('حفظ الخلفية'));
        await t.pumpAndSettle();
        await t.tap(find.text('حفظ الخلفية'));
        await t.pumpAndSettle();
        expect(thread.wallpaper, 2);
        final saved = await account.draftStore.read(
          thread.savedOwner!,
          thread.scope,
        );
        expect(saved!['wallpaper'], 2);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          MaterialApp(
            home: PrivateChatPage(
              chats: account.chats,
              conversation: thread.conversation,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(thread.wallpaper, 2);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );
  testWidgets(
    'recording and video delivery activity appear then expire rather than sticking online',
    (t) async {
      final (account, api, thread) = await chats.setup();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PrivateChatPage(
              chats: account.chats,
              conversation: thread.conversation,
            ),
          ),
        );
        await t.pumpAndSettle();
        thread.event({
          'type': 'chat.typing',
          'active': true,
          'activity': 'recording',
          'userId': 'peer',
        });
        await t.pump();
        expect(find.text('يسجل رسالة صوتية…'), findsOneWidget);
        thread.event({
          'type': 'chat.typing',
          'active': true,
          'activity': 'video',
          'userId': 'peer',
        });
        await t.pump();
        expect(find.text('يرسل فيديو…'), findsOneWidget);
        await t.pump(const Duration(seconds: 6));
        expect(find.text('يرسل فيديو…'), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );
}
