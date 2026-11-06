import 'package:flutter/material.dart';
import '../messaging/chat_controller.dart';
import '../social/social_models.dart';
import 'game_models.dart';

class ChatGameInvite extends StatefulWidget {
  const ChatGameInvite({super.key, required this.thread});
  final ChatThreadController thread;
  @override
  State<ChatGameInvite> createState() => _ChatGameInviteState();
}

class _ChatGameInviteState extends State<ChatGameInvite> {
  String kind = 'uno';
  bool busy = false;
  String? error;
  Future<void> invite() async {
    if (busy || !widget.thread.current) return;
    setState(() => busy = true);
    final thread = widget.thread, accounts = thread.chats.accounts;
    final owner = accounts.draftOwnerId!, session = accounts.sessionRevision;
    final key = 'game-invite-${thread.conversation.id}';
    bool valid() => thread.current && accounts.sessionRevision == session;
    try {
      var saved = await accounts.draftStore.read(owner, key);
      saved ??= {
        'requestId': newRequestId(),
        'messageRequestId': newRequestId(),
        'kind': kind,
        'mode': 'friends',
      };
      if (!valid()) return;
      if (!await accounts.draftStore.write(owner, key, saved, valid: valid))
        return;
      final d = await accounts.chatRequest(
        'POST',
        '/v1/games/matches',
        body: {
          'requestId': saved['requestId'],
          'kind': saved['kind'],
          'mode': 'friends',
        },
      );
      if (!valid()) return;
      final match = d['match'] as Map;
      if (!thread.conversation.isGroup)
        await accounts.chatRequest(
          'POST',
          '/v1/me/invitations',
          body: {
            'requestId': saved['messageRequestId'],
            'recipientId': thread.conversation.peer.id,
            'kind': 'game',
            'targetId': match['id'],
          },
        );
      await thread.restored;
      thread.enqueue(
        'دعوة للعب ${gameName(saved['kind'] as String)} • كود الغرفة: ${match['code']}\nاضغط «انضم للعبة» داخل الرسالة.',
        null,
        requestId: saved['messageRequestId'] as String,
      );
      if (!await thread.persist()) throw StateError('draft');
      await accounts.draftStore.write(owner, key, null, valid: valid);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'تعذّر إرسال الدعوة؛ أعد المحاولة لاستعادة نفس الغرفة. إذا عندك جولة مفتوحة، أكملها أو غادرها أولًا.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ادعُه للعبة',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Text('تُنشأ طاولة خاصة ويُرسل كودها في هذه المحادثة.'),
          DropdownButtonFormField<String>(
            initialValue: kind,
            isExpanded: true,
            items: [
              for (final k in ['uno', 'snakes', 'jackaroo', 'camel'])
                DropdownMenuItem(value: k, child: Text(gameName(k))),
            ],
            onChanged: busy ? null : (v) => setState(() => kind = v!),
          ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
          FilledButton(
            onPressed: busy ? null : invite,
            child: const Text('إنشاء الغرفة وإرسال الدعوة'),
          ),
        ],
      ),
    ),
  );
}
