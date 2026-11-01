import 'dart:async';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_api.dart';
import '../accounts/account_widgets.dart';
import '../identity/charisma_badge.dart';
import '../messaging/chat_models.dart';
import '../messaging/chat_screens.dart' show PrivateChatPage;
import '../widgets.dart';
import 'social_models.dart';
import 'social_screens.dart' show RealPostCard;

Future<void> showPostShareSheet(BuildContext context, AccountController accounts, String postId) async {
  final message = await showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, useSafeArea: true,
    builder: (sheetContext) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom), child: SizedBox(height: MediaQuery.sizeOf(sheetContext).height * .72, child: PostShareSheet(accounts: accounts, postId: postId))));
  if (context.mounted && message != null) showNote(context, message);
}
class _ShareContactsCache {
  const _ShareContactsCache(this.userId, this.session, this.users, this.cursor, this.at);
  final String userId;
  final int session;
  final List<AccountUser> users;
  final String? cursor;
  final DateTime at;
}
final _shareContacts = Expando<_ShareContactsCache>();

class PostShareSheet extends StatefulWidget {
  const PostShareSheet({super.key, required this.accounts, required this.postId});
  final AccountController accounts;
  final String postId;
  @override
  State<PostShareSheet> createState() => _PostShareSheetState();
}
class _PostShareSheetState extends State<PostShareSheet> {
  final input = TextEditingController(), nonces = <String,String>{};
  List<AccountUser> users = [];
  Timer? debounce;
  String? cursor, error, sending;
  int epoch = 0;
  bool loading = true;
  late final userId = widget.accounts.user?.id ?? '';
  late final session = widget.accounts.sessionRevision;
  bool get current => mounted && userId.isNotEmpty && widget.accounts.user?.id == userId && widget.accounts.sessionRevision == session;
  @override
  void initState() {
    super.initState();
    widget.accounts.addListener(accountChanged);
    final cached = _shareContacts[widget.accounts];
    if (cached != null && cached.userId == userId && cached.session == session && DateTime.now().difference(cached.at).inSeconds < 30) {
      users = cached.users; cursor = cached.cursor; loading = false;
    }
    unawaited(load());
  }
  @override
  void dispose() { epoch++; widget.accounts.removeListener(accountChanged); debounce?.cancel(); input.dispose(); super.dispose(); }
  void accountChanged() {
    if (!mounted || current) return;
    debounce?.cancel(); epoch++; _shareContacts[widget.accounts] = null;
    setState(() {users = []; cursor = null; loading = false; sending = null; error = 'انتهت جلسة الحساب؛ أغلق المشاركة وسجّل الدخول مجددًا.';});
  }
  void changed(String text) { if (!current) return; debounce?.cancel(); epoch++; debounce = Timer(const Duration(milliseconds: 300), () => load()); }
  Future<void> load({bool more = false}) async {
    if (!current) return;
    final mine = ++epoch, q = input.text.trim();
    setState(() { loading = true; error = null; });
    try {
      List<AccountUser> result;
      String? next;
      if (q.isEmpty) {
        final d = await widget.accounts.chatRequest('GET','/v1/post-shares/contacts',query: more && cursor != null ? {'cursor':cursor!} : null);
        result = (d['users'] as List).map((u) => AccountUser.fromJson((u as Map).cast<String,dynamic>())).toList(); next = d['nextCursor'] as String?;
      } else if (q.replaceFirst('@','').runes.length >= 2) { result = (await widget.accounts.search(q)).where((u) => u.id != userId).toList(); }
      else { result = []; }
      if (!current || mine != epoch) return;
      setState(() { users = more ? [...users,...result.where((u) => !users.any((v) => v.id == u.id))] : result; cursor = next; });
      if (q.isEmpty) _shareContacts[widget.accounts] = _ShareContactsCache(userId, session, List<AccountUser>.unmodifiable(users), cursor, DateTime.now());
    } on AccountFailure catch (f) { if (current && mine == epoch) setState(() => error = f.message); }
    catch (_) { if (current && mine == epoch) setState(() => error = 'تعذّر تحميل الأشخاص؛ حاول مجددًا.'); }
    finally { if (current && mine == epoch) setState(() => loading = false); }
  }
  Future<void> send(AccountUser user) async {
    if (!current || sending != null) return;
    setState(() { sending = user.id; error = null; });
    try {
      final d = await widget.accounts.chatRequest('POST','/v1/posts/${widget.postId}/share',body: {'requestId':nonces.putIfAbsent(user.id,newRequestId),'userId':user.id});
      if (!current) return;
      unawaited(widget.accounts.chats.refresh());
      Navigator.pop(context,d['status'] == 'pending' ? 'وصلت المشاركة إلى طلبات الغرباء، وبانتظار قبول الشخص.' : 'تم إرسال المنشور إلى ${user.displayName}.');
    } on AccountFailure catch (f) { if (current) setState(() => error = f.message); }
    catch (_) { if (current) setState(() => error = 'تعذّر تأكيد الإرسال؛ اضغط الشخص نفسه لإعادة المحاولة.'); }
    finally { if (current) setState(() => sending = null); }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    SizedBox(height: 48, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
      const Icon(Icons.send_outlined, color: TomiColors.accent, size: 20),
      const SizedBox(width: 10),
      const Expanded(child: Text('مشاركة المنشور', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19,fontWeight: FontWeight.w800))),
      IconButton(tooltip: 'إغلاق', onPressed: sending == null ? () => Navigator.pop(context) : null, icon: const Icon(Icons.close_rounded)),
    ]))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: TextField(
      key: const Key('post-share-search'), controller: input, enabled: sending == null && current, onChanged: changed,
      decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'الاسم أو اسم المستخدم',
        suffixIcon: input.text.isEmpty ? null : IconButton(tooltip: 'مسح البحث', onPressed: sending == null ? () {input.clear(); changed('');} : null, icon: const Icon(Icons.close_rounded))),
    )),
    SizedBox(height: 6, child: loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink()),
    Expanded(child: ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: users.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return Padding(padding: const EdgeInsets.fromLTRB(16,8,16,10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('متابعوك ومن تتابعهم', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('تصل المشاركة إلى الدردشة. الغريب يستلم طلبًا ينتظر قبوله.', style: TextStyle(fontSize: 12,color: TomiColors.muted)),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10),child: AccountErrorMessage(error!)),
        ]));
        if (index == users.length + 1) return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          if (users.isEmpty && !loading) Text(input.text.isEmpty ? 'ابحث عن شخص لمشاركة المنشور معه.' : 'لا توجد نتائج؛ جرّب اسمًا من حرفين أو أكثر.', style: const TextStyle(color: TomiColors.muted)),
          if (cursor != null) TextButton(onPressed: loading ? null : () => load(more: true),child: const Text('عرض المزيد')),
          if (error != null) TextButton(onPressed: loading ? null : load,child: const Text('إعادة تحميل القائمة')),
        ]));
        final u = users[index - 1];
        return ListTile(
          key: ValueKey('share-person-${u.id}'), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
          leading: AccountAvatar(u,size: 44),
          title: Text(u.displayName,maxLines: 1,overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [Text('@${u.username}',maxLines: 1,overflow: TextOverflow.ellipsis,style: const TextStyle(color: TomiColors.muted,fontSize: 12)),CharismaBadge(u.identity)]),
          trailing: SizedBox(width: 26,height: 26,child: sending == u.id ? const Padding(padding: EdgeInsets.all(4),child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded,color: TomiColors.accent,size: 21)),
          onTap: sending == null && current ? () => send(u) : null,
        );
      },
    )),
  ]);
}

