import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_search.dart';
import '../accounts/account_widgets.dart';
import '../social/social_models.dart';
import '../social/social_screens.dart';
import '../widgets.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'voice_note.dart';
import 'gallery_intent.dart';
import 'video_media.dart';

final chatRouteObserver = RouteObserver<ModalRoute<void>>();
Future<void> openPrivateChat(
  BuildContext context,
  AccountController accounts,
  String userId,
) async {
  final chats = accounts.chats;
  if (!chats.openingPeerIds.add(userId)) return;
  try {
    final conversation = await chats.open(userId);
    if (context.mounted)
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              PrivateChatPage(chats: chats, conversation: conversation),
        ),
      );
  } on AccountFailure catch (f) {
    if (context.mounted) showNote(context, f.message);
  } catch (_) {
    if (context.mounted) showNote(context, 'تعذّر فتح المحادثة.');
  } finally {
    chats.openingPeerIds.remove(userId);
  }
}

class PrivateChatsScreen extends StatelessWidget {
  const PrivateChatsScreen({super.key, required this.accounts});
  final AccountController accounts;
  @override
  Widget build(BuildContext context) {
    final chats = accounts.chats;
    return AnimatedBuilder(
      animation: chats,
      builder: (context, _) => RefreshIndicator(
        onRefresh: chats.refresh,
        child: ListView(
          padding: const EdgeInsets.all(18),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'المحادثات',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'المحظورون',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => BlockedUsersPage(chats: chats),
                    ),
                  ),
                  icon: const Icon(Icons.block),
                ),
                IconButton(
                  tooltip: 'محادثة جديدة',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AccountSearchPage(accounts: accounts),
                    ),
                  ),
                  icon: const Icon(Icons.edit_square),
                ),
              ],
            ),
            if (chats.error != null) Text(chats.error!),
            if (chats.loading && chats.conversations.isEmpty)
              const Center(child: CircularProgressIndicator()),
            if (!chats.loading && chats.conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ابحث عن حساب وابدأ أول محادثة 💜',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final c in chats.conversations)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TomiCard(
                  padding: const EdgeInsets.all(4),
                  child: ListTile(
                    leading: AccountAvatar(c.peer.avatarUser, size: 44),
                    title: Text(
                      c.peer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      c.lastMessage.isEmpty ? 'ابدأ رسالة' : c.lastMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: c.unreadCount > 0
                        ? Badge(label: Text('${c.unreadCount}'))
                        : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PrivateChatPage(chats: chats, conversation: c),
                      ),
                    ),
                  ),
                ),
              ),
            if (chats.nextCursor != null)
              TextButton(
                onPressed: chats.loading
                    ? null
                    : () => chats.refresh(more: true),
                child: const Text('محادثات أقدم'),
              ),
          ],
        ),
      ),
    );
  }
}

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key, required this.chats});
  final ChatController chats;
  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<dynamic>? users;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final d = await widget.chats.accounts.chatRequest(
        'GET',
        '/v1/chat/blocks',
      );
      if (mounted)
        setState(() {
          users = d['users'] as List;
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل المحظورين.');
    }
  }

  Future<void> unblock(String id) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final d = await widget.chats.accounts.chatRequest(
        'PUT',
        '/v1/chat/blocks/$id',
        body: {'blocked': false},
      );
      widget.chats.update(
        DirectConversation.fromJson(d['conversation'] as Map<String, dynamic>),
      );
      await load();
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المحظورون')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (error != null) Text(error!),
        if (users == null && error == null)
          const Center(child: CircularProgressIndicator()),
        if (users?.isEmpty == true) const Text('ما عندك مستخدمين محظورين.'),
        for (final u in users ?? [])
          ListTile(
            title: Text(u['displayName'] as String),
            subtitle: Text('@${u['username']}'),
            trailing: TextButton(
              onPressed: busy ? null : () => unblock(u['id'] as String),
              child: const Text('إلغاء الحظر'),
            ),
          ),
      ],
    ),
  );
}

