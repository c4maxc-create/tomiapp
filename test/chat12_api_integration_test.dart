import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/social_models.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

Future<void> sent(ChatThreadController t) async {
  for (var i = 0; i < 200 && t.pending.isNotEmpty; i++)
    await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(t.pending, isEmpty, reason: t.pending.map((p) => p.error).join(', '));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '1.2 real group chat, durable documents, stickers, read, quotes and member revocation agree with the API',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/chat12-client-api.mjs',
      ]);
      final errors = StringBuffer(),
          stderr = child.stderr.transform(utf8.decoder).listen(errors.write);
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode.timeout(const Duration(seconds: 10));
        await stderr.cancel();
      });
      final line = await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 25)),
          fixture = jsonDecode(line) as Map<String, dynamic>,
          base = Uri.parse(fixture['base'] as String),
          users = fixture['users'] as List;
      Future<AccountController> account(int i) async {
        final a = AccountController(
          api: AccountApi('https://chat.tomi.test', client: LocalBridge(base)),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          draftStore: MemoryDraftStore(),
          realtimeEnabled: false,
        );
        await a.restore();
        expect(a.user, isNotNull, reason: errors.toString());
        addTearDown(a.dispose);
        return a;
      }

      final a = await account(0),
          b = await account(1),
          c = await account(2),
          group = await a.chats.createGroup('الأصدقاء', [
            b.user!.id,
            c.user!.id,
          ], newRequestId());
      expect(group.isGroup, true);
      expect(group.memberCount, 3);
      final out = a.chats.thread(group);
      await out.restored;
      out.enqueue('', null, stickerId: 'hello');
      await sent(out);
      expect(out.messages.single.stickerId, 'hello');
      out.enqueue(
        'مستند للمجموعة',
        null,
        document: DocumentDraft(
          Uint8List.fromList(utf8.encode('%PDF-1.4\nTOMI test document')),
          'contract.pdf',
        ),
      );
      await sent(out);
      expect(out.messages.last.document!.name, 'contract.pdf');
      await b.chats.refresh();
      final view = b.chats.thread(
        b.chats.conversations.singleWhere((x) => x.id == group.id),
      );
      await view.sync();
      expect(view.messages.length, 2);
      expect(view.messages.last.document!.byteLength, greaterThan(0));
      expect(
        Uri.parse(
          view.messages.last.document!.url!,
        ).queryParameters['X-Amz-Expires'],
        '300',
      );
      view.visible = true;
      await view.markVisibleRead();
      await b.chats.refresh();
      expect(b.chats.totalUnread, 0);
      view.chooseReply(view.messages.first);
      view.enqueue('رد على الملصق', null);
      await sent(view);
      expect(view.messages.last.reply!['id'], out.messages.first.id);
      await view.changeTool(view.messages.last, 'reaction', {'emoji': '❤️'});
      expect(view.messages.last.reactions.single['count'], 1);
      await out.sync(reconcile: true);
      await out.deleteMessage(out.messages.first);
      await view.sync(reconcile: true);
      expect(view.messages.first.deleted, true);
      expect(view.messages.last.reply!['deleted'], true);
      final pushed = await b.chatRequest('GET', '/v1/chats/${group.id}');
      expect(
        DirectConversation.fromJson(
          pushed['conversation'] as Map<String, dynamic>,
        ).isGroup,
        true,
      );
      final direct = await a.chats.open(b.user!.id),
          dm = a.chats.thread(direct);
      await dm.restored;
      dm.enqueue('', null, stickerId: 'love');
      await sent(dm);
      expect(dm.messages.single.stickerId, 'love');
      dm.enqueue(
        '',
        null,
        document: DocumentDraft(
          Uint8List.fromList(utf8.encode('private note')),
          'note.txt',
        ),
      );
      await sent(dm);
      expect(dm.messages.last.document!.name, 'note.txt');
      await a.chatRequest(
        'DELETE',
        '/v1/groups/${group.id}/members/${b.user!.id}',
      );
      await b.chats.refresh();
      expect(b.chats.conversations.where((x) => x.id == group.id), isEmpty);
      expect(view.conversation.canSend, false);
      await expectLater(
        b.chatRequest('GET', '/v1/groups/${group.id}/messages'),
        throwsA(isA<AccountFailure>().having((e) => e.status, 'status', 404)),
      );
    },
    skip: Platform.environment['TOMI_CHAT_INTEGRATION'] != '1',
  );
}
