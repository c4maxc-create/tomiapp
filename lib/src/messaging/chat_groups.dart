import 'dart:async';

import 'package:flutter/material.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../social/social_models.dart';
import '../widgets.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_widgets.dart';

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({
    super.key,
    required this.chats,
    this.group,
    this.existingIds = const {},
  });
  final ChatController chats;
  final DirectConversation? group;
  final Set<String> existingIds;
  @override
  State<GroupCreatePage> createState() => _GroupCreateState();
}

class _GroupCreateState extends State<GroupCreatePage> {
  final name = TextEditingController(), search = TextEditingController();
  final selected = <String, AccountUser>{};
  List<AccountUser> found = [];
  Timer? debounce;
  String nonce = newRequestId();
  String? error;
  bool busy = false,
      loading = true,
      frozen = false,
      searching = false,
      storageReady = true;
  int queryRevision = 0;
  late final owner = widget.chats.accounts.draftOwnerId,
      session = widget.chats.accounts.sessionRevision;
  AccountController get accounts => widget.chats.accounts;
  bool get current =>
      mounted &&
      owner == accounts.draftOwnerId &&
      session == accounts.sessionRevision;
  bool get adding => widget.group != null;
  String get scope => 'group-create';
  @override
  void initState() {
    super.initState();
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      if (!adding && owner != null) {
        final d = await accounts.draftStore.read(owner!, scope);
        if (!current) return;
        if (d != null) {
          nonce = d['requestId'] as String;
          name.text = d['title'] as String;
          for (final u in d['members'] as List) {
            final p = PostAuthor.fromJson(
              Map<String, dynamic>.from(u as Map),
            ).avatarUser;
            selected[p.id] = p;
          }
          frozen = true;
        }
      }
    } catch (_) {
      storageReady = false;
      error = 'تعذّر قراءة طلب المجموعة المحفوظ؛ أعد المحاولة.';
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  List<AccountUser> get choices {
    final map = {
      for (final c in widget.chats.conversations.where((c) => !c.isGroup))
        c.peer.id: c.peer.avatarUser,
      for (final u in found) u.id: u,
    };
    final q = search.text.toLowerCase().trim().replaceFirst('@', '');
    return map.values
        .where(
          (u) =>
              u.id != accounts.user?.id &&
              !widget.existingIds.contains(u.id) &&
              (q.isEmpty ||
                  u.displayName.toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q)),
        )
        .toList();
  }

