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
  void initState() { super.initState(); unawaited(load()); }
  @override
  void dispose() { epoch++; debounce?.cancel(); input.dispose(); super.dispose(); }
  void changed(String text) { debounce?.cancel(); epoch++; debounce = Timer(const Duration(milliseconds: 300), () => load()); }
  Future<void> load({bool more = false}) async {
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
    } on AccountFailure catch (f) { if (current && mine == epoch) setState(() => error = f.message); }
    catch (_) { if (current && mine == epoch) setState(() => error = 'تعذّر تحميل الأشخاص؛ حاول مجددًا.'); }
    finally { if (current && mine == epoch) setState(() => loading = false); }
  }
  Future<void> send(AccountUser user) async {
    if (sending != null) return;
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
    const Padding(padding: EdgeInsets.all(10),child: Text('مشاركة المنشور',style: TextStyle(fontSize: 21,fontWeight: FontWeight.bold))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16),child: TextField(key: const Key('post-share-search'),controller: input,enabled: sending == null,onChanged: changed,decoration: const InputDecoration(prefixIcon: Icon(Icons.search),hintText: 'ابحث عن أي شخص بالاسم أو اليوزر'))),
    if (loading) const LinearProgressIndicator(),
    Expanded(child: ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(16,10,16,6),child: Text('متابعوك والحسابات التي تتابعها. مشاركة الغريب تصل كطلب يستطيع قبوله أو حظرك.',style: TextStyle(fontSize: 12,color: TomiColors.muted))),
      if (error != null) Padding(padding: const EdgeInsets.all(12),child: AccountErrorMessage(error!)),
      for (final u in users) ListTile(key: ValueKey('share-person-${u.id}'),leading: AccountAvatar(u,size: 42),title: Text(u.displayName),subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [Text('@${u.username}'),CharismaBadge(u.identity)]),trailing: sending == u.id ? const SizedBox(width: 22,height: 22,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),onTap: sending == null ? () => send(u) : null),
      if (users.isEmpty && !loading) const Padding(padding: EdgeInsets.all(24),child: Text('ابحث عن الشخص الذي تريد مشاركة المنشور معه.')),
      if (cursor != null) TextButton(onPressed: loading ? null : () => load(more: true),child: const Text('عرض المزيد')),
      if (error != null) TextButton(onPressed: loading ? null : load,child: const Text('إعادة تحميل القائمة')),
    ])),
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
  void initState() { super.initState(); unawaited(load()); }
  Future<void> load({bool more = false}) async {
    if (loading) return; final mine = ++epoch; setState(() { loading = true; error = null; });
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
    if (busyId != null) return; setState(() { busyId = id; error = null; epoch++; loading = false; });
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
    if (busy || post == null) return; setState(()=>busy=true);
    try {final p = await widget.accounts.likePost(post!.id,!post!.liked);if(current)setState(()=>post=p);}
    catch(_){if(current)showNote(context,'تعذّر تحديث الإعجاب.');}finally{if(current)setState(()=>busy=false);}
  }
  Future<void> remove() async {
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