class PrivateChatPage extends StatefulWidget {
  const PrivateChatPage({
    super.key,
    required this.chats,
    required this.conversation,
    this.initialImage,
    this.initialVideo,
  });
  final ChatController chats;
  final DirectConversation conversation;
  final XFile? initialImage, initialVideo;
  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> with RouteAware {
  late final thread = widget.chats.thread(widget.conversation);
  final input = TextEditingController(), scroll = ScrollController();
  final playback = VoicePlayback();
  ModalRoute<void>? route;
  ImageDraft? image;
  VideoDraft? video;
  bool picking = false, mutating = false, capturing = false;
  int renderedSequence = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(scrolled);
    unawaited(restoreDraft());
    unawaited(thread.sync(reconcile: true));
    if (widget.initialVideo != null) unawaited(loadVideo(widget.initialVideo!));
    if (widget.initialImage != null) unawaited(loadImage(widget.initialImage!));
  }

  Future<void> restoreDraft() async {
    await thread.restored;
    if (!mounted || !thread.current) return;
    if (input.text.isEmpty) input.text = thread.draft;
    if (image == null &&
        video == null &&
        widget.initialImage == null &&
        widget.initialVideo == null)
      setState(() {
        image = thread.draftAttachment?.image;
        video = thread.draftAttachment?.video;
      });
  }

