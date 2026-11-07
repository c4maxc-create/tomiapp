import '../accounts/external_auth_ui.dart';
import '../accounts/account_api.dart';
import 'security_page.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_profile.dart';
import '../accounts/account_widgets.dart';
import '../design/async_content.dart';
import '../social/post_share_screens.dart';
import '../social/social_models.dart';
import '../voice_rooms/room_screens.dart';
import '../voice_rooms/room_models.dart';
import '../widgets.dart';

class UnifiedSearchPage extends StatefulWidget {
  const UnifiedSearchPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<UnifiedSearchPage> createState() => _UnifiedSearchPageState();
}

class _UnifiedSearchPageState extends State<UnifiedSearchPage> {
  final input = TextEditingController();
  Timer? timer;
  int generation = 0;
  bool busy = false;
  String? error;
  String scope = 'all';
  Map<String, dynamic> result = {};
  void search(String q) {
    timer?.cancel();
    final gen = ++generation;
    setState(() {
      busy = q.trim().length >= 2;
      error = null;
      result = {};
    });
    if (!busy) return;
    timer = Timer(const Duration(milliseconds: 280), () async {
      try {
        final r = await widget.accounts.chatRequest(
          'GET',
          '/v1/search',
          query: {'q': q.trim()},
        );
        if (mounted && gen == generation) setState(() => result = r);
      } catch (_) {
        if (mounted && gen == generation)
          setState(() => error = 'تعذّر البحث؛ أعد المحاولة.');
      } finally {
        if (mounted && gen == generation) setState(() => busy = false);
      }
    });
  }