class PostShareRequestsPage extends StatefulWidget {
  const PostShareRequestsPage({super.key,required this.accounts});
  final AccountController accounts;
  @override
  State<PostShareRequestsPage> createState() => _PostShareRequestsPageState();
}
class _PostShareRequestsPageState extends State<PostShareRequestsPage> {
  List<Map<String,dynamic>> items = [];
  final nonces = <String,String>{};
  String? cursor,error,busyId;
  bool loading = false;
  int epoch = 0;
  late final uid = widget.accounts.user?.id ?? '';
  late final session = widget.accounts.sessionRevision;
  bool get current => mounted && uid.isNotEmpty && widget.accounts.user?.id == uid && widget.accounts.sessionRevision == session;
  @override
  void initState() { super.initState(); widget.accounts.addListener(accountChanged); unawaited(load()); }
  @override
  void dispose() { epoch++; widget.accounts.removeListener(accountChanged); super.dispose(); }
  void accountChanged() {
    if (!mounted || current) return;
    epoch++; nonces.clear();
    setState(() {items = []; cursor = null; loading = false; busyId = null; error = 'انتهت جلسة الحساب؛ سجّل الدخول مجددًا.';});
  }
  Future<void> load({bool more = false}) async {
    if (!current || loading) return; final mine = ++epoch; setState(() { loading = true; error = null; });
    try {
      final d = await widget.accounts.chatRequest('GET','/v1/post-shares/requests',query: more && cursor != null ? {'cursor':cursor!} : null);
      if (!current || mine != epoch) return;
      final rows = (d['items'] as List).map((r) => (r as Map).cast<String,dynamic>()).toList();
      setState(() { items = more ? [...items,...rows.where((r) => !items.any((v) => v['id'] == r['id']))] : rows; cursor = d['nextCursor'] as String?; });
    } on AccountFailure catch (f) { if (current && mine == epoch) setState(() => error = f.message); }
    catch (_) { if (current && mine == epoch) setState(() => error = 'تعذّر تحميل الطلبات.'); }
    finally { if (current && mine == epoch) setState(() => loading = false); }
  }
  Future<void> act(String id,String action) async {
    if (!current || busyId != null) return; setState(() { busyId = id; error = null; epoch++; loading = false; });
    try {
      final d = await widget.accounts.chatRequest('POST','/v1/post-shares/requests/$id',body: {'action':action,'requestId':nonces.putIfAbsent('$id:$action',newRequestId)});
      if (!current) return;
      await widget.accounts.chats.refresh(); if (!current) return;
      await load(); if (!current) return;
      if (d['conversationId'] != null) {
        final thread = await widget.accounts.chatRequest('GET','/v1/chats/${d['conversationId']}'); if (!current) return;
        await Navigator.push<void>(context,MaterialPageRoute(builder: (_) => PrivateChatPage(chats: widget.accounts.chats,conversation: DirectConversation.fromJson((thread['conversation'] as Map).cast<String,dynamic>()))));
      }
    } on AccountFailure catch (f) { if (current) setState(() => error = f.message); }
    catch (_) { if (current) setState(() => error = 'تعذّر تأكيد الإجراء؛ يمكنك إعادة المحاولة نفسها.'); }
    finally { if (current) setState(() => busyId = null); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('طلبات الغرباء'),actions: [IconButton(tooltip: 'تحديث',onPressed: loading || busyId != null ? null : load,icon: const Icon(Icons.refresh))]),body: ListView(padding: const EdgeInsets.all(14),children: [
    if (loading) const LinearProgressIndicator(),
    if (error != null) AccountErrorMessage(error!),
    if (items.isEmpty && !loading) const Padding(padding: EdgeInsets.all(28),child: Text('لا توجد طلبات مشاركة جديدة.')),
    for (final r in items) Padding(padding: const EdgeInsets.only(bottom: 12),child: TomiCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      ListTile(contentPadding: EdgeInsets.zero,leading: AccountAvatar(AccountUser.fromJson((r['sender'] as Map).cast<String,dynamic>()),size: 44),title: Text('${r['sender']['displayName']}'),subtitle: Text('@${r['sender']['username']}')),
      Text('${r['text']}',maxLines: 4,overflow: TextOverflow.ellipsis),
      const SizedBox(height: 12),
      Wrap(spacing: 12,runSpacing: 8,children: [FilledButton.icon(key: ValueKey('accept-share-${r['id']}'),onPressed: busyId == null ? () => act(r['id'] as String,'accept') : null,icon: const Icon(Icons.check),label: const Text('قبول')),OutlinedButton.icon(key: ValueKey('block-share-${r['id']}'),onPressed: busyId == null ? () => act(r['id'] as String,'block') : null,icon: const Icon(Icons.block),label: const Text('حظر المرسل')),if (busyId == r['id']) const SizedBox(width: 20,height: 20,child: CircularProgressIndicator(strokeWidth: 2))]),
    ]))),
    if (cursor != null) TextButton(onPressed: loading || busyId != null ? null : () => load(more: true),child: const Text('المزيد')),
  ]));
}

