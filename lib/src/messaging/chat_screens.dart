import '../security/secure_chat_page.dart';
import '../preferences/network_media_image.dart';
import '../gaming/chat_game_invite.dart';
import '../gaming/csharp_games_page.dart';
import '../social/post_share_screens.dart';
import '../identity/charisma_badge.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:url_launcher/url_launcher.dart';

import 'chat_widgets.dart';
import 'chat_groups.dart';

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

class PrivateChatsScreen extends StatefulWidget {
  const PrivateChatsScreen({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

class _PrivateChatsScreenState extends State<PrivateChatsScreen> {
  final input = TextEditingController();
  String filter = 'all';
  ChatController get chats => widget.accounts.chats;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> action(String value) async {
    if (value == 'requests') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PostShareRequestsPage(accounts: widget.accounts),
        ),
      );
      if (mounted) await chats.refresh();
    } else if (value == 'group') {
      final c = await Navigator.push<DirectConversation>(
        context,
        MaterialPageRoute(builder: (_) => GroupCreatePage(chats: chats)),
      );
      if (c != null && mounted) await open(c);
    } else
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => value == 'blocked'
              ? BlockedUsersPage(chats: chats)
              : ChatSurface(
                  child: AccountSearchPage(accounts: widget.accounts),
                ),
        ),
      );
  }

  Future<void> open(DirectConversation c) async {
    if (c.markedUnread) await organise(c, unread: false);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatPage(chats: chats, conversation: c),
      ),
    );
  }

  Future<void> organise(
    DirectConversation c, {
    bool? pinned,
    bool? archived,
    bool? unread,
  }) async {
    try {
      await widget.accounts.chatRequest(
        'PUT',
        '/v1/${c.isGroup ? 'groups' : 'chats'}/${c.id}/organisation',
        body: {
          'pinned': pinned ?? c.personalPinned,
          'archived': archived ?? c.archived,
          'markedUnread': unread ?? c.markedUnread,
        },
      );
      await chats.refresh();
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر تنظيم المحادثة.');
    }
  }

  Future<void> organiseMenu(DirectConversation c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (d) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                c.personalPinned ? 'إلغاء تثبيت المحادثة' : 'تثبيت المحادثة',
              ),
              leading: const Icon(Icons.push_pin_outlined),
              onTap: () => Navigator.pop(d, 'pin'),
            ),
            ListTile(
              title: Text(c.archived ? 'إخراج من الأرشيف' : 'أرشفة المحادثة'),
              leading: const Icon(Icons.archive_outlined),
              onTap: () => Navigator.pop(d, 'archive'),
            ),
            ListTile(
              title: Text(
                c.markedUnread ? 'إلغاء علامة غير مقروء' : 'تحديد غير مقروء',
              ),
              leading: const Icon(Icons.mark_chat_unread_outlined),
              onTap: () => Navigator.pop(d, 'unread'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await organise(
      c,
      pinned: action == 'pin' ? !c.personalPinned : null,
      archived: action == 'archive' ? !c.archived : null,
      unread: action == 'unread' ? !c.markedUnread : null,
    );
  }

  PendingChatMessage? pending(DirectConversation c) =>
      chats.threads[c.id]?.pending.lastOrNull;
  DateTime activity(DirectConversation c) =>
      pending(c)?.createdAt ?? DateTime.tryParse(c.updatedAt) ?? DateTime(2000);
  String preview(DirectConversation c) {
    final t = chats.threads[c.id], p = pending(c);
    if (t?.peerTyping == true) return t!.activityLabel;
    if (p != null)
      return p.text.isNotEmpty
          ? p.text
          : p.stickerId != null
          ? 'ملصق'
          : p.hasAudio
          ? '🎤 رسالة صوتية'
          : p.hasVideo
          ? '🎬 فيديو'
          : p.hasDocument
          ? '📎 ${p.document?.name ?? p.savedMedia?['fileName'] ?? 'مستند'}'
          : '📷 صورة';
    if (t?.draft.isNotEmpty == true) return 'مسودة: ${t!.draft}';
    return c.lastMessage.isEmpty ? 'ابدأ المحادثة' : c.lastMessage;
  }

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return ChatSurface(
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: chats,
          builder: (context, _) {
            final q = input.text.toLowerCase().trim(),
                rows =
                    chats.conversations
                        .where(
                          (c) =>
                              (filter != 'groups' || c.isGroup) &&
                              (filter == 'archived'
                                  ? c.archived
                                  : !c.archived) &&
                              (filter != 'unread' ||
                                  c.unreadCount > 0 ||
                                  c.markedUnread) &&
                              (q.isEmpty ||
                                  c.peer.displayName.toLowerCase().contains(
                                    q,
                                  ) ||
                                  c.peer.username.toLowerCase().contains(q) ||
                                  preview(c).toLowerCase().contains(q)),
                        )
                        .toList()
                      ..sort(
                        (a, b) => a.personalPinned != b.personalPinned
                            ? (a.personalPinned ? -1 : 1)
                            : activity(b).compareTo(activity(a)),
                      );
            return Material(
              color: p.surface,
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: chats.refresh,
                    child: CustomScrollView(
                      key: const PageStorageKey('chat-inbox-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'TOMI',
                                            textDirection: TextDirection.ltr,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.5,
                                              color: p.accent,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          const Text(
                                            'المحادثات',
                                            style: TextStyle(
                                              fontSize: 29,
                                              fontWeight: FontWeight.w800,
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      key: const Key('chat-inbox-menu'),
                                      tooltip: 'قائمة المحادثات',
                                      icon: Badge(
                                        isLabelVisible:
                                            chats.shareRequestsCount > 0,
                                        label: Text(
                                          '${chats.shareRequestsCount}',
                                        ),
                                        child: const Icon(Icons.menu_rounded),
                                      ),
                                      onSelected: action,
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'group',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.group_add_outlined,
                                            ),
                                            title: Text('إنشاء مجموعة'),
                                            subtitle: Text('اختر عدة أشخاص'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'search',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.person_search_outlined,
                                            ),
                                            title: Text('البحث عن شخص'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'requests',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                              Icons.mark_email_unread_outlined,
                                            ),
                                            title: Text(
                                              'طلبات الغرباء (${chats.shareRequestsCount})',
                                            ),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'blocked',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.block_rounded),
                                            title: Text('المحظورون'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                TextField(
                                  key: const Key('chat-inbox-search'),
                                  controller: input,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'ابحث في محادثاتك',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    suffixIcon: input.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'مسح البحث',
                                            onPressed: () {
                                              input.clear();
                                              setState(() {});
                                            },
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 20,
                                            ),
                                          ),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 5,
                                  children: [
                                    for (final item in [
                                      ('all', 'الكل'),
                                      ('groups', 'المجموعات'),
                                      ('unread', 'غير مقروءة'),
                                      ('archived', 'الأرشيف'),
                                    ])
                                      ChoiceChip(
                                        key: ValueKey('chat-filter-${item.$1}'),
                                        label: Text(item.$2),
                                        selected: filter == item.$1,
                                        onSelected: (_) =>
                                            setState(() => filter = item.$1),
                                        showCheckmark: false,
                                        selectedColor: p.accent.withValues(
                                          alpha: .15,
                                        ),
                                        backgroundColor: p.raised,
                                        side: BorderSide.none,
                                        labelStyle: TextStyle(
                                          color: filter == item.$1
                                              ? p.accent
                                              : p.muted,
                                          fontWeight: filter == item.$1
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (chats.error != null)
                                  TextButton.icon(
                                    onPressed: chats.refresh,
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      chats.error!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (chats.realtimeEnabled && !chats.connected)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.cloud_sync_outlined,
                                          size: 13,
                                          color: p.muted,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            'جارٍ الاتصال… رسائلك المحفوظة متاحة',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: p.muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (rows.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child:
                                    chats.loading && chats.conversations.isEmpty
                                    ? const CircularProgressIndicator()
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 42,
                                            color: p.muted.withValues(
                                              alpha: .5,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            q.isNotEmpty
                                                ? 'ماكو محادثة مطابقة'
                                                : filter == 'unread'
                                                ? 'كل رسائلك مقروءة'
                                                : filter == 'groups'
                                                ? 'مجموعاتك تظهر هنا'
                                                : 'ابدأ محادثة جديدة',
                                            style: TextStyle(color: p.muted),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () => action(
                                              filter == 'groups'
                                                  ? 'group'
                                                  : 'search',
                                            ),
                                            child: Text(
                                              filter == 'groups'
                                                  ? 'إنشاء مجموعة'
                                                  : 'البحث عن شخص',
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final c = rows[i],
                                pend = pending(c),
                                t = chats.threads[c.id],
                                isTyping = t?.peerTyping == true;
                            return Column(
                              children: [
                                InkWell(
                                  key: ValueKey('chat-row-${c.id}'),
                                  onTap: () => open(c),
                                  onLongPress: () => organiseMenu(c),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 13,
                                    ),
                                    child: Row(
                                      children: [
                                        c.isGroup
                                            ? CircleAvatar(
                                                radius: 27,
                                                backgroundColor: p.accent
                                                    .withValues(alpha: .14),
                                                child: Icon(
                                                  Icons.groups_rounded,
                                                  size: 29,
                                                  color: p.accent,
                                                ),
                                              )
                                            : AccountAvatar(
                                                c.peer.avatarUser,
                                                size: 54,
                                              ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                c.peer.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: c.unreadCount > 0
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                              CharismaBadge(c.peer.identity),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  if (pend != null ||
                                                      c.lastMessageIsMine &&
                                                          c
                                                              .lastMessage
                                                              .isNotEmpty) ...[
                                                    Icon(
                                                      pend != null
                                                          ? Icons
                                                                .schedule_rounded
                                                          : Icons
                                                                .done_all_rounded,
                                                      size: 16,
                                                      color: pend != null
                                                          ? p.muted
                                                          : c.sequence <=
                                                                c.peerReadSequence
                                                          ? p.accent
                                                          : p.muted,
                                                    ),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      preview(c),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 13.5,
                                                        color: isTyping
                                                            ? p.accent
                                                            : p.muted,
                                                        fontWeight:
                                                            isTyping ||
                                                                c.unreadCount >
                                                                    0
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              c.lastMessage.isEmpty &&
                                                      pend == null
                                                  ? ''
                                                  : chatTime(
                                                      pend?.createdAt ??
                                                          c.lastMessageAt,
                                                      inbox: true,
                                                    ),
                                              textDirection: TextDirection.ltr,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: c.unreadCount > 0
                                                    ? p.accent
                                                    : p.muted,
                                              ),
                                            ),
                                            const SizedBox(height: 7),
                                            if (c.unreadCount > 0)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 21,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: p.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  c.unreadCount > 99
                                                      ? '99+'
                                                      : '${c.unreadCount}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              )
                                            else
                                              const SizedBox(height: 18),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 86,
                                  ),
                                  child: Divider(height: 1, color: p.line),
                                ),
                              ],
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 90)),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 20,
                    end: 18,
                    child: FloatingActionButton(
                      key: const Key('chat-new-message'),
                      tooltip: 'محادثة جديدة',
                      backgroundColor: p.accent,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      onPressed: () => action('search'),
                      child: const Icon(Icons.edit_square, size: 26),
                    ),
                  ),
                ],
              ),
            );
          },
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
    final gen = widget.chats.generation;
    setState(() => busy = true);
    try {
      final d = await widget.chats.accounts.chatRequest(
        'PUT',
        '/v1/chat/blocks/$id',
        body: {'blocked': false},
      );
      if (!mounted || gen != widget.chats.generation) return;
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
  Widget build(BuildContext context) => ChatSurface(
    child: Scaffold(
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
              leading: AccountAvatar(
                PostAuthor.fromJson(
                  Map<String, dynamic>.from(u as Map),
                ).avatarUser,
                size: 44,
              ),
              title: Text(u['displayName'] as String),
              subtitle: Text('@${u['username']}'),
              trailing: TextButton(
                onPressed: busy ? null : () => unblock(u['id'] as String),
                child: const Text('إلغاء الحظر'),
              ),
            ),
        ],
      ),
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
    this.initialWallpaper,
  });
  final ChatController chats;
  final DirectConversation conversation;
  final XFile? initialImage, initialVideo, initialWallpaper;
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
  DocumentDraft? document;
  final focus = FocusNode();
  int pane = 0;
  bool picking = false, mutating = false, capturing = false;
  final cancelVoice = ValueNotifier<bool>(false);
  double? voiceDownX;
  int renderedSequence = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(scrolled);
    focus.addListener(() {
      if (focus.hasFocus && pane != 0 && mounted) setState(() => pane = 0);
    });
    if (widget.initialWallpaper != null)
      unawaited(
        readPickedImage(
          widget.initialWallpaper!,
        ).then(thread.setWallpaperImage),
      );
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
        document = thread.draftAttachment?.document;
        video = thread.draftAttachment?.video;
      });
  }

  Future<void> loadVideo(XFile file) async {
    if (mounted) setState(() => picking = true);
    try {
      final v = await readPickedVideo(file);
      if (!mounted || !thread.current) return;
      await thread.setAttachment(v);
      if (mounted)
        setState(() {
          video = v;
          image = null;
          document = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح أو حفظ الفيديو.');
    } finally {
      if (mounted) setState(() => picking = false);
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
      final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
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
          document = null;
        });
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حفظ إزالة المرفق.');
    }
  }

  Future<void> tools(ChatMessage m, String action) async {
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) showNote(context, 'تم نسخ النص');
      return;
    }
    if (action == 'delete') {
      await delete(m);
      return;
    }
    if (action == 'edit') {
      await editMessage(m);
      return;
    }
    if (action == 'info') {
      await messageInfo(m);
      return;
    }
    if (action == 'reply') {
      thread.chooseReply(m);
      focus.requestFocus();
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
            : {'pinned': thread.pinnedMessageId != m.id},
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
    if (videoFile(f)) {
      await loadVideo(f);
      return;
    }
    try {
      final draft = await readPickedImage(f);
      if (!mounted || !thread.current) return;
      await thread.setAttachment(draft);
      if (mounted)
        setState(() {
          image = draft;
          video = null;
          document = null;
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

  Future<void> toggleMute() async {
    if (thread.conversation.isGroup) return;
    try {
      final path = '/v1/chats/${thread.conversation.id}/mute';
      final old = await widget.chats.accounts.chatRequest('GET', path);
      final saved = await widget.chats.accounts.chatRequest(
        'PUT',
        path,
        body: {'muted': old['muted'] != true},
      );
      if (mounted)
        showNote(
          context,
          saved['muted'] == true
              ? 'تم كتم إشعارات هذه المحادثة.'
              : 'تم إلغاء الكتم.',
        );
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر تغيير الكتم؛ أعد المحاولة.');
    }
  }

  Future<void> recordVoice() async {
    if (widget.chats.accounts.liveAudioBusy) {
      showNote(
        context,
        'أنهِ المكالمة أو غادر الغرفة الصوتية قبل تسجيل رسالة.',
      );
      return;
    }
    if (capturing ||
        picking ||
        image != null ||
        video != null ||
        document != null)
      return;
    cancelVoice.value = false;
    setState(() => capturing = true);
    await playback.stop();
    if (!mounted) return;
    final draft = await showModalBottomSheet<AudioDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ChatSurface(
        child: VoiceRecorderSheet(
          autoStart: true,
          cancel: cancelVoice,
          onRecording: thread.recordingPresence,
        ),
      ),
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
    if (!thread.current || !thread.conversation.canSend || thread.restoring)
      return;
    if (picking || capturing) return;
    try {
      thread.enqueue(input.text, image, video: video, document: document);
      if (input.text.trim().isEmpty &&
          image == null &&
          video == null &&
          document == null)
        return;
      input.clear();
      setState(() {
        image = null;
        video = null;
        document = null;
      });
      thread.atLatest = true;
      if (scroll.hasClients) scroll.jumpTo(0);
    } on AccountFailure catch (f) {
      showNote(context, f.message);
    }
  }

  Future<void> chooseWallpaper() async {
    var preview = thread.wallpaper;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('معاينة خلفية المحادثة'),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(minHeight: 150),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: [
                        Theme.of(context).scaffoldBackgroundColor,
                        const Color(0xff21172f),
                        const Color(0xff102b3b),
                        const Color(0xff142d25),
                        const Color(0xff35202f),
                        const Color(0xff17191d),
                      ][preview],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Chip(label: Text('هلا، شلونك؟')),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(label: Text('تمام، هاي معاينة الخلفية')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final e in [
                        'الافتراضية',
                        'ليل بنفسجي',
                        'محيط',
                        'غابة',
                        'وردي',
                        'فحمي',
                      ].asMap().entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: preview == e.key,
                          onSelected: (_) => update(() => preview = e.key),
                        ),
                    ],
                  ),
                  const Text('محفوظة على جهازك لهذا الحساب فقط'),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, preview),
                    child: const Text('حفظ الخلفية'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, -1),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('صورة من الاستوديو'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (chosen == -1 && mounted) {
      await GalleryIntent.remember(
        widget.chats.accounts.api.baseUrl,
        widget.chats.accounts.user!.id,
        conversationId: thread.conversation.id,
        purpose: 'chat-wallpaper',
      );
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 2400,
        imageQuality: 80,
      );
      await GalleryIntent.clear();
      if (file != null && mounted)
        await thread.setWallpaperImage(await readPickedImage(file));
    } else if (chosen != null && mounted)
      await thread.setWallpaper(chosen);
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

  bool videoFile(XFile f) =>
      f.mimeType?.startsWith('video/') == true ||
      RegExp(
        r'\.(mp4|mov|m4v|webm|mkv)$',
        caseSensitive: false,
      ).hasMatch(f.name);
  Future<void> pickMixed() async {
    if (picking || capturing) return;
    setState(() => picking = true);
    focus.unfocus();
    try {
      await GalleryIntent.remember(
        widget.chats.accounts.api.baseUrl,
        widget.chats.accounts.user!.id,
        conversationId: thread.conversation.id,
        purpose: 'chat-media',
      );
      final f = await ImagePicker().pickMedia(
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await GalleryIntent.clear();
      if (f != null && mounted && thread.current) {
        if (videoFile(f))
          await loadVideo(f);
        else
          await loadImage(f);
      }
    } catch (_) {
      if (mounted)
        showNote(context, 'تعذّر فتح الصور والفيديو؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> pickCamera() async {
    if (picking || capturing) return;
    setState(() => picking = true);
    focus.unfocus();
    try {
      await GalleryIntent.remember(
        widget.chats.accounts.api.baseUrl,
        widget.chats.accounts.user!.id,
        conversationId: thread.conversation.id,
        purpose: 'chat-media',
      );
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await GalleryIntent.clear();
      if (f != null && mounted && thread.current) await loadImage(f);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح الكاميرا؛ تأكد من الصلاحية.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> pickDocument() async {
    if (picking || capturing) return;
    setState(() => picking = true);
    focus.unfocus();
    try {
      final f = await files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(
            label: 'مستندات وملفات',
            extensions: [
              'pdf',
              'txt',
              'csv',
              'json',
              'md',
              'doc',
              'docx',
              'xls',
              'xlsx',
              'ppt',
              'pptx',
              'zip',
              'rar',
              '7z',
            ],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (f == null || !mounted || !thread.current) return;
      final length = await f.length();
      if (length < 1 ||
          length > 25 * 1024 * 1024 ||
          f.name.length > 120 ||
          RegExp(r'[\x00-\x1f/\\]').hasMatch(f.name))
        throw const AccountFailure(
          'FILE_SIZE',
          'اختَر ملفًا حتى25 MB باسم صحيح.',
        );
      final d = DocumentDraft(await f.readAsBytes(), f.name);
      await thread.setAttachment(d);
      if (mounted && thread.current)
        setState(() {
          document = d;
          image = null;
          video = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح أو حفظ الملف.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> attachments() async {
    focus.unfocus();
    setState(() => pane = 0);
    final c = thread.conversation, p = ChatPalette.of(context);
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ChatSurface(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'إرفاق',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  key: const Key('private-chat-image'),
                  enabled: c.imageUploadEnabled || c.videoUploadEnabled,
                  leading: CircleAvatar(
                    backgroundColor: p.accent.withValues(alpha: .15),
                    child: Icon(Icons.photo_library_rounded, color: p.accent),
                  ),
                  title: const Text(
                    'الصور والفيديو',
                    key: Key('private-chat-video'),
                  ),
                  subtitle: const Text('اختَر من المعرض'),
                  onTap: () => Navigator.pop(context, 'media'),
                ),
                ListTile(
                  key: const Key('private-chat-document'),
                  enabled: c.fileUploadEnabled,
                  leading: CircleAvatar(
                    backgroundColor: const Color(
                      0xFF9B7BEE,
                    ).withValues(alpha: .16),
                    child: const Icon(
                      Icons.description_rounded,
                      color: Color(0xFF9B7BEE),
                    ),
                  ),
                  title: const Text('مستند أو ملف'),
                  subtitle: const Text('PDF، ملفات Office، وملفات مضغوطة'),
                  onTap: () => Navigator.pop(context, 'file'),
                ),
                ListTile(
                  enabled: c.imageUploadEnabled,
                  leading: CircleAvatar(
                    backgroundColor: const Color(
                      0xFFEC6D91,
                    ).withValues(alpha: .16),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFFEC6D91),
                    ),
                  ),
                  title: const Text('التقاط صورة'),
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
                ListTile(
                  enabled:
                      c.audioUploadEnabled &&
                      image == null &&
                      video == null &&
                      document == null,
                  leading: CircleAvatar(
                    backgroundColor: const Color(
                      0xFFEAB45F,
                    ).withValues(alpha: .16),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Color(0xFFEAB45F),
                    ),
                  ),
                  title: const Text('رسالة صوتية'),
                  onTap: () => Navigator.pop(context, 'voice'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || !thread.current) return;
    if (value == 'media')
      await pickMixed();
    else if (value == 'file')
      await pickDocument();
    else if (value == 'camera')
      await pickCamera();
    else if (value == 'voice')
      await recordVoice();
  }

  void insertEmoji(String emoji) {
    final selection = input.selection,
        start = selection.isValid ? selection.start : input.text.length,
        end = selection.isValid ? selection.end : input.text.length;
    input.value = TextEditingValue(
      text: input.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    thread.setDraft(input.text);
    thread.noteTyping();
  }

  Future<void> pickGif() async {
    if (picking || thread.sending) return;
    setState(() => picking = true);
    try {
      final file = await files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(
            label: 'GIF',
            extensions: ['gif'],
            mimeTypes: ['image/gif'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024)
        throw const AccountFailure('GIF_SIZE', 'اختار GIF أصغر من10 MB.');
      final bytes = await file.readAsBytes();
      if (bytes.length < 13 ||
          !['GIF87a', 'GIF89a'].contains(String.fromCharCodes(bytes.take(6))))
        throw const AccountFailure('GIF_TYPE', 'الملف مو GIF صالح.');
      final selected = ImageDraft(bytes, 'image/gif');
      await thread.setAttachment(selected);
      if (mounted && thread.current)
        setState(() {
          image = selected;
          video = null;
          document = null;
          pane = 0;
        });
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح GIF؛ جرّب ملفًا ثانيًا.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void sendSticker(String id) {
    try {
      thread.enqueue('', null, stickerId: id);
    } on AccountFailure catch (e) {
      showNote(context, e.message);
    }
  }

  Future<void> call(bool video) async {
    await playback.stop();
    if (!mounted || !thread.current) return;
    await widget.chats.accounts.calls.start(
      thread.conversation.id,
      video: video,
    );
    if (mounted && widget.chats.accounts.calls.error != null)
      showNote(context, widget.chats.accounts.calls.error!);
  }

  Future<void> info() async {
    if (thread.conversation.isGroup) {
      final left = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupInfoPage(
            chats: widget.chats,
            conversation: thread.conversation,
          ),
        ),
      );
      if (left == true && mounted) Navigator.pop(context);
    } else
      await openAuthor(
        context,
        widget.chats.accounts,
        thread.conversation.peer,
      );
  }

  Future<void> openDocument(ChatMessage m) async {
    try {
      final uri = await thread.mediaSource(m.id, 'file');
      if (!mounted) return;
      if (uri == null ||
          uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication))
        throw StateError('File unavailable');
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح الملف؛ حاول تحديث المرفق.');
    }
  }

  Future<void> editMessage(ChatMessage m) async {
    final input = TextEditingController(text: m.text);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعديل الرسالة'),
        content: TextField(
          controller: input,
          minLines: 1,
          maxLines: 6,
          maxLength: 2000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await thread.request(
          'PUT',
          '/messages/${m.id}/edit',
          body: {'text': input.text, 'expectedRevision': m.revision},
        );
        await thread.refreshMessage(m.id);
      } on AccountFailure catch (e) {
        if (mounted) showNote(context, e.message);
      }
    }
    input.dispose();
  }

  Future<void> messageInfo(ChatMessage m) async {
    try {
      final d = await thread.request('GET', '/messages/${m.id}/info');
      if (!mounted) return;
      String time(Object? value) {
        final date = DateTime.tryParse(value as String? ?? '');
        return date == null
            ? 'غير مسجّل بعد'
            : date.toLocal().toString().split('.').first;
      }

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تفاصيل الرسالة',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text('أُرسلت: ${time(d['sentAt'])}'),
                if (d['editedAt'] != null)
                  Text('عُدّلت: ${time(d['editedAt'])}'),
                if ((d['receipts'] as List? ?? []).isEmpty)
                  const Text('وقت الوصول والمشاهدة غير مسجّل بعد.'),
                for (final r in d['receipts'] as List? ?? []) ...[
                  const Divider(),
                  Text('وصلت: ${time(r['deliveredAt'])}'),
                  Text('شُوهدت: ${time(r['readAt'])}'),
                ],
              ],
            ),
          ),
        ),
      );
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    }
  }

  Future<void> messageActions(ChatMessage m) async {
    if (m.deleted) return;
    final c = thread.conversation;
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ChatSurface(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.canSend)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Wrap(
                      spacing: 9,
                      children: [
                        for (final e in ['❤️', '😂', '👍', '😮', '😢', '🔥'])
                          IconButton(
                            tooltip: e,
                            onPressed: () => Navigator.pop(context, 'emoji:$e'),
                            icon: Text(e, style: const TextStyle(fontSize: 27)),
                          ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('تفاصيل الرسالة'),
                  onTap: () => Navigator.pop(context, 'info'),
                ),
                if (m.isMine && m.text.isNotEmpty && c.canSend)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('تعديل الرسالة'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (c.canSend)
                  ListTile(
                    leading: const Icon(Icons.reply_rounded),
                    title: const Text('رد'),
                    onTap: () => Navigator.pop(context, 'reply'),
                  ),
                if (m.text.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('نسخ النص'),
                    onTap: () => Navigator.pop(context, 'copy'),
                  ),
                if (c.canSend)
                  ListTile(
                    leading: const Icon(Icons.push_pin_outlined),
                    title: Text(
                      thread.pinnedMessageId == m.id
                          ? 'إلغاء التثبيت'
                          : 'تثبيت الرسالة',
                    ),
                    onTap: () => Navigator.pop(context, 'pin'),
                  ),
                if (m.isMine || c.isGroup && c.isOwner)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'حذف الرسالة',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (value == null || !mounted || !thread.current) return;
    if (value.startsWith('emoji:')) {
      try {
        await thread.changeTool(m, 'reaction', {'emoji': value.substring(6)});
      } catch (_) {
        if (mounted) showNote(context, 'تعذّر إضافة التفاعل.');
      }
    } else
      await tools(m, value);
  }

  Widget expressionPanel(double height) {
    final p = ChatPalette.of(context);
    const emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '🥰',
      '😍',
      '😘',
      '😎',
      '🤩',
      '🥳',
      '😉',
      '🙂',
      '🤗',
      '🫶',
      '🤍',
      '❤️',
      '💙',
      '💜',
      '💛',
      '🧡',
      '💚',
      '🔥',
      '✨',
      '🎉',
      '👍',
      '👎',
      '👏',
      '🙏',
      '🤝',
      '💪',
      '👋',
      '🤔',
      '😴',
      '🥺',
      '😢',
      '😭',
      '😤',
      '🤯',
      '😮',
      '😋',
      '☕',
      '🌹',
      '🌺',
      '🌙',
      '⭐',
      '🎁',
      '🎂',
      '✅',
      '💯',
      '⚽',
      '🎮',
      '📚',
      '💬',
      '🐼',
      '🐱',
    ];
    final stickerKeys = tomiStickers.keys
        .where(
          (id) => pane == 3
              ? animatedStickerIds.contains(id)
              : !animatedStickerIds.contains(id),
        )
        .toList();
    return Container(
      key: const Key('chat-expression-panel'),
      height: height,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'لوحة المفاتيح',
                onPressed: () {
                  setState(() => pane = 0);
                  focus.requestFocus();
                },
                icon: const Icon(Icons.keyboard_rounded),
              ),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 1,
                      label: Text(
                        'إيموجي',
                        maxLines: 1,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('GIF', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text(
                        'ملصقات',
                        maxLines: 1,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  selected: {pane},
                  onSelectionChanged: (v) => setState(() => pane = v.first),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
          if (pane == 3)
            TextButton.icon(
              onPressed: picking ? null : pickGif,
              icon: const Icon(Icons.gif_box_outlined),
              label: const Text('GIF من جهازك'),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: pane == 1 ? 48 : 94,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: pane == 1 ? emojis.length : stickerKeys.length,
              itemBuilder: (context, i) => pane == 1
                  ? InkResponse(
                      key: ValueKey('chat-emoji-$i'),
                      onTap: () => insertEmoji(emojis[i]),
                      child: Center(
                        child: Text(
                          emojis[i],
                          style: const TextStyle(fontSize: 27),
                        ),
                      ),
                    )
                  : InkWell(
                      key: ValueKey('chat-sticker-${stickerKeys[i]}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => sendSticker(stickerKeys[i]),
                      child: TomiSticker(id: stickerKeys[i], size: 82),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget bubble(ChatMessage m) {
    return Dismissible(
      key: ValueKey('reply-swipe-${m.id}'),
      direction: !m.deleted && thread.conversation.canSend
          ? DismissDirection.startToEnd
          : DismissDirection.none,
      dismissThresholds: const {DismissDirection.startToEnd: .22},
      movementDuration: const Duration(milliseconds: 160),
      background: const Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Icon(Icons.reply_rounded),
        ),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.selectionClick();
        if (thread.current) {
          thread.chooseReply(m);
          focus.requestFocus();
        }
        return false;
      },
      child: messageBubble(m),
    );
  }

  Widget messageBubble(ChatMessage m) {
    final p = ChatPalette.of(context),
        c = thread.conversation,
        sticker = m.stickerId != null && !m.deleted,
        read = m.isMine && m.sequence <= c.peerReadSequence;
    return Align(
      alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => messageActions(m),
        onTap: () => messageActions(m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: EdgeInsets.fromLTRB(
            sticker ? 2 : 10,
            sticker ? 2 : 7,
            sticker ? 2 : 10,
            3,
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .82,
          ),
          decoration: BoxDecoration(
            color: sticker
                ? Colors.transparent
                : m.isMine
                ? p.outgoing
                : p.incoming,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(m.isMine ? 13 : 3),
              topRight: Radius.circular(m.isMine ? 3 : 13),
              bottomLeft: const Radius.circular(13),
              bottomRight: const Radius.circular(13),
            ),
            boxShadow: sticker
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .035),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onDoubleTap:
                    !m.deleted &&
                        c.canSend &&
                        m.audio == null &&
                        m.video == null &&
                        m.document == null
                    ? () async {
                        try {
                          await thread.changeTool(m, 'reaction', {
                            'emoji': '❤️',
                          });
                        } catch (_) {
                          if (mounted)
                            showNote(context, 'تعذّر إضافة التفاعل.');
                        }
                      }
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isGroup &&
                        !m.isMine &&
                        !m.deleted &&
                        m.authorName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: p.accent,
                              ),
                            ),
                            CharismaBadge(m.authorIdentity, compact: true),
                          ],
                        ),
                      ),
                    if (!m.deleted &&
                        !c.isGroup &&
                        RegExp(
                          r'^دعوة للعب .+ • كود الغرفة: [A-F0-9]{8}\n',
                        ).hasMatch(m.text))
                      TextButton.icon(
                        icon: const Icon(Icons.sports_esports),
                        label: const Text('انضم للعبة'),
                        onPressed: () {
                          final code = RegExp(
                            r'كود الغرفة: ([A-F0-9]{8})',
                          ).firstMatch(m.text)!.group(1)!;
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: const Text('الألعاب')),
                                body: CSharpGamesPage(
                                  accounts: widget.chats.accounts,
                                  initialCode: code,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (m.deleted)
                      Text(
                        'تم حذف الرسالة',
                        style: TextStyle(
                          color: p.muted,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      )
                    else ...[
                      if (m.reply != null)
                        InkWell(
                          onTap: () => showMessage(m.reply!['id'] as String),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(
                                alpha: p.dark ? .12 : .035,
                              ),
                              border: BorderDirectional(
                                start: BorderSide(color: p.accent, width: 3),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.reply!['author'] as String? ?? 'رد',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: p.accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m.reply!['text'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (m.data['sharedPost'] != null)
                        InkWell(
                          key: ValueKey('shared-post-${m.id}'),
                          onTap:
                              (m.data['sharedPost'] as Map)['available'] ==
                                      true &&
                                  (m.data['sharedPost'] as Map)['id'] is String
                              ? () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SharedPostPage(
                                      accounts: widget.chats.accounts,
                                      postId:
                                          (m.data['sharedPost'] as Map)['id']
                                              as String,
                                    ),
                                  ),
                                )
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: p.raised,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.article_outlined, size: 20),
                                    SizedBox(width: 6),
                                    Flexible(child: Text('منشور مشارك')),
                                  ],
                                ),
                                Text(
                                  (m.data['sharedPost'] as Map)['available'] ==
                                          true
                                      ? (m.data['sharedPost'] as Map)['text']
                                            as String
                                      : 'هذا المنشور لم يعد متاحًا',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (sticker) TomiSticker(id: m.stickerId!, size: 144),
                      if (m.video != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: VideoTile(
                            video: m.video!,
                            source: () => thread.mediaSource(m.id, 'video'),
                          ),
                        ),
                      if (m.image?.url != null)
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ChatImagePage(
                                thread: thread,
                                messageId: m.id,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: NetworkMediaImage(
                              m.image!.url!,
                              height: 190,
                              width: 280,
                              fit: BoxFit.cover,
                              cacheWidth: 650,
                              errorBuilder: (_, _, _) => TextButton.icon(
                                onPressed: () => thread.refreshMessage(m.id),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('تحديث الصورة'),
                              ),
                            ),
                          ),
                        ),
                      if (m.document != null)
                        InkWell(
                          key: ValueKey('document-${m.id}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => openDocument(m),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.description_rounded,
                                  size: 30,
                                  color: p.accent,
                                ),
                                const SizedBox(width: 9),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.document!.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${documentSize(m.document!.byteLength)} • ${m.document!.name.split('.').last.toUpperCase()}',
                                        textDirection: TextDirection.ltr,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.download_rounded,
                                  size: 20,
                                  color: p.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (m.audio != null)
                        _ChatVoiceMessage(
                          playback: playback,
                          id: m.id,
                          durationMs: m.audio!.durationMs,
                          source: () => thread.mediaSource(m.id, 'audio'),
                        ),
                      if (m.text.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            top:
                                m.image != null ||
                                    m.video != null ||
                                    m.document != null
                                ? 7
                                : 0,
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              fontSize: 15.5,
                              height: 1.35,
                              color: p.text,
                            ),
                          ),
                        ),
                      if (m.reactions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 3,
                            children: [
                              for (final r in m.reactions)
                                InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: !c.canSend || mutating
                                      ? null
                                      : () async {
                                          try {
                                            await thread
                                                .changeTool(m, 'reaction', {
                                                  'emoji': r['mine'] == true
                                                      ? null
                                                      : r['emoji'],
                                                });
                                          } catch (_) {
                                            if (mounted)
                                              showNote(
                                                context,
                                                'تعذّر تغيير التفاعل.',
                                              );
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: r['mine'] == true
                                          ? p.accent.withValues(alpha: .16)
                                          : p.raised,
                                      border: Border.all(
                                        color: r['mine'] == true
                                            ? p.accent.withValues(alpha: .45)
                                            : Colors.transparent,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      '${r['emoji']} ${r['count']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (m.isMine) ...[
                    Semantics(
                      label: read ? 'مقروءة' : 'تم الإرسال',
                      child: Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: read ? p.accent : p.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    chatTime(m.createdAt),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: p.muted, fontSize: 10),
                  ),
                  if (!m.deleted)
                    SizedBox(
                      width: 25,
                      height: 25,
                      child: PopupMenuButton<String>(
                        key: ValueKey('message-options:${m.id}'),
                        tooltip: 'خيارات الرسالة',
                        padding: EdgeInsets.zero,
                        iconSize: 15,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: p.muted,
                          size: 16,
                        ),
                        enabled: !mutating,
                        onSelected: (a) => tools(m, a),
                        itemBuilder: (_) => [
                          if (c.canSend) ...[
                            const PopupMenuItem(
                              value: 'reply',
                              child: Text('رد'),
                            ),
                            const PopupMenuItem(
                              value: 'reaction',
                              child: Text('تفاعل'),
                            ),
                            PopupMenuItem(
                              value: 'pin',
                              child: Text(
                                thread.pinnedMessageId == m.id
                                    ? 'إلغاء التثبيت'
                                    : 'تثبيت الرسالة',
                              ),
                            ),
                          ],
                          if (m.text.isNotEmpty)
                            const PopupMenuItem(
                              value: 'copy',
                              child: Text('نسخ النص'),
                            ),
                          if (m.isMine || c.isGroup && c.isOwner)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف الرسالة'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget pendingBubble(PendingChatMessage pending) {
    final p = ChatPalette.of(context), sticker = pending.stickerId != null;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        decoration: BoxDecoration(
          color: sticker ? Colors.transparent : p.outgoing,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sticker) TomiSticker(id: pending.stickerId!),
            if (pending.image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.memory(
                  pending.image!.bytes,
                  height: 150,
                  width: 230,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
                ),
              ),
            if (pending.transfer?.active == true) ...[
              LinearProgressIndicator(value: pending.transfer?.progress),
              TextButton.icon(
                onPressed: pending.transfer?.cancel,
                icon: const Icon(Icons.close),
                label: Text(
                  'إيقاف الرفع • ${((pending.transfer?.progress ?? 0) * 100).round()}%',
                ),
              ),
            ],
            if (pending.hasAudio) const Text('🎤 تسجيل صوتي'),
            if (pending.hasVideo) const Text('🎬 فيديو'),
            if (pending.hasDocument)
              Text(
                '📎 ${pending.document?.name ?? pending.savedMedia?['fileName'] ?? 'مستند'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (pending.text.isNotEmpty)
              Text(
                pending.text,
                style: const TextStyle(fontSize: 15.5, height: 1.35),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pending.busy
                      ? Icons.schedule_rounded
                      : Icons.error_outline_rounded,
                  size: 13,
                  color: pending.busy ? p.muted : Colors.redAccent,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    pending.busy
                        ? 'جارٍ الإرسال…'
                        : pending.error ?? 'قيد الانتظار',
                    style: TextStyle(
                      fontSize: 11,
                      color: pending.busy ? p.muted : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
            if (!pending.busy)
              Wrap(
                children: [
                  TextButton(
                    onPressed: thread.sending || !thread.conversation.canSend
                        ? null
                        : () => thread.retryPending(pending, manual: true),
                    child: const Text('إعادة المحاولة'),
                  ),
                  TextButton(
                    onPressed: () => thread.discard(pending),
                    child: const Text('إلغاء إعادة المحاولة'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    playback.dispose();
    cancelVoice.dispose();
    thread.visible = false;
    thread.stopTyping();
    chatRouteObserver.unsubscribe(this);
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      thread,
      widget.chats,
      input,
      widget.chats.accounts.calls,
    ]),
    builder: (context, _) {
      if (thread.conversation.secureEnabled)
        return SecureChatPage(
          accounts: widget.chats.accounts,
          threadId: thread.conversation.id,
          title: thread.conversation.peer.displayName,
        );
      final headerHeight =
          (MediaQuery.textScalerOf(context).scale(16) * 1.2 +
                  MediaQuery.textScalerOf(context).scale(11) * 1.1 +
                  11)
              .clamp(64.0, 128.0);
      final c = thread.conversation,
          p = ChatPalette.of(context),
          h =
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              headerHeight -
              MediaQuery.paddingOf(context).vertical;
      final previousExtent = scroll.hasClients
              ? scroll.position.maxScrollExtent
              : 0.0,
          previousOffset = scroll.hasClients ? scroll.offset : 0.0;
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
      final pending = thread.pending.reversed.toList(),
          messages = thread.messages.reversed.toList(),
          count =
              pending.length +
              messages.length +
              (thread.nextBefore == null ? 0 : 1),
          hasDraft =
              input.text.trim().isNotEmpty ||
              image != null ||
              video != null ||
              document != null;
      final status = thread.peerTyping
          ? thread.activityLabel
          : widget.chats.realtimeEnabled && !widget.chats.connected
          ? 'جارٍ الاتصال…'
          : c.isGroup
          ? '${c.memberCount} أعضاء'
          : 'محادثة خاصة';
      Widget banner() {
        final attachment = document != null
            ? document!.name
            : video != null
            ? 'فيديو • ${voiceTime(video!.durationMs)}'
            : image != null
            ? 'صورة مرفقة'
            : '';
        final reply = thread.replyToId == null
            ? ''
            : thread.cache[thread.replyToId]?.text ?? 'رد على رسالة';
        return Container(
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              if (image != null && h >= 240) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    image!.bytes,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (document != null || video != null) ...[
                Icon(
                  document != null
                      ? Icons.description_outlined
                      : Icons.videocam_outlined,
                  color: p.accent,
                  size: 24,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  [
                    if (reply.isNotEmpty) 'رد: $reply',
                    if (attachment.isNotEmpty) attachment,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
              if (thread.replyToId != null)
                IconButton(
                  tooltip: 'إلغاء الرد',
                  onPressed: () => thread.chooseReply(null),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              if (attachment.isNotEmpty)
                IconButton(
                  tooltip: 'إزالة المرفق',
                  onPressed: clearAttachment,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
        );
      }

      Widget composer() => Container(
        color: p.surface,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: p.raised,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const Key('chat-emoji-toggle'),
                        tooltip: pane == 0
                            ? 'الإيموجي والملصقات'
                            : 'لوحة المفاتيح',
                        onPressed: capturing || picking
                            ? null
                            : () {
                                if (pane == 0) {
                                  focus.unfocus();
                                  setState(() => pane = 1);
                                } else {
                                  setState(() => pane = 0);
                                  focus.requestFocus();
                                }
                              },
                        constraints: const BoxConstraints(
                          minWidth: 42,
                          minHeight: 48,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          pane == 0
                              ? Icons.emoji_emotions_outlined
                              : Icons.keyboard_rounded,
                          color: p.muted,
                          size: 24,
                        ),
                      ),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: h < 240 ? 64 : 120,
                          ),
                          child: TextField(
                            key: const Key('private-chat-input'),
                            controller: input,
                            focusNode: focus,
                            enabled: !thread.restoring,
                            minLines: 1,
                            maxLines: h < 240 ? 1 : 4,
                            maxLength: 2000,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 15.5,
                              height: 1.3,
                              color: p.text,
                            ),
                            onChanged: (v) {
                              thread.setDraft(v);
                              thread.noteTyping();
                            },
                            textInputAction: h < 180
                                ? TextInputAction.send
                                : TextInputAction.newline,
                            onSubmitted: h < 180 ? (_) => send() : null,
                            decoration: InputDecoration(
                              hintText: 'اكتب رسالة…',
                              hintTextDirection: TextDirection.rtl,
                              counterText: '',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('private-chat-attachment'),
                        tooltip: 'إرفاق صورة أو فيديو أو ملف',
                        onPressed: picking || capturing || thread.restoring
                            ? null
                            : attachments,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 48,
                        ),
                        padding: EdgeInsets.zero,
                        icon: picking
                            ? SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: p.accent,
                                ),
                              )
                            : Icon(Icons.add_rounded, color: p.muted, size: 27),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Listener(
                onPointerDown: (e) {
                  if (!hasDraft &&
                      c.audioUploadEnabled &&
                      !picking &&
                      !capturing &&
                      !thread.restoring) {
                    voiceDownX = e.position.dx;
                    unawaited(recordVoice());
                  }
                },
                onPointerMove: (e) {
                  if (capturing &&
                      voiceDownX != null &&
                      e.position.dx < voiceDownX! - 64)
                    cancelVoice.value = true;
                },
                onPointerUp: (_) => voiceDownX = null,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    key: hasDraft
                        ? const Key('private-chat-send')
                        : const Key('private-chat-voice'),
                    tooltip: hasDraft ? 'إرسال الرسالة' : 'تسجيل رسالة صوتية',
                    onPressed: picking || capturing || thread.restoring
                        ? null
                        : hasDraft
                        ? send
                        : c.audioUploadEnabled
                        ? recordVoice
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: p.accent.withValues(alpha: .35),
                    ),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 120),
                      child: Icon(
                        hasDraft ? Icons.send_rounded : Icons.mic_rounded,
                        key: ValueKey(hasDraft),
                        size: 23,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return ChatSurface(
        child: PopScope(
          canPop: pane == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && pane != 0) setState(() => pane = 0);
          },
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: headerHeight,
              leadingWidth: 42,
              leading: BackButton(onPressed: () => Navigator.maybePop(context)),
              titleSpacing: 0,
              title: InkWell(
                onTap: info,
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    c.isGroup
                        ? CircleAvatar(
                            radius: 19,
                            backgroundColor: p.accent.withValues(alpha: .15),
                            child: Icon(
                              Icons.groups_rounded,
                              color: p.accent,
                              size: 23,
                            ),
                          )
                        : AccountAvatar(c.peer.avatarUser, size: 38),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.peer.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: CharismaBadge(
                                  c.peer.identity,
                                  compact: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: thread.peerTyping ? p.accent : p.muted,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!c.isGroup) ...[
                  IconButton(
                    key: const Key('chat-video-call'),
                    tooltip: 'مكالمة فيديو',
                    onPressed: c.canSend && !widget.chats.accounts.calls.busy
                        ? () => call(true)
                        : null,
                    icon: const Icon(Icons.videocam_outlined, size: 25),
                  ),
                  IconButton(
                    key: const Key('chat-voice-call'),
                    tooltip: 'مكالمة صوتية',
                    onPressed: c.canSend && !widget.chats.accounts.calls.busy
                        ? () => call(false)
                        : null,
                    icon: const Icon(Icons.call_outlined, size: 22),
                  ),
                ],
                PopupMenuButton<String>(
                  key: const Key('chat-thread-menu'),
                  tooltip: 'قائمة المحادثة',
                  onSelected: (value) async {
                    if (value == 'secure') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecureChatPage(
                            accounts: widget.chats.accounts,
                            threadId: c.id,
                            title: c.peer.displayName,
                            setupOnly: true,
                          ),
                        ),
                      );
                      await widget.chats.refreshConversation(c.id);
                      return;
                    }
                    if (value == 'search')
                      unawaited(search());
                    else if (value == 'info')
                      unawaited(info());
                    else if (value == 'game')
                      unawaited(
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => ChatGameInvite(thread: thread),
                        ),
                      );
                    else if (value == 'mute')
                      unawaited(toggleMute());
                    else if (value == 'wallpaper')
                      unawaited(chooseWallpaper());
                    else if (value == 'pinned')
                      unawaited(showMessage(thread.pinnedMessageId!));
                    else
                      unawaited(toggleBlock());
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'info',
                      child: Text(
                        c.isGroup ? 'معلومات المجموعة' : 'عرض الحساب',
                      ),
                    ),
                    if (!c.isGroup)
                      const PopupMenuItem(
                        value: 'secure',
                        child: Text('تفعيل محادثة مشفرة'),
                      ),
                    const PopupMenuItem(
                      key: Key('chat-search'),
                      value: 'search',
                      child: Text('بحث في المحادثة'),
                    ),
                    if (thread.pinnedMessageId != null)
                      const PopupMenuItem(
                        value: 'pinned',
                        child: Text('الرسالة المثبّتة'),
                      ),
                    if (!c.isGroup && c.canSend)
                      const PopupMenuItem(
                        value: 'game',
                        child: Text('ادعُه للعبة'),
                      ),
                    if (!c.isGroup)
                      const PopupMenuItem(
                        value: 'mute',
                        child: Text('كتم / إلغاء كتم إشعارات المحادثة'),
                      ),
                    PopupMenuItem(
                      value: 'wallpaper',
                      child: const Text('خلفية المحادثة'),
                    ),
                    if (!c.isGroup)
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          c.blockedByMe ? 'إلغاء الحظر' : 'حظر المستخدم',
                        ),
                      ),
                  ],
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: [
                          p.background,
                          const Color(0xff21172f),
                          const Color(0xff102b3b),
                          const Color(0xff142d25),
                          const Color(0xff35202f),
                          const Color(0xff17191d),
                        ][thread.wallpaper],
                        child: CustomPaint(
                          painter: ChatWallpaper(
                            p.text.withValues(alpha: p.dark ? .025 : .035),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (thread.wallpaperImage != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Image.memory(
                          thread.wallpaperImage!.bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      if (thread.pinnedMessageId != null && h >= 360)
                        Material(
                          color: p.surface,
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              Icons.push_pin_outlined,
                              size: 19,
                              color: p.accent,
                            ),
                            title: Text(
                              'رسالة مثبّتة',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.muted),
                            ),
                            trailing: const Icon(
                              Icons.chevron_left_rounded,
                              size: 20,
                            ),
                            onTap: () => showMessage(thread.pinnedMessageId!),
                          ),
                        ),
                      if (thread.error != null && h >= 280)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => thread.sync(reconcile: true),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            thread.error!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child:
                                  thread.loading &&
                                      messages.isEmpty &&
                                      pending.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: () =>
                                          thread.sync(reconcile: true),
                                      child: ListView.builder(
                                        key: const Key('chat-message-list'),
                                        controller: scroll,
                                        reverse: true,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          12,
                                          12,
                                          5,
                                        ),
                                        itemCount: count == 0 ? 1 : count,
                                        itemBuilder: (context, i) {
                                          if (count == 0)
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 32,
                                                    horizontal: 24,
                                                  ),
                                              child: Text(
                                                'ابدأ المحادثة برسالة 👋',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: p.muted,
                                                ),
                                              ),
                                            );
                                          if (i < pending.length)
                                            return KeyedSubtree(
                                              key: ValueKey(
                                                'pending:${pending[i].requestId}',
                                              ),
                                              child: pendingBubble(pending[i]),
                                            );
                                          if (i <
                                              pending.length +
                                                  messages.length) {
                                            final j = i - pending.length,
                                                m = messages[j],
                                                day = chatDay(m.createdAt),
                                                showDay =
                                                    day.isNotEmpty &&
                                                    (j == messages.length - 1 ||
                                                        chatDay(
                                                              messages[j + 1]
                                                                  .createdAt,
                                                            ) !=
                                                            day);
                                            return KeyedSubtree(
                                              key: ValueKey('message:${m.id}'),
                                              child: Column(
                                                children: [
                                                  if (showDay)
                                                    Center(
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 12,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 13,
                                                              vertical: 5,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: p.raised,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          day,
                                                          style: TextStyle(
                                                            color: p.muted,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  bubble(m),
                                                ],
                                              ),
                                            );
                                          }
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
                            if (thread.historyWindow || !thread.atLatest)
                              PositionedDirectional(
                                bottom: 10,
                                end: 7,
                                child: FloatingActionButton.small(
                                  key: const Key('chat-show-latest'),
                                  heroTag: 'latest-chat-message',
                                  tooltip: 'الرجوع لأحدث الرسائل',
                                  backgroundColor: p.surface,
                                  foregroundColor: p.accent,
                                  onPressed: () async {
                                    if (thread.historyWindow)
                                      await thread.showLatest();
                                    if (mounted && scroll.hasClients)
                                      await scroll.animateTo(
                                        0,
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOut,
                                      );
                                  },
                                  child: const Icon(
                                    Icons.keyboard_double_arrow_down_rounded,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!c.canSend)
                        Container(
                          color: p.surface,
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            c.isGroup
                                ? 'لم تعد عضوًا في المجموعة.'
                                : c.blockedByMe
                                ? 'المستخدم محظور. تگدر تلغي الحظر من القائمة.'
                                : 'المراسلة غير متاحة مع هذا المستخدم.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        )
                      else ...[
                        if (thread.replyToId != null ||
                            image != null ||
                            video != null ||
                            document != null)
                          banner(),
                        composer(),
                        if (pane != 0 && h >= 220)
                          expressionPanel((h * .4).clamp(72.0, 240.0)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ChatVoiceMessage extends StatelessWidget {
  const _ChatVoiceMessage({
    required this.playback,
    required this.id,
    required this.durationMs,
    required this.source,
  });
  final VoicePlayback playback;
  final String id;
  final int durationMs;
  final Future<Uri?> Function() source;
  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final active = playback.activeId == id,
            position = active ? playback.positionMs : 0,
            duration = active ? playback.durationMs : durationMs;
        return SizedBox(
          width: 248,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'رسالة صوتية',
                style: TextStyle(fontSize: 10, color: p.muted),
              ),
              const SizedBox(height: 2),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    TextButton(
                      key: ValueKey('chat-voice-speed-$id'),
                      onPressed: playback.cycleSpeed,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 36),
                        backgroundColor: p.accent.withValues(alpha: .14),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text('${playback.speed.toInt()}×'),
                    ),
                    IconButton(
                      tooltip: active && playback.playing
                          ? 'إيقاف مؤقت'
                          : 'تشغيل الرسالة الصوتية',
                      onPressed: playback.busy
                          ? null
                          : () => playback.toggle(
                              id,
                              source,
                              duration: durationMs,
                            ),
                      icon: playback.busy && active
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              active && playback.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 32,
                              color: p.accent,
                            ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          onTapDown: active && !playback.busy
                              ? (d) => playback.seek(
                                  (d.localPosition.dx / constraints.maxWidth)
                                          .clamp(0.0, 1.0)
                                          .toDouble() *
                                      duration,
                                )
                              : null,
                          child: SizedBox(
                            height: 29,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _WavePainter(
                                id.hashCode,
                                duration <= 0 ? 0 : position / duration,
                                p.muted.withValues(alpha: .5),
                                p.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                active
                    ? '${voiceTime(position)} / ${voiceTime(duration)}'
                    : voiceTime(durationMs),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 10, color: p.muted),
              ),
              if (active && playback.error != null)
                Text(
                  playback.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.seed, this.progress, this.color, this.active);
  final int seed;
  final double progress;
  final Color color, active;
  @override
  void paint(Canvas c, Size s) {
    final count = (s.width / 4).floor();
    for (var i = 0; i < count; i++) {
      final height = 5 + ((i * 19 + seed.abs()) % 23).toDouble(),
          x = i * 4.0 + 2;
      c.drawLine(
        Offset(x, (s.height - height) / 2),
        Offset(x, (s.height + height) / 2),
        Paint()
          ..color = i / count <= progress ? active : color
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.seed != seed ||
      old.progress != progress ||
      old.color != color ||
      old.active != active;
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
  String kind = 'all';
  DateTime? date;
  int? before;
  int epoch = 0;
  bool loading = false;
  String? error;
  Future<void> search({bool more = false}) async {
    if (more && (loading || before == null)) return;
    final q = input.text.trim(), e = ++epoch;
    if (q.runes.length < 2 && kind == 'all' && date == null) {
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
      final d = await widget.thread.search(
        q,
        before: more ? before : null,
        kind: kind,
        date: date?.toIso8601String().substring(0, 10),
      );
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in const {
                  'all': 'الكل',
                  'image': 'صور',
                  'video': 'فيديو',
                  'audio': 'صوت',
                  'link': 'روابط',
                  'file': 'ملفات',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(item.value),
                      selected: kind == item.key,
                      onSelected: loading
                          ? null
                          : (_) {
                              setState(() => kind = item.key);
                              if (input.text.trim().length >= 2 ||
                                  kind != 'all' ||
                                  date != null)
                                search();
                            },
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    date == null
                        ? 'التاريخ'
                        : date!.toIso8601String().substring(0, 10),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          final value = await showDatePicker(
                            context: c,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDate: date ?? DateTime.now(),
                          );
                          if (value != null && mounted) {
                            setState(() => date = value);
                            search();
                          }
                        },
                ),
                if (date != null)
                  IconButton(
                    tooltip: 'إلغاء التاريخ',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => date = null);
                    },
                  ),
              ],
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
                  child: NetworkMediaImage(
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
