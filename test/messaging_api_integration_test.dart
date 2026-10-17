import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/chat_models.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/social/post_draft_controller.dart';
import 'account_fakes.dart';
import 'call_api_integration_test.dart' show LocalBridge;

class LoseSendAck extends LocalBridge {
  LoseSendAck(super.base);
  bool lose = true;
  int sends = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest source) async {
    final reply = await super.send(source);
    if (source.method == 'POST' && source.url.path.endsWith('/messages')) {
      sends++;
      if (lose) {
        lose = false;
        await reply.stream.drain<void>();
        throw http.ClientException('simulated lost committed ACK');
      }
    }
    return reply;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '0.10 Flutter disk restart reconciles real HTTP send and retains reply reaction pin search and post contracts',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/calls-client-api.mjs',
      ]);
      final stderr = child.stderr.transform(utf8.decoder).listen((_) {});
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode.timeout(const Duration(seconds: 10));
        await stderr.cancel();
      });
      final line = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 25));
      final d = jsonDecode(line) as Map<String, dynamic>,
          base = Uri.parse(d['base'] as String),
          users = d['users'] as List;
      final dir = await Directory.systemTemp.createTemp('tomi-http-drafts10-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileDraftStore(directory: () async => dir),
          bridge = LoseSendAck(base);
      Future<AccountController> account(int i, {http.Client? client}) async {
        final a = AccountController(
          api: AccountApi(
            'https://contract.tomi.test',
            client: client ?? LocalBridge(base),
          ),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          realtimeEnabled: false,
          draftStore: store,
        );
        await a.restore();
        return a;
      }

      final a = await account(0, client: bridge), b = await account(1);
      addTearDown(b.dispose);
      final c = await a.chats.open(b.user!.id), t = a.chats.thread(c);
      await t.restored;
      t.enqueue('نص ثابت بعد إعادة التشغيل', null);
      for (
        var i = 0;
        i < 500 &&
            (t.pending.isEmpty ||
                t.pending.single.busy ||
                !t.pending.single.commitAttempted);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await t.persist();
      expect(t.pending.length, 1);
      expect(t.pending.single.error, isNotNull);
      final nonce = t.pending.single.requestId;
      a.dispose();
      final restored = await account(0);
      addTearDown(restored.dispose);
      final rt = restored.chats.thread(c);
      await rt.restored;
      expect(rt.pending.single.requestId, nonce);
      await rt.retryPending(rt.pending.single, manual: true);
      expect(rt.pending, isEmpty);
      expect(bridge.sends, 1);
      expect(rt.messages.single.text, 'نص ثابت بعد إعادة التشغيل');
      final bt = b.chats.thread(
        DirectConversation(
          (await b.chatRequest('GET', '/v1/chats/${c.id}'))['conversation']
              as Map<String, dynamic>,
        ),
      );
      await bt.sync();
      bt.chooseReply(bt.messages.single);
      bt.enqueue('الرد', null);
      for (var i = 0; i < 500 && (bt.pending.isNotEmpty || bt.sending); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(bt.pending, isEmpty);
      expect(bt.messages.last.reply!['text'], 'نص ثابت بعد إعادة التشغيل');
      await rt.sync();
      final reply = rt.messages.last;
      await rt.changeTool(reply, 'reaction', {'emoji': '❤️'});
      await rt.changeTool(reply, 'pin', {'pinned': true});
      expect(rt.conversation.pinnedMessageId, reply.id);
      expect(rt.cache[reply.id]!.reactions.single['count'], 1);
      final search = await rt.search('الثابت');
      expect(search['messages'], isEmpty);
      final found = await rt.search('ثابت');
      expect((found['messages'] as List).length, 1);
      final post = PostDraftController(restored);
      addTearDown(post.dispose);
      await post.restored;
      post.editText('منشور من عقد HTTP');
      expect((await post.publish())!.text, 'منشور من عقد HTTP');
      expect(await store.read(restored.draftOwnerId!, 'post'), isNull);
      await rt.deleteMessage(rt.messages.first);
      await bt.sync(reconcile: true);
      expect(bt.messages.last.reply!['deleted'], true);
    },
    skip: Platform.environment['TOMI_MESSAGING_INTEGRATION'] != '1',
  );
}