class SharedPostPage extends StatefulWidget {
  const SharedPostPage({super.key,required this.accounts,required this.postId});
  final AccountController accounts;
  final String postId;
  @override
  State<SharedPostPage> createState() => _SharedPostPageState();
}
class _SharedPostPageState extends State<SharedPostPage> {
  SocialPost? post;
  String? error;
  bool busy = false;
  late final uid = widget.accounts.user?.id ?? '';
  late final session = widget.accounts.sessionRevision;
  bool get current => mounted && uid.isNotEmpty && widget.accounts.user?.id == uid && widget.accounts.sessionRevision == session;
  @override
  void initState() { super.initState(); unawaited(load()); }
  Future<void> load() async {
    try { final d = await widget.accounts.chatRequest('GET','/v1/posts/${widget.postId}'); if (current) setState(() {post = SocialPost.fromJson((d['post'] as Map).cast<String,dynamic>()); error = null;}); }
    on AccountFailure catch(f) {if(current)setState(()=>error=f.message);} catch(_){if(current)setState(()=>error='المنشور غير متاح حاليًا.');}
  }
  Future<void> like() async {
    if (!current || busy || post == null) return; setState(()=>busy=true);
    try {final p = await widget.accounts.likePost(post!.id,!post!.liked);if(current)setState(()=>post=p);}
    catch(_){if(current)showNote(context,'تعذّر تحديث الإعجاب.');}finally{if(current)setState(()=>busy=false);}
  }
  Future<void> remove() async {
    if (!current) return;
    try {await widget.accounts.deletePost(widget.postId);if(current)Navigator.pop(context);}catch(_){if(current)showNote(context,'تعذّر حذف المنشور.');}
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('المنشور')),body: ListView(children: [
    if(error!=null)Padding(padding: const EdgeInsets.all(20),child: AccountErrorMessage(error!)),
    if(post==null && error==null)const LinearProgressIndicator(),
    if(post!=null)RealPostCard(accounts: widget.accounts,post: post!,busy: busy,onLike: like,onDelete: remove,onUpdated:(p){if(current)setState(()=>post=p);}),
    if(error!=null)TextButton(onPressed: load,child: const Text('تحديث')),
  ]));
}