  void changed(String value) {
    debounce?.cancel();
    final rev = ++queryRevision;
    setState(() => searching = value.trim().length >= 2);
    if (value.trim().length < 2) return;
    debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final rows = await accounts.search(value);
        if (current && rev == queryRevision) setState(() => found = rows);
      } on AccountFailure catch (e) {
        if (current && rev == queryRevision) setState(() => error = e.message);
      } finally {
        if (current && rev == queryRevision) setState(() => searching = false);
      }
    });
  }

  Future<void> submit() async {
    if (busy || loading || !storageReady) return;
    if (selected.length < (adding ? 1 : 2) ||
        !adding && name.text.trim().isEmpty) {
      setState(
        () => error = adding
            ? 'اختر عضوًا على الأقل.'
            : 'اكتب اسم المجموعة واختر عضوين على الأقل.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!adding && !frozen) {
        final data = {
          'requestId': nonce,
          'title': name.text.trim(),
          'members': [
            for (final u in selected.values)
              {
                'id': u.id,
                'username': u.username,
                'displayName': u.displayName,
                'avatarPreset': u.avatarPreset,
              },
          ],
        };
        if (owner == null ||
            !await accounts.draftStore.write(
              owner!,
              scope,
              data,
              valid: () => current,
            ))
          throw const AccountFailure(
            'DRAFT_WRITE',
            'تعذّر حفظ الطلب؛ لم تُنشأ المجموعة.',
          );
        frozen = true;
      }
      late final DirectConversation c;
      if (adding) {
        final d = await accounts.chatRequest(
          'PUT',
          '/v1/groups/${widget.group!.id}/members',
          body: {'memberIds': selected.keys.toList()},
        );
        if (!current) return;
        c = DirectConversation.fromJson(
          d['conversation'] as Map<String, dynamic>,
        );
        widget.chats.update(c);
      } else {
        c = await widget.chats.createGroup(
          name.text.trim(),
          selected.keys.toList(),
          nonce,
        );
        if (!current) return;
        await accounts.draftStore.write(
          owner!,
          scope,
          null,
          valid: () => current,
        );
      }
      if (current) Navigator.pop(context, c);
    } on AccountFailure catch (e) {
      if (current) setState(() => error = e.message);
    } catch (_) {
      if (current)
        setState(
          () => error = 'تعذّر إكمال الطلب. أعد المحاولة؛ بياناته محفوظة.',
        );
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> cancelSavedRequest() async {
    if (busy || owner == null) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء الطلب المحفوظ؟'),
        content: const Text(
          'إذا أُنشئت المجموعة تبقى في قائمتك. هذا الخيار يتيح لك بدء طلب جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (clear != true || !current) return;
    setState(() => busy = true);
    try {
      if (!await accounts.draftStore.write(
        owner!,
        scope,
        null,
        valid: () => current,
      ))
        return;
      if (current)
        setState(() {
          frozen = false;
          nonce = newRequestId();
          selected.clear();
          name.clear();
          error = null;
        });
    } catch (_) {
      if (current) setState(() => error = 'تعذّر إلغاء الطلب؛ بقي محفوظًا.');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    name.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return ChatSurface(
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: busy ? null : () => Navigator.maybePop(context),
            ),
            actions: [
              if (frozen && !busy)
                IconButton(
                  tooltip: 'إلغاء الطلب المحفوظ',
                  onPressed: cancelSavedRequest,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
            ],
            title: Text(
              adding ? 'إضافة أعضاء' : 'مجموعة جديدة',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                      sliver: SliverList.list(
                        children: [
                          if (!adding) ...[
                            Center(
                              child: CircleAvatar(
                                radius: 34,
                                backgroundColor: p.accent.withValues(
                                  alpha: .14,
                                ),
                                child: Icon(
                                  Icons.groups_rounded,
                                  size: 38,
                                  color: p.accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              key: const Key('group-name'),
                              controller: name,
                              enabled: !busy && !frozen,
                              maxLength: 60,
                              decoration: const InputDecoration(
                                hintText: 'اسم المجموعة',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          Text(
                            '${selected.length} ${adding ? 'أعضاء محددون' : 'من29 عضوًا'}',
                            style: TextStyle(color: p.muted),
                          ),
                          const SizedBox(height: 8),
                          if (selected.isNotEmpty)
                            Wrap(
                              spacing: 7,
                              runSpacing: 6,
                              children: [
                                for (final u in selected.values)
                                  InputChip(
                                    label: Text(u.displayName),
                                    avatar: AccountAvatar(u, size: 24),
                                    onDeleted: busy || frozen
                                        ? null
                                        : () => setState(
                                            () => selected.remove(u.id),
                                          ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('group-member-search'),
                            controller: search,
                            onChanged: changed,
                            enabled: !busy && !frozen,
                            decoration: const InputDecoration(
                              hintText: 'ابحث بالاسم أو اليوزر',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                          if (searching)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (frozen && !busy)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'طلبك محفوظ بنفس البيانات؛ أعد المحاولة لإكماله.',
                                style: TextStyle(color: p.muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (choices.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'ابحث باليوزر لإضافة أشخاص إلى المجموعة.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, i) {
                        final u = choices[i],
                            checked = selected.containsKey(u.id);
                        return CheckboxListTile(
                          key: ValueKey('group-member-${u.id}'),
                          value: checked,
                          onChanged: busy || frozen
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    if (selected.length >= 29) {
                                      error = 'المجموعة حتى30 شخصًا معك.';
                                      return;
                                    }
                                    selected[u.id] = u;
                                  } else
                                    selected.remove(u.id);
                                }),
                          secondary: AccountAvatar(u, size: 44),
                          title: Text(
                            u.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '@${u.username}',
                            textDirection: TextDirection.ltr,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const Key('group-create-submit'),
                onPressed: busy || loading
                    ? null
                    : !storageReady
                    ? () async {
                        setState(() {
                          loading = true;
                          storageReady = true;
                        });
                        await restore();
                      }
                    : submit,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        adding
                            ? Icons.person_add_alt_1_rounded
                            : Icons.check_rounded,
                      ),
                label: Text(
                  !storageReady
                      ? 'إعادة قراءة الطلب'
                      : busy
                      ? 'جارٍ الإكمال…'
                      : adding
                      ? 'إضافة الأعضاء'
                      : 'إنشاء المجموعة',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.chats,
    required this.conversation,
  });
  final ChatController chats;
  final DirectConversation conversation;
  @override
  State<GroupInfoPage> createState() => _GroupInfoState();
}

class _GroupInfoState extends State<GroupInfoPage> {
  late DirectConversation conversation = widget.conversation;
  List<AccountUser> users = [];
  bool busy = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final d = await widget.chats.accounts.chatRequest(
        'GET',
        '/v1/groups/${conversation.id}/members',
      );
      if (!mounted) return;
      setState(() {
        conversation = DirectConversation.fromJson(
          d['conversation'] as Map<String, dynamic>,
        );
        users = (d['users'] as List)
            .map(
              (u) => PostAuthor.fromJson(u as Map<String, dynamic>).avatarUser,
            )
            .toList();
        loading = false;
        error = null;
      });
    } on AccountFailure catch (e) {
      if (mounted)
        setState(() {
          error = e.message;
          loading = false;
        });
    }
  }

  Future<void> remove(String uid) async {
    if (busy) return;
    final own = uid == widget.chats.accounts.user?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(own ? 'مغادرة المجموعة؟' : 'إزالة العضو؟'),
        content: Text(
          own
              ? 'تتوقف عن استقبال رسائلها. تنتقل الملكية لعضو آخر إذا كنت المالك.'
              : 'لن يستطيع قراءة الرسائل الجديدة أو إرسالها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(own ? 'مغادرة' : 'إزالة'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.chats.accounts.chatRequest(
        'DELETE',
        '/v1/groups/${conversation.id}/members/$uid',
      );
      if (own) {
        widget.chats.removeConversation(conversation.id);
        if (mounted) Navigator.pop(context, true);
      } else
        await load();
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return ChatSurface(
      child: Scaffold(
        appBar: AppBar(title: const Text('معلومات المجموعة')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundColor: p.accent.withValues(alpha: .15),
                child: Icon(Icons.groups_rounded, size: 46, color: p.accent),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              conversation.peer.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${conversation.memberCount} أعضاء',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted),
            ),
            const SizedBox(height: 24),
            if (error != null) TextButton(onPressed: load, child: Text(error!)),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (conversation.isOwner)
              ListTile(
                key: const Key('group-add-members'),
                leading: Icon(Icons.person_add_alt_1_rounded, color: p.accent),
                title: const Text('إضافة أعضاء'),
                onTap: busy
                    ? null
                    : () async {
                        await Navigator.push<DirectConversation>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupCreatePage(
                              chats: widget.chats,
                              group: conversation,
                              existingIds: users.map((u) => u.id).toSet(),
                            ),
                          ),
                        );
                        if (mounted) await load();
                      },
              ),
            for (final u in users)
              ListTile(
                leading: AccountAvatar(u, size: 44),
                title: Text(u.displayName),
                subtitle: Text(
                  '@${u.username}',
                  textDirection: TextDirection.ltr,
                ),
                trailing: u.id == conversation.ownerId
                    ? Chip(
                        label: Text(
                          'المالك',
                          style: TextStyle(color: p.accent, fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    : conversation.isOwner
                    ? IconButton(
                        tooltip: 'إزالة العضو',
                        onPressed: busy ? null : () => remove(u.id),
                        icon: const Icon(Icons.person_remove_outlined),
                      )
                    : null,
              ),
            const Divider(height: 32),
            ListTile(
              key: const Key('group-leave'),
              leading: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'مغادرة المجموعة',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: busy ? null : () => remove(widget.chats.accounts.user!.id),
            ),
          ],
        ),
      ),
    );
  }
}
