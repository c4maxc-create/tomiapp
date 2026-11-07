import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/external_auth_ui.dart';
import '../experience/security_page.dart';
import 'secure_store.dart';

class SecureChatPage extends StatefulWidget {
  const SecureChatPage({
    super.key,
    required this.accounts,
    required this.threadId,
    required this.title,
    this.setupOnly = false,
  });
  final AccountController accounts;
  final String threadId, title;
  final bool setupOnly;
  @override
  State<SecureChatPage> createState() => _SecureChatPageState();
}

class _SecureChatPageState extends State<SecureChatPage>
    with WidgetsBindingObserver {
  late final store = SecureStore.forAccount(widget.accounts);
  final input = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? roster;
  bool busy = false,
      ready = false,
      enabled = false,
      pending = false,
      trustRequired = false;
  String? error;
  Timer? poll;
  StreamSubscription<Map<String, dynamic>>? events;
  XFile? attachment;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy &&
          ready &&
          enabled &&
          !trustRequired &&
          (ModalRoute.of(context)?.isCurrent ?? false))
        unawaited(load());
    });
    events = widget.accounts.chats.realtimeEvents.stream.listen((e) {
      if (e['conversationId'] == widget.threadId && !busy && mounted)
        unawaited(load());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    events?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) unawaited(load());
  }

  String failure(Object e) => e is AccountFailure
      ? e.message
      : e is SecureTrustRequired
      ? 'تغيّرت أجهزة التشفير؛ راجع البصمة قبل المتابعة.'
      : 'تعذّر التحقق أو فك التشفير. لن نعرض رسالة غير موثقة؛ حاول مجدداً.';
  Future<void> load() async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    try {
      final status = await store.status();
      if (mounted) setState(() => ready = status['registered'] == true);
      final r = await store.roster(widget.threadId);
      if (mounted) setState(() => enabled = r['enabled'] == true);
      Map<String, dynamic>? data;
      if (status['registered'] == true && r['enabled'] == true)
        data = await store.sync(widget.threadId);
      if (mounted)
        setState(() {
          ready = status['registered'] == true;
          roster = r;
          enabled = r['enabled'] == true;
          trustRequired = data?['trustRequired'] == true;
          error = null;
          if (data != null) {
            rows = (data['messages'] as List).cast<Map<String, dynamic>>();
            pending = data['pending'] == true;
          }
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = failure(e);
          trustRequired = e is SecureTrustRequired;
        });
      if (e is SecureTrustRequired)
        try {
          final cached = await store.snapshot(widget.threadId);
          if (mounted) setState(() => rows = cached);
          final r = await store.roster(widget.threadId);
          if (mounted) setState(() => roster = r);
        } catch (_) {}
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enroll() async {
    final password = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تسجيل جهاز التشفير'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'المفاتيح الخاصة تبقى على هذا الجهاز. سجّل الدخول أو أكد كلمة المرور لتسجيله؛ حسابات المزوّدين تؤكّد الدخول من المزوّد.',
              ),
              TextField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور TOMI إن كانت موجودة',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تسجيل الجهاز'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final credential = await sensitiveCredential(
        context,
        widget.accounts,
        password.text,
      );
      await store.enroll(credential);
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> review() async {
    Map<String, dynamic> r;
    try {
      r = await store.roster(widget.threadId);
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
      return;
    }
    if (!mounted) return;
    final devices = (r['devices'] as List).cast<Map<String, dynamic>>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('التحقق من أجهزة المحادثة'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'قارن هذه البصمة مع صديقك بقناة موثوقة خارج TOMI أو وجهاً لوجه. تغيّر الأجهزة يحتاج مراجعة جديدة. تأكيدها بدون مقارنة يعتمد على الثقة بأول استخدام.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '${r['rosterHash']}',
                  textDirection: TextDirection.ltr,
                ),
                const Divider(),
                for (final d in devices)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${d['label']} • ${d['userId'] == widget.accounts.user?.id ? 'جهازي' : 'الطرف الآخر'}',
                    ),
                    subtitle: Text(
                      '${d['id']}',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                const Text(
                  'التشفير يخص الرسائل الجديدة داخل هذه المحادثة الخاصة. السجل السابق والمجموعات ليست مشفرة بهذا المسار. لا نرجع لإرسال نص واضح إذا تعذّر التشفير.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed:
                devices.any((d) => d['userId'] != widget.accounts.user?.id)
                ? () => Navigator.pop(c, true)
                : null,
            child: const Text('تأكيد الأجهزة'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await store.trust(widget.threadId, r);
        if (r['enabled'] != true) await store.enable(widget.threadId);
        if (mounted) setState(() => trustRequired = false);
        await widget.accounts.chats.refreshConversation(widget.threadId);
        await load();
      } catch (e) {
        if (mounted) setState(() => error = failure(e));
      }
    }
  }

  Future<void> send() async {
    if (busy) return;
    final text = input.text, file = attachment;
    if (text.trim().isEmpty && file == null) return;
    String? sendError;
    setState(() => busy = true);
    try {
      await store.send(widget.threadId, text, file: file);
      input.clear();
      attachment = null;
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
      sendError = failure(e);
      if (e is! SecureTrustRequired) pending = true;
      trustRequired = e is SecureTrustRequired;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
    if (mounted && sendError != null) setState(() => error = sendError);
  }

  Future<void> retry() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await store.retry(widget.threadId);
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> discardPending() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إيقاف إعادة الإرسال؟'),
        content: const Text(
          'قد تكون الرسالة وصلت قبل انقطاع التأكيد. هذا يوقف إعادة محاولتها فقط، ولا يحذفها من جهاز الطرف الآخر. لا يتم إرجاع مفاتيح التشفير للخلف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إيقاف المحاولة'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await store.discardPending(widget.threadId);
      pending = false;
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> backup(bool importing) async {
    final password = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(importing ? 'استعادة السجل المشفر' : 'نسخة مشفرة من السجل'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اختر عبارة مرور مستقلة من 20 حرفاً على الأقل واحفظها خارج التطبيق. النسخة تحتوي سجل الرسائل المحفوظة ومفاتيح مرفقاتها؛ لا تعيد مفاتيح أجهزة قديمة ولا تُرجع جلسات التشفير إلى الوراء.',
              ),
              TextField(
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'عبارة مرور النسخة',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      if (importing) {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'نسخة TOMI', extensions: ['tomibak']),
          ],
        );
        if (file != null)
          await store.importHistory(File(file.path), password.text);
      } else {
        final file = await store.exportHistory(password.text);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'نسخة سجل TOMI مشفرة؛ احتفظ بعبارة المرور منفصلة.',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> openAttachment(Map<String, dynamic> a) async {
    if (busy) return;
    setState(() => busy = true);
    File? file;
    try {
      file = await store.decryptAttachment(widget.threadId, a);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${a['name']}'),
          content: const Text(
            'تم التحقق وفك التشفير على جهازك. فتح الملف أو مشاركته مع تطبيق آخر يسلّمه نسخة واضحة؛ افتح فقط ملفات تثق بمرسلها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('فتح أو حفظ'),
            ),
          ],
        ),
      );
      if (yes == true)
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) setState(() => error = failure(e));
    } finally {
      if (file != null) await file.delete().catchError((_) => file!);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text(
            'رسائل خاصة مشفرة من طرف إلى طرف',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'keys') review();
            if (v == 'legacy')
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LegacySecureHistory(
                    accounts: widget.accounts,
                    threadId: widget.threadId,
                  ),
                ),
              );
            if (v == 'export') backup(false);
            if (v == 'import') backup(true);
            if (v == 'mfa')
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SecurityProtectionPage(accounts: widget.accounts),
                ),
              );
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'legacy',
              child: Text('السجل السابق غير المشفر'),
            ),
            PopupMenuItem(value: 'keys', child: Text('بصمة وأجهزة التشفير')),
            PopupMenuItem(value: 'export', child: Text('تصدير سجل مشفر')),
            PopupMenuItem(value: 'import', child: Text('استعادة سجل مشفر')),
            PopupMenuItem(value: 'mfa', child: Text('تأكيد أمان الحساب')),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!ready || !enabled)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.lock_outline, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    'المفاتيح تبقى على الأجهزة. الطرفان يحتاجان نسخة تدعم التشفير وتسجيل جهازهما قبل التفعيل.',
                  ),
                  const SizedBox(height: 12),
                  if (!ready)
                    FilledButton(
                      onPressed: busy ? null : enroll,
                      child: const Text('تسجيل هذا الجهاز'),
                    ),
                  if (ready)
                    FilledButton(
                      onPressed: busy ? null : review,
                      child: const Text('مراجعة البصمة وتفعيل التشفير'),
                    ),
                  TextButton(
                    onPressed: busy ? null : load,
                    child: const Text('تحديث حالة الطرف الآخر'),
                  ),
                ],
              ),
            ),
          if (ready && enabled && trustRequired)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                onPressed: busy ? null : review,
                icon: const Icon(Icons.security),
                label: const Text('تغيّرت الأجهزة؛ راجع البصمة قبل الإرسال'),
              ),
            ),
          if (ready && enabled) ...[
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: rows.length > 200 ? 200 : rows.length,
                itemBuilder: (c, i) {
                  final row = rows[rows.length - 1 - i],
                      payload = row['payload'] as Map?;
                  final mine = row['senderId'] == widget.accounts.user?.id;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (row['deleted'] == true)
                              const Text('تم حذف الرسالة')
                            else if (row['securityError'] == true)
                              const Text('تعذّر التحقق من سلامة هذه الرسالة')
                            else if (payload == null)
                              const Text(
                                'هذه الرسالة غير متاحة لمفاتيح هذا الجهاز',
                              )
                            else ...[
                              if ('${payload['text']}'.isNotEmpty)
                                Text('${payload['text']}'),
                              if (payload['file'] != null)
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => openAttachment(
                                          (payload['file'] as Map)
                                              .cast<String, dynamic>(),
                                        ),
                                  icon: const Icon(Icons.lock_outline),
                                  label: Text('${payload['file']['name']}'),
                                ),
                            ],
                            const Icon(Icons.lock, size: 11),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (pending)
              TextButton.icon(
                onPressed: busy ? null : retry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة إرسال الرسالة المعلّقة'),
              ),
            if (pending)
              TextButton(
                onPressed: busy ? null : discardPending,
                child: const Text('إيقاف إعادة المحاولة'),
              ),
            if (attachment != null)
              ListTile(
                title: Text(
                  attachment!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  onPressed: () => setState(() => attachment = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: busy || pending || trustRequired
                        ? null
                        : () async {
                            final f = await openFile();
                            if (f != null && mounted)
                              setState(() => attachment = f);
                          },
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'رسالة مشفرة…',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy || pending || trustRequired ? null : send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class LegacySecureHistory extends StatefulWidget {
  const LegacySecureHistory({
    super.key,
    required this.accounts,
    required this.threadId,
  });
  final AccountController accounts;
  final String threadId;
  @override
  State<LegacySecureHistory> createState() => _LegacySecureHistoryState();
}

class _LegacySecureHistoryState extends State<LegacySecureHistory> {
  final rows = <Map<String, dynamic>>[];
  int? before;
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (busy || !more) return;
    setState(() => busy = true);
    try {
      var pages = 0;
      do {
        final d = await widget.accounts.chatRequest(
          'GET',
          '/v1/chats/${widget.threadId}/messages',
          query: {'limit': '50', if (before != null) 'before': '$before'},
        );
        final batch = (d['messages'] as List)
            .map((v) => (v as Map).cast<String, dynamic>())
            .where((v) => v['text'] != '🔒 رسالة مشفرة')
            .toList();
        rows.insertAll(0, batch);
        before = (d['nextBefore'] as num?)?.toInt();
        more = before != null;
        pages++;
        if (batch.isNotEmpty) break;
      } while (more && pages < 5);
      if (mounted) setState(() => error = null);
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('السجل السابق غير المشفر')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'هذا محتوى أُرسل قبل تفعيل التشفير. يبقى في السجل بحمايته السابقة؛ تفعيل التشفير لا يحوّله بأثر رجعي.',
        ),
        if (error != null) Text(error!),
        if (more)
          TextButton(
            onPressed: busy ? null : load,
            child: const Text('عرض أقدم'),
          ),
        if (busy) const LinearProgressIndicator(),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['author']?['displayName'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    row['deleted'] == true
                        ? 'تم حذف الرسالة'
                        : '${row['text'] ?? ''}',
                  ),
                  for (final kind in ['image', 'video', 'audio', 'file'])
                    if (row[kind] is Map && row[kind]['url'] is String)
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.tryParse(row[kind]['url'] as String);
                          if (uri?.scheme == 'https')
                            await launchUrl(
                              uri!,
                              mode: LaunchMode.externalApplication,
                            );
                        },
                        child: const Text('فتح وسائط السجل السابق'),
                      ),
                  if (row['image'] != null) const Text('صورة من السجل السابق'),
                  if (row['video'] != null) const Text('فيديو من السجل السابق'),
                  if (row['audio'] != null)
                    const Text('تسجيل صوتي من السجل السابق'),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