  Future<void> room(String id) async {
    try {
      final c = widget.accounts.voiceRooms;
      if (c.active?.id == id) {
        c.expand();
      } else {
        final data = await widget.accounts.chatRequest('GET', '/v1/rooms/$id'),
            r = VoiceRoom(data['room'] as Map<String, dynamic>);
        String? password;
        if (r.passwordRequired && r.ownerId != widget.accounts.user?.id) {
          if (!mounted) return;
          var value = '';
          password = await showDialog<String>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('كلمة مرور الغرفة'),
              content: TextField(
                obscureText: true,
                maxLength: 64,
                onChanged: (v) => value = v,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('رجوع'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(d, value),
                  child: const Text('دخول'),
                ),
              ],
            ),
          );
          if (password == null) return;
        }
        if (!await c.join(id, password: password)) {
          if (mounted) showNote(context, c.error ?? 'تعذّر دخول الغرفة.');
          return;
        }
      }
      if (mounted)
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => VoiceRoomPage(controller: c)),
        );
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر فتح الغرفة؛ أعد المحاولة.');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = (result['users'] as List? ?? []),
        rooms = (result['rooms'] as List? ?? []),
        posts = (result['posts'] as List? ?? []);
    return Scaffold(
      appBar: AppBar(title: const Text('بحث TOMI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('account-search-input'),
            controller: input,
            onChanged: search,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'أشخاص، غرف، منشورات…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final e in {
                'all': 'الكل',
                'users': 'أشخاص',
                'rooms': 'غرف',
                'posts': 'منشورات',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: scope == e.key,
                  onSelected: (_) => setState(() => scope = e.key),
                ),
            ],
          ),
          if (busy) const TomiSkeleton(),
          if (error != null)
            TomiRetry(message: error!, retry: () => search(input.text)),
          if (!busy &&
              error == null &&
              input.text.trim().length >= 2 &&
              users.isEmpty &&
              rooms.isEmpty &&
              posts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'ما لقينا نتائج. جرّب كلمات ثانية.',
                textAlign: TextAlign.center,
              ),
            ),
          if (scope == 'all' || scope == 'users') ...[
            if (users.isNotEmpty) const ListTile(title: Text('الأشخاص')),
            for (final d in users)
              Builder(
                builder: (c) {
                  final u = AccountUser.fromJson(
                    (d as Map).cast<String, dynamic>(),
                  );
                  return ListTile(
                    leading: AccountAvatar(u, size: 42),
                    title: Text(u.displayName),
                    subtitle: Text('@${u.username}'),
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute<void>(
                        builder: (_) => UserAccountPage(
                          accounts: widget.accounts,
                          initialUser: u,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
          if (scope == 'all' || scope == 'rooms') ...[
            if (rooms.isNotEmpty) const ListTile(title: Text('الغرف الصوتية')),
            for (final d in rooms)
              ListTile(
                leading: const Icon(Icons.headphones),
                title: Text(d['title'] as String),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => room(d['id'] as String),
              ),
          ],
          if (scope == 'all' || scope == 'posts') ...[
            if (posts.isNotEmpty)
              const ListTile(title: Text('المنشورات العامة')),
            for (final d in posts)
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(
                  d['text'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  (d['author'] as Map?)?['displayName'] as String? ?? '',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SharedPostPage(
                      accounts: widget.accounts,
                      postId: d['id'] as String,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class SessionSecurityPage extends StatefulWidget {
  const SessionSecurityPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<SessionSecurityPage> createState() => _SessionSecurityPageState();
}

class _SessionSecurityPageState extends State<SessionSecurityPage> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load(label: true));
  }

  Future<void> load({bool label = false}) async {
    setState(() => busy = true);
    try {
      final platform = kIsWeb
          ? 'web'
          : ['android', 'ios'].contains(Platform.operatingSystem)
          ? Platform.operatingSystem
          : 'desktop';
      final d = await widget.accounts.chatRequest(
        label ? 'PUT' : 'GET',
        label ? '/v1/me/sessions/current' : '/v1/me/sessions',
        body: label
            ? {'label': 'TOMI • $platform', 'platform': platform}
            : null,
      );
      if (mounted)
        setState(() {
          rows = (d['sessions'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل الأجهزة.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(String? id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          id == null ? 'تسجيل خروج الأجهزة الأخرى؟' : 'تسجيل خروج هذا الجهاز؟',
        ),
        content: const Text(
          'يحتاج الجهاز تسجيل الدخول مجددًا، وتنتهي اتصالاته الحالية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.accounts.chatRequest(
        id == null ? 'POST' : 'DELETE',
        id == null ? '/v1/me/sessions/revoke-others' : '/v1/me/sessions/$id',
      );
      await load();
    } catch (failure) {
      if (mounted)
        setState(() {
          busy = false;
          error = failure is AccountFailure
              ? failure.message
              : 'تعذّر إنهاء الجلسة؛ أعد المحاولة.';
        });
    }
  }

  String time(dynamic v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    return d == null
        ? ''
        : '${d.year}/${d.month}/${d.day} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الأجهزة وأمان الحساب')),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('طرق الدخول وربط الحساب'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AuthMethodsPage(accounts: widget.accounts),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('التحقق بخطوتين وسجل الأمان'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SecurityProtectionPage(accounts: widget.accounts),
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('أجهزتك المسجّلة'),
            subtitle: Text(
              'راجع وقت الدخول وآخر استخدام، وأوقف أي جهاز ما تعرفه.',
            ),
          ),
          if (busy && rows.isEmpty) const TomiSkeleton(),
          if (error != null) TomiRetry(message: error!, retry: load),
          for (final r in rows)
            Card(
              child: ListTile(
                isThreeLine: true,
                leading: Icon(
                  r['platform'] == 'desktop'
                      ? Icons.computer
                      : Icons.smartphone,
                ),
                title: Text(
                  '${r['label']}${r['current'] == true ? ' • هذا الجهاز' : ''}',
                ),
                subtitle: Text(
                  'دخول: ${time(r['createdAt'])}\nآخر استخدام: ${time(r['lastSeenAt'])}',
                ),
                trailing: r['current'] == true
                    ? const Icon(Icons.check_circle_outline)
                    : IconButton(
                        tooltip: 'تسجيل خروج الجهاز',
                        onPressed: busy
                            ? null
                            : () => revoke(r['id'] as String),
                        icon: const Icon(Icons.logout),
                      ),
              ),
            ),
          if (rows.any((r) => r['current'] != true))
            OutlinedButton.icon(
              onPressed: busy ? null : () => revoke(null),
              icon: const Icon(Icons.devices),
              label: const Text('تسجيل خروج الأجهزة الأخرى'),
            ),
        ],
      ),
    ),
  );
}

class SavedCollectionsPage extends StatefulWidget {
  const SavedCollectionsPage({super.key, required this.accounts, this.postId});
  final AccountController accounts;
  final String? postId;
  @override
  State<SavedCollectionsPage> createState() => _SavedCollectionsPageState();
}

class _SavedCollectionsPageState extends State<SavedCollectionsPage> {
  List<Map<String, dynamic>> rows = [], posts = [];
  bool busy = false;
  int generation = 0;
  String? error, id, name, cursor, pendingId, pendingName;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    final gen = ++generation, target = id;
    setState(() => busy = true);
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        target == null ? '/v1/me/collections' : '/v1/me/collections/$target',
        query: more && cursor != null ? {'before': cursor!} : null,
      );
      if (mounted && gen == generation)
        setState(() {
          if (target == null)
            rows = (d['collections'] as List)
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
          else {
            final items = (d['posts'] as List)
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList();
            posts = more ? [...posts, ...items] : items;
            cursor = d['nextCursor'] as String?;
          }
          error = null;
        });
    } catch (_) {
      if (mounted && gen == generation)
        setState(() => error = 'تعذّر تحميل المجموعة؛ أعد المحاولة.');
    } finally {
      if (mounted && gen == generation) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    if (busy) return;
    if (pendingName == null) {
      var value = '';
      final n = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('مجموعة جديدة'),
          content: TextField(
            maxLength: 40,
            onChanged: (v) => value = v,
            decoration: const InputDecoration(hintText: 'اسم المجموعة'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, value.trim()),
              child: const Text('إنشاء'),
            ),
          ],
        ),
      );
      if (n == null || n.isEmpty) return;
      pendingName = n;
      pendingId = newRequestId();
    }
    setState(() => busy = true);
    try {
      await widget.accounts.chatRequest(
        'POST',
        '/v1/me/collections',
        body: {'id': pendingId, 'name': pendingName},
      );
      pendingName = null;
      pendingId = null;
      await load();
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = 'تعذّر تأكيد الإنشاء؛ أعد المحاولة لنفس المجموعة.';
        });
    }
  }

  Future<void> select(Map<String, dynamic> r) async {
    if (widget.postId != null) {
      setState(() => busy = true);
      try {
        await widget.accounts.chatRequest(
          'PUT',
          '/v1/me/collections/${r['id']}/posts/${widget.postId}',
        );
        if (mounted) {
          showNote(context, 'تمت إضافة المنشور للمجموعة.');
          Navigator.pop(context);
        }
      } catch (_) {
        if (mounted)
          setState(() {
            busy = false;
            error = 'احفظ المنشور أولًا، ثم جرّب الإضافة مجددًا.';
          });
      }
    } else {
      setState(() {
        id = r['id'] as String;
        name = r['name'] as String;
        posts = [];
      });
      await load();
    }
  }

  Future<void> removePost(String post) async {
    try {
      await widget.accounts.chatRequest(
        'DELETE',
        '/v1/me/collections/$id/posts/$post',
      );
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّرت الإزالة.');
    }
  }

  Future<void> deleteCollection(Map<String, dynamic> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف المجموعة؟'),
        content: const Text('تبقى المنشورات محفوظة في المحفوظات العامة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      try {
        await widget.accounts.chatRequest(
          'DELETE',
          '/v1/me/collections/${r['id']}',
        );
        await load();
      } catch (_) {
        if (mounted)
          setState(() => error = 'تعذّر حذف المجموعة؛ أعد المحاولة.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        name ??
            (widget.postId == null ? 'مجموعات المحفوظات' : 'أضف إلى مجموعة'),
      ),
      leading: id == null
          ? null
          : IconButton(
              onPressed: () {
                setState(() {
                  id = null;
                  name = null;
                  posts = [];
                });
                unawaited(load());
              },
              icon: const Icon(Icons.arrow_back),
            ),
      actions: [
        if (id == null)
          IconButton(
            tooltip: 'مجموعة جديدة',
            onPressed: busy ? null : create,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const TomiSkeleton(rows: 2),
        if (error != null)
          TomiRetry(
            message: error!,
            retry: pendingName != null ? create : load,
          ),
        if (id == null) ...[
          if (rows.isEmpty && !busy)
            const ListTile(
              title: Text('رتّب منشوراتك المحفوظة بمجموعات'),
              subtitle: Text('اضغط علامة المجموعة بالأعلى لإنشاء أول مجموعة.'),
            ),
          for (final r in rows)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(r['name'] as String),
              subtitle: Text('${r['count']} منشور'),
              onTap: busy ? null : () => select(r),
              trailing: widget.postId == null
                  ? IconButton(
                      tooltip: 'حذف المجموعة',
                      onPressed: busy ? null : () => deleteCollection(r),
                      icon: const Icon(Icons.delete_outline),
                    )
                  : const Icon(Icons.add),
            ),
        ] else ...[
          if (posts.isEmpty && !busy) const Text('هذه المجموعة فارغة.'),
          for (final p in posts)
            ListTile(
              title: Text(
                (p['text'] as String).isEmpty
                    ? 'منشور وسائط'
                    : p['text'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SharedPostPage(
                    accounts: widget.accounts,
                    postId: p['id'] as String,
                  ),
                ),
              ),
              trailing: IconButton(
                tooltip: 'إزالة من المجموعة',
                onPressed: () => removePost(p['id'] as String),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ),
          if (cursor != null)
            TextButton(
              onPressed: busy ? null : () => load(more: true),
              child: const Text('المزيد'),
            ),
        ],
      ],
    ),
  );
}