  Future<void> loadVideo(XFile file) async {
    try {
      final v = await readPickedVideo(file);
      if (!mounted || !thread.current) return;
      await thread.setAttachment(v);
      if (mounted)
        setState(() {
          video = v;
          image = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح أو حفظ الفيديو.');
    }
  }

  Future<void> pickVideo() async {
    if (picking || capturing || thread.sending) return;
    setState(() => picking = true);
    try {
      await GalleryIntent.remember(
        widget.chats.accounts.api.baseUrl,
        widget.chats.accounts.user!.id,
        conversationId: thread.conversation.id,
        purpose: 'chat-video',
      );
      final f = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
      await GalleryIntent.clear();
      if (f != null && mounted && thread.current) await loadVideo(f);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح معرض الفيديو.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> clearAttachment() async {
    try {
      await thread.setAttachment(null);
      if (mounted)
        setState(() {
          image = null;
          video = null;
        });
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حفظ إزالة المرفق.');
    }
  }

  Future<void> tools(ChatMessage m, String action) async {
    if (action == 'delete') {
      await delete(m);
      return;
    }
    if (action == 'reply') {
      thread.chooseReply(m);
      return;
    }
    if (mutating) return;
    String? emoji;
    if (action == 'reaction') {
      emoji = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Wrap(
            children: [
              for (final value in ['❤️', '😂', '👍', '😮', '😢', '🔥'])
                TextButton(
                  onPressed: () => Navigator.pop(c, value),
                  child: Text(value, style: const TextStyle(fontSize: 28)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(c, ''),
                child: const Text('إزالة تفاعلي'),
              ),
            ],
          ),
        ),
      );
      if (emoji == null) return;
    }
    if (!mounted) return;
    setState(() => mutating = true);
    try {
      await thread.changeTool(
        m,
        action == 'reaction' ? 'reaction' : 'pin',
        action == 'reaction'
            ? {'emoji': emoji!.isEmpty ? null : emoji}
            : {'pinned': thread.conversation.pinnedMessageId != m.id},
      );
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر تحديث الرسالة.');
    } finally {
      if (mounted) setState(() => mutating = false);
    }
  }

  Future<void> showMessage(String id) async {
    await thread.refreshMessage(id);
    if (!mounted) return;
    final message = thread.cache[id];
    if (message == null) {
      showNote(context, 'الرسالة غير متاحة.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: bubble(message),
        ),
      ),
    );
  }

  Future<void> search() async {
    final m = await Navigator.push<ChatMessage>(
      context,
      MaterialPageRoute(builder: (_) => ChatSearchPage(thread: thread)),
    );
    if (m != null && mounted) await showMessage(m.id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of<void>(context);
    if (next != route) {
      if (route != null) chatRouteObserver.unsubscribe(this);
      route = next;
      if (next != null) chatRouteObserver.subscribe(this, next);
    }
    thread.visible = route?.isCurrent ?? true;
  }

  @override
  void didPush() {
    thread.visible = true;
  }

  @override
  void didPopNext() {
    thread.visible = true;
    unawaited(thread.sync(reconcile: true));
  }

  @override
  void didPushNext() {
    unawaited(playback.stop());
    thread.visible = false;
    thread.stopTyping();
  }

  @override
  void didPop() {
    unawaited(playback.stop());
    thread.visible = false;
    thread.stopTyping();
    unawaited(thread.persist().catchError((Object _) => false));
  }

  void scrolled() {
    thread.atLatest = scroll.hasClients && scroll.offset < 70;
    if (thread.atLatest) unawaited(thread.markVisibleRead());
  }

  Future<void> loadImage(XFile f) async {
    try {
      final draft = await readPickedImage(f);
      if (!mounted || !thread.current) return;
      await thread.setAttachment(draft);
      if (mounted)
        setState(() {
          image = draft;
          video = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حفظ الصورة.');
    }
  }

  Future<void> pick() async {
    if (picking || capturing || thread.sending) return;
    setState(() => picking = true);
    try {
      await GalleryIntent.remember(
        widget.chats.accounts.api.baseUrl,
        widget.chats.accounts.user!.id,
        conversationId: thread.conversation.id,
      );
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await GalleryIntent.clear();
      if (f != null && mounted && thread.current) await loadImage(f);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح المعرض.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> recordVoice() async {
    if (capturing ||
        picking ||
        thread.sending ||
        image != null ||
        video != null)
      return;
    setState(() => capturing = true);
    await playback.stop();
    if (!mounted) return;
    final draft = await showModalBottomSheet<AudioDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const VoiceRecorderSheet(),
    );
    if (!mounted) return;
    setState(() => capturing = false);
    if (draft == null) return;
    try {
      thread.enqueue(input.text, null, audio: draft);
      input.clear();
      thread.atLatest = true;
      if (scroll.hasClients) scroll.jumpTo(0);
    } on AccountFailure catch (f) {
      showNote(context, f.message);
    }
  }

  void send() {
    if (picking || capturing || thread.sending) return;
    try {
      thread.enqueue(input.text, image, video: video);
      if (input.text.trim().isEmpty && image == null && video == null) return;
      input.clear();
      setState(() {
        image = null;
        video = null;
      });
      thread.atLatest = true;
      if (scroll.hasClients) scroll.jumpTo(0);
    } on AccountFailure catch (f) {
      showNote(context, f.message);
    }
  }

  Future<void> toggleBlock() async {
    if (mutating) return;
    final blocked = thread.conversation.blockedByMe;
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(blocked ? 'إلغاء الحظر؟' : 'حظر المستخدم؟'),
        content: const Text(
          'الحظر يوقف المراسلة بالاتجاهين ويبقي سجل الرسائل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(blocked ? 'إلغاء الحظر' : 'حظر'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => mutating = true);
    try {
      await thread.setBlocked(!blocked);
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر تغيير الحظر.');
    } finally {
      if (mounted) setState(() => mutating = false);
    }
  }

  Future<void> delete(ChatMessage m) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الرسالة؟'),
        content: const Text('تُحذف من المحادثة عند الطرفين.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await thread.deleteMessage(m);
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حذف الرسالة.');
    }
  }

  Widget bubble(ChatMessage m) => Align(
    alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: m.isMine ? const Color(0xFF3C305C) : TomiColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.deleted)
            const Text(
              'تم حذف الرسالة',
              style: TextStyle(color: TomiColors.muted),
            )
          else ...[
            if (m.reply != null)
              InkWell(
                onTap: () => showMessage(m.reply!['id'] as String),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.reply!['author'] as String? ?? 'رد',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        m.reply!['text'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            if (m.video != null)
              VideoTile(
                video: m.video!,
                source: () async {
                  await thread.refreshMessage(m.id);
                  final url = thread.cache[m.id]?.video?.url;
                  return url == null ? null : Uri.parse(url);
                },
              ),
            if (m.image?.url != null)
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatImagePage(thread: thread, messageId: m.id),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    m.image!.url!,
                    height: 170,
                    width: 260,
                    fit: BoxFit.cover,
                    cacheWidth: 600,
                    errorBuilder: (_, _, _) => TextButton.icon(
                      onPressed: () => thread.refreshMessage(m.id),
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث الصورة'),
                    ),
                  ),
                ),
              ),
            if (m.audio != null)
              VoicePlayer(
                playback: playback,
                id: m.id,
                durationMs: m.audio!.durationMs,
                source: () async {
                  await thread.refreshMessage(m.id);
                  final url = thread.cache[m.id]?.audio?.url;
                  return url == null ? null : Uri.parse(url);
                },
              ),
            if (m.text.isNotEmpty) Text(m.text),
          ],
          if (!m.deleted && m.reactions.isNotEmpty)
            Wrap(
              spacing: 5,
              children: [
                for (final reaction in m.reactions)
                  ActionChip(
                    label: Text('${reaction['emoji']} ${reaction['count']}'),
                    backgroundColor: reaction['mine'] == true
                        ? TomiColors.raised
                        : null,
                    onPressed: mutating
                        ? null
                        : () => thread
                              .changeTool(m, 'reaction', {
                                'emoji': reaction['mine'] == true
                                    ? null
                                    : reaction['emoji'],
                              })
                              .catchError((Object _) {
                                if (mounted)
                                  showNote(context, 'تعذّر تغيير التفاعل.');
                              }),
                  ),
              ],
            ),
          if (!m.deleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    m.isMine
                        ? (m.sequence <= thread.conversation.peerReadSequence
                              ? 'مقروءة'
                              : 'تم الإرسال')
                        : '',
                    style: const TextStyle(
                      fontSize: 10,
                      color: TomiColors.muted,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('message-options:${m.id}'),
                  tooltip: 'خيارات الرسالة',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  enabled: !mutating && thread.conversation.canSend,
                  onSelected: (action) => tools(m, action),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'reply', child: Text('رد')),
                    const PopupMenuItem(
                      value: 'reaction',
                      child: Text('تفاعل'),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(
                        thread.conversation.pinnedMessageId == m.id
                            ? 'إلغاء التثبيت'
                            : 'تثبيت الرسالة',
                      ),
                    ),
                    if (m.isMine)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف الرسالة'),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget pendingBubble(PendingChatMessage p) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: TomiColors.raised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.hasAudio) const Text('🎤 تسجيل صوتي'),
          if (p.hasVideo) const Text('🎬 فيديو'),
          if (p.hasImage) const Text('📷 صورة'),
          if (p.text.isNotEmpty) Text(p.text),
          Text(
            p.busy ? 'جارٍ الإرسال…' : p.error ?? 'قيد الانتظار',
            style: const TextStyle(fontSize: 11, color: TomiColors.muted),
          ),
          if (!p.busy)
            Wrap(
              children: [
                TextButton(
                  onPressed: thread.sending || !thread.conversation.canSend
                      ? null
                      : () => thread.retryPending(p, manual: true),
                  child: const Text('إعادة المحاولة'),
                ),
                TextButton(
                  onPressed: () => thread.discard(p),
                  child: const Text('إلغاء إعادة المحاولة'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    playback.dispose();
    thread.visible = false;
    thread.stopTyping();
    chatRouteObserver.unsubscribe(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([thread, widget.chats]),
    builder: (context, _) {
      final c = thread.conversation,
          h =
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              kToolbarHeight -
              MediaQuery.paddingOf(context).vertical;
      final previousExtent = scroll.hasClients
          ? scroll.position.maxScrollExtent
          : 0.0;
      final previousOffset = scroll.hasClients ? scroll.offset : 0.0;
      final preserveAnchor =
          !thread.atLatest &&
          !thread.historyWindow &&
          thread.highestSequence > renderedSequence;
      renderedSequence = thread.highestSequence;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && preserveAnchor && scroll.hasClients) {
          final growth = scroll.position.maxScrollExtent - previousExtent;
          if (growth > 0)
            scroll.jumpTo(
              (previousOffset + growth).clamp(
                0.0,
                scroll.position.maxScrollExtent,
              ),
            );
        }
        if (mounted && (route?.isCurrent ?? true)) {
          thread.visible = true;
          unawaited(thread.markVisibleRead());
        }
      });
      final p = thread.pending.reversed.toList(),
          m = thread.messages.reversed.toList(),
          count = p.length + m.length + (thread.nextBefore == null ? 0 : 1);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            c.peer.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const Key('chat-search'),
              tooltip: 'بحث في المحادثة',
              onPressed: search,
              icon: const Icon(Icons.search),
            ),
            AnimatedBuilder(
              animation: widget.chats.accounts.calls,
              builder: (context, _) => PopupMenuButton<bool>(
                key: const Key('chat-call-menu'),
                tooltip: 'اتصال',
                icon: const Icon(Icons.call_outlined),
                enabled: c.canSend && !widget.chats.accounts.calls.busy,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: false,
                    child: Text('مكالمة صوتية'),
                  ),
                  const PopupMenuItem(value: true, child: Text('مكالمة فيديو')),
                ],
                onSelected: (video) async {
                  await playback.stop();
                  await widget.chats.accounts.calls.start(c.id, video: video);
                  if (mounted && widget.chats.accounts.calls.error != null)
                    showNote(context, widget.chats.accounts.calls.error!);
                },
              ),
            ),
            if (thread.historyWindow)
              IconButton(
                key: const Key('chat-show-latest'),
                tooltip: 'الرجوع لأحدث الرسائل',
                onPressed: () async {
                  await thread.showLatest();
                  if (mounted && scroll.hasClients) scroll.jumpTo(0);
                },
                icon: const Icon(Icons.keyboard_double_arrow_down),
              ),
            PopupMenuButton<String>(
              enabled: !mutating,
              onSelected: (action) => action == 'pinned'
                  ? showMessage(c.pinnedMessageId!)
                  : toggleBlock(),
              itemBuilder: (_) => [
                if (c.pinnedMessageId != null)
                  const PopupMenuItem(
                    value: 'pinned',
                    child: Text('الرسالة المثبّتة'),
                  ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(c.blockedByMe ? 'إلغاء الحظر' : 'حظر المستخدم'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (c.pinnedMessageId != null && h >= 400)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.push_pin_outlined),
                  title: const Text('رسالة مثبّتة'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => showMessage(c.pinnedMessageId!),
                ),
              if (!widget.chats.connected && h >= 280)
                const Padding(
                  padding: EdgeInsets.all(5),
                  child: Text(
                    'نعيد الاتصال المباشر… تگدر تسحب لتحديث الرسائل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: TomiColors.muted),
                  ),
                ),
              if (thread.error != null && h >= 240)
                TextButton(
                  onPressed: () => thread.sync(reconcile: true),
                  child: Text(thread.error!),
                ),
              Expanded(
                child: thread.loading && m.isEmpty && p.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: () => thread.sync(reconcile: true),
                        child: ListView.builder(
                          controller: scroll,
                          reverse: true,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(14),
                          itemCount: count == 0 ? 1 : count,
                          itemBuilder: (_, i) {
                            if (count == 0)
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'ابدأ أول رسالة 💜',
                                  textAlign: TextAlign.center,
                                ),
                              );
                            if (i < p.length)
                              return KeyedSubtree(
                                key: ValueKey('pending:${p[i].requestId}'),
                                child: pendingBubble(p[i]),
                              );
                            if (i < p.length + m.length)
                              return KeyedSubtree(
                                key: ValueKey('message:${m[i - p.length].id}'),
                                child: bubble(m[i - p.length]),
                              );
                            return TextButton(
                              onPressed: thread.loadingOlder
                                  ? null
                                  : thread.loadOlder,
                              child: Text(
                                thread.loadingOlder
                                    ? 'جارٍ التحميل…'
                                    : 'رسائل أقدم',
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (thread.peerTyping && h >= 220)
                const Padding(
                  padding: EdgeInsets.all(5),
                  child: Text(
                    'يكتب الآن…',
                    style: TextStyle(color: TomiColors.accent, fontSize: 12),
                  ),
                ),
              if (!c.canSend)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    c.blockedByMe
                        ? 'المستخدم محظور. تگدر تلغي الحظر من القائمة.'
                        : 'المراسلة غير متاحة مع هذا المستخدم.',
                  ),
                )
              else ...[
                if (thread.replyToId != null && h >= 300)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.reply),
                    title: Text(
                      thread.cache[thread.replyToId]?.text ?? 'رد على رسالة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'إلغاء الرد',
                      onPressed: () => thread.chooseReply(null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                if (video != null && h >= 300)
                  ListTile(
                    leading: const Icon(Icons.videocam_outlined),
                    title: Text('فيديو مرفق • ${voiceTime(video!.durationMs)}'),
                    trailing: IconButton(
                      tooltip: 'إزالة الفيديو',
                      onPressed: clearAttachment,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                if (image != null && h >= 300)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Image.memory(
                          image!.bytes,
                          height: h < 450 ? 32 : 64,
                          width: h < 450 ? 32 : 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.image),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('صورة مرفقة')),
                        IconButton(
                          tooltip: 'إزالة الصورة',
                          onPressed: clearAttachment,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                if (h < 300 &&
                    (thread.replyToId != null ||
                        image != null ||
                        video != null))
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        if (thread.replyToId != null) ...[
                          const Icon(Icons.reply, size: 16),
                          const Expanded(
                            child: Text(
                              'رد على رسالة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          IconButton(
                            tooltip: 'إلغاء الرد',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: () => thread.chooseReply(null),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                        if (image != null || video != null) ...[
                          Expanded(
                            child: Text(
                              video != null ? 'فيديو مرفق' : 'صورة مرفقة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          IconButton(
                            tooltip: 'إزالة المرفق',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: clearAttachment,
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const Key('private-chat-image'),
                        tooltip: 'إرفاق صورة',
                        onPressed:
                            picking || thread.sending || !c.imageUploadEnabled
                            ? null
                            : pick,
                        icon: Badge(
                          isLabelVisible: image != null,
                          child: const Icon(Icons.add_photo_alternate_outlined),
                        ),
                      ),
                      if (c.videoUploadEnabled)
                        IconButton(
                          key: const Key('private-chat-video'),
                          tooltip: 'إرفاق فيديو',
                          onPressed: picking || capturing || thread.sending
                              ? null
                              : pickVideo,
                          icon: const Icon(Icons.video_library_outlined),
                        ),
                      IconButton(
                        key: const Key('private-chat-voice'),
                        tooltip: 'تسجيل رسالة صوتية',
                        onPressed:
                            picking ||
                                capturing ||
                                thread.sending ||
                                image != null ||
                                video != null ||
                                !c.audioUploadEnabled
                            ? null
                            : recordVoice,
                        icon: const Icon(Icons.mic_none),
                      ),
                      Expanded(
                        child: TextField(
                          key: const Key('private-chat-input'),
                          controller: input,
                          enabled: !thread.restoring,
                          minLines: 1,
                          maxLines: h < 180
                              ? 1
                              : h < 450
                              ? 2
                              : 4,
                          maxLength: 2000,
                          onChanged: (value) {
                            thread.setDraft(value);
                            thread.noteTyping();
                          },
                          textInputAction: h < 180
                              ? TextInputAction.send
                              : TextInputAction.newline,
                          onSubmitted: h < 180 ? (_) => send() : null,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالتك…',
                            counterText: '',
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(
                        key: const Key('private-chat-send'),
                        tooltip: 'إرسال الرسالة',
                        onPressed: picking || thread.sending || thread.restoring
                            ? null
                            : send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class ChatSearchPage extends StatefulWidget {
  const ChatSearchPage({super.key, required this.thread});
  final ChatThreadController thread;
  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  final input = TextEditingController();
  List<ChatMessage> rows = [];
  int? before;
  int epoch = 0;
  bool loading = false;
  String? error;
  Future<void> search({bool more = false}) async {
    if (more && (loading || before == null)) return;
    final q = input.text.trim(), e = ++epoch;
    if (q.runes.length < 2) {
      setState(() => error = 'اكتب حرفين على الأقل.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        rows = [];
        before = null;
      }
    });
    try {
      final d = await widget.thread.search(q, before: more ? before : null);
      if (!mounted || e != epoch) return;
      final found = (d['messages'] as List).map(
        (x) => ChatMessage.fromJson(x as Map<String, dynamic>),
      );
      setState(() {
        rows = [if (more) ...rows, ...found];
        before = (d['nextBefore'] as num?)?.toInt();
      });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر البحث.');
    } finally {
      if (mounted && e == epoch) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('بحث في المحادثة')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('chat-search-input'),
              controller: input,
              maxLength: 80,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: 'اكتب كلمة من الرسالة',
                suffixIcon: IconButton(
                  tooltip: 'بحث',
                  onPressed: () => search(),
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final m in rows)
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      m.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      m.isMine
                          ? 'أنت'
                          : widget.thread.conversation.peer.displayName,
                    ),
                    onTap: () => Navigator.pop(c, m),
                  ),
                if (rows.isEmpty && !loading && error == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'ابحث بالنص داخل هذه المحادثة.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (before != null)
                  TextButton(
                    onPressed: loading ? null : () => search(more: true),
                    child: const Text('نتائج أقدم'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ChatImagePage extends StatelessWidget {
  const ChatImagePage({
    super.key,
    required this.thread,
    required this.messageId,
  });
  final ChatThreadController thread;
  final String messageId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: thread,
    builder: (context, _) {
      final m = thread.cache[messageId];
      return Scaffold(
        appBar: AppBar(
          title: const Text('الصورة'),
          actions: [
            IconButton(
              onPressed: () => thread.refreshMessage(messageId),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: m?.image?.url == null
              ? const Text('الصورة غير متاحة أو حُذفت.')
              : InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Image.network(
                    m!.image!.url!,
                    errorBuilder: (_, _, _) => TextButton(
                      onPressed: () => thread.refreshMessage(messageId),
                      child: const Text('تحديث الصورة'),
                    ),
                  ),
                ),
        ),
      );
    },
  );
}
