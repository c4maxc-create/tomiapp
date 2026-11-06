import 'camera_check_page.dart';
import '../messaging/voice_note.dart';
import '../gaming/csharp_games_page.dart';
import '../voice_rooms/room_screens.dart';
import '../live/live_pages.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../preferences/media_preferences.dart';
import '../social/social_models.dart' show newRequestId;

class CommunityToolsPage extends StatelessWidget {
  const CommunityToolsPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('أدوات TOMI')),
    body: ListView(
      children: [
        for (final entry in const {
          'diagnostics': 'فحص الاتصال والهاتف',
          'support': 'الدعم ومتابعة الطلبات',
          'invitations': 'مركز الدعوات',
          'notices': 'تنبيهات الدعم والمحتوى',
          'contentPrivacy': 'التعليقات والإشارات والكلمات',
          'polls': 'التصويت والاستطلاعات',
          'explore': 'تخصيص الاستكشاف',
          'exceptions': 'استثناءات التواصل',
          'gifts': 'سجل الهدايا التجريبية',
        }.entries)
          ListTile(
            key: ValueKey('tools-${entry.key}'),
            leading: Icon(switch (entry.key) {
              'diagnostics' => Icons.health_and_safety_outlined,
              'support' => Icons.support_agent,
              'notices' => Icons.notifications_none,
              'contentPrivacy' => Icons.comment_outlined,
              'polls' => Icons.poll_outlined,
              'explore' => Icons.explore_outlined,
              'exceptions' => Icons.privacy_tip_outlined,
              _ => Icons.redeem,
            }),
            title: Text(entry.value),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(
              c,
              MaterialPageRoute<void>(
                builder: (_) => CommunityPage(
                  accounts: accounts,
                  kind: entry.key,
                  title: entry.value,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.accounts,
    required this.kind,
    required this.title,
    this.roomId,
    this.canCreate = true,
    this.targetId,
  });
  final AccountController accounts;
  final String kind, title;
  final String? roomId;
  final bool canCreate;
  final String? targetId;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  int epoch = 0;
  String? requestId;
  String composeSubject = '', composeBody = '';
  DateTime? pollEnd;
  final first = TextEditingController(), second = TextEditingController();
  String get path => switch (widget.kind) {
    'support' => '/v1/me/support',
    'notices' => '/v1/me/notices',
    'contentPrivacy' => '/v1/me/content-preferences',
    'invitations' => '/v1/me/invitations',
    'adminSupport' => '/v1/admin/support',
    'polls' => '/v1/polls',
    'explore' => '/v1/me/explore-preferences',
    'exceptions' => '/v1/me/contact-exceptions',
    'gifts' => '/v1/me/gift-history',
    _ => '/v1/me/connection-check',
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (more && (busy || data?['nextCursor'] == null)) return;
    final e = ++epoch;
    setState(() => busy = true);
    try {
      final result = await widget.accounts.chatRequest(
        'GET',
        path,
        query: {
          if (widget.kind == 'polls' && widget.roomId != null)
            'roomId': widget.roomId!,
          if (more) 'cursor': data!['nextCursor'] as String,
          if (widget.targetId != null) 'targetId': widget.targetId!,
        },
      );
      if (!mounted || e != epoch) return;
      if (widget.kind == 'diagnostics') {
        try {
          if (!(Platform.isAndroid || Platform.isIOS) ||
              Platform.environment.containsKey('FLUTTER_TEST'))
            throw MissingPluginException();
          result['device'] = await const MethodChannel(
            'tomi/mobile',
          ).invokeMapMethod<String, dynamic>('deviceCheck');
        } catch (_) {
          result['device'] = null;
        }
        result['previewBytes'] = await MediaPreferences.instance.previewBytes();
      }
      if (!mounted || e != epoch) return;
      if (more)
        result['items'] = [
          ...data?['items'] as List? ?? [],
          ...result['items'] as List? ?? [],
        ];
      setState(() {
        data = result;
        error = null;
        if (widget.kind == 'contentPrivacy')
          first.text = (result['words'] as List).join('، ');
        if (widget.kind == 'explore') {
          first.text = (result['keywords'] as List).join('، ');
          second.text = (result['topics'] as List).join('، ');
        }
      });
    } on AccountFailure catch (f) {
      if (mounted && e == epoch) setState(() => error = f.message);
    } catch (_) {
      if (mounted && e == epoch)
        setState(() => error = 'تعذّر التحميل؛ أعد المحاولة.');
    } finally {
      if (mounted && e == epoch) setState(() => busy = false);
    }
  }

  Future<void> send(
    String method,
    String target,
    Map<String, dynamic> body,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.accounts.chatRequest(method, target, body: body);
      if (!mounted) return;
      requestId = null;
      await load();
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted) setState(() => error = 'لم يكتمل الطلب؛ أعد المحاولة.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> compose() async {
    final a = TextEditingController(text: composeSubject),
        b = TextEditingController(text: composeBody);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(widget.kind == 'support' ? 'طلب مساعدة' : 'تصويت جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: a,
                maxLength: widget.kind == 'support' ? 100 : 180,
                decoration: InputDecoration(
                  labelText: widget.kind == 'support' ? 'الموضوع' : 'السؤال',
                ),
              ),
              TextField(
                controller: b,
                maxLength: widget.kind == 'support' ? 3000 : 480,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: widget.kind == 'support'
                      ? 'اشرح المشكلة بدون كلمات مرور أو مفاتيح'
                      : 'خيار بكل سطر، من2 إلى6 خيارات',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    final av = a.text.trim(), bv = b.text.trim();
    a.dispose();
    b.dispose();
    if (accepted != true || !mounted) return;
    if (av != composeSubject || bv != composeBody) {
      requestId = null;
      pollEnd = null;
    }
    composeSubject = av;
    composeBody = bv;
    pollEnd ??= DateTime.now().toUtc().add(const Duration(days: 1));
    requestId ??= newRequestId();
    await send(
      'POST',
      path,
      widget.kind == 'support'
          ? {'subject': av, 'body': bv, 'requestId': requestId}
          : {
              'question': av,
              'options': bv
                  .split('\n')
                  .map((x) => x.trim())
                  .where((x) => x.isNotEmpty)
                  .toList(),
              'endsAt': pollEnd!.toIso8601String(),
              'requestId': requestId,
              if (widget.roomId != null) 'roomId': widget.roomId,
            },
    );
  }

  Future<void> exception() async {
    final id = TextEditingController();
    String kind = 'messages';
    bool allowed = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('استثناء تواصل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: id,
                  decoration: const InputDecoration(
                    labelText: 'يوزر الشخص بدون @',
                  ),
                ),
                DropdownButton<String>(
                  value: kind,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'messages', child: Text('الرسائل')),
                    DropdownMenuItem(value: 'calls', child: Text('المكالمات')),
                    DropdownMenuItem(
                      value: 'roomInvites',
                      child: Text('دعوات المايك'),
                    ),
                  ],
                  onChanged: (v) => update(() => kind = v!),
                ),
                SwitchListTile(
                  title: const Text('السماح لهذا الشخص'),
                  value: allowed,
                  onChanged: (v) => update(() => allowed = v),
                ),
                const Text('الحظر يبقى أقوى من الاستثناء.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final value = id.text.trim();
    id.dispose();
    if (ok == true && mounted)
      await send('PUT', path, {'id': value, 'kind': kind, 'allowed': allowed});
  }

  Future<String?> resolveUser(String username) async {
    try {
      final clean = username.replaceFirst(RegExp(r'^@'), '').trim();
      final result = await widget.accounts.chatRequest(
        'GET',
        '/v1/search',
        query: {'q': clean},
      );
      final users = (result['users'] as List).cast<Map<String, dynamic>>();
      final exact = users
          .where(
            (u) =>
                (u['username'] as String).toLowerCase() == clean.toLowerCase(),
          )
          .firstOrNull;
      if (exact != null) return exact['id'] as String;
      if (mounted)
        setState(
          () => error = 'لم نجد هذا اليوزر؛ اكتب الاسم الكامل للمستخدم.',
        );
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر البحث عن الشخص.');
    }
    return null;
  }

  List<String> words(String s) => s
      .split(RegExp('[،,\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  @override
  void dispose() {
    epoch++;
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final items = (data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton:
          widget.canCreate &&
              ['support', 'polls', 'exceptions'].contains(widget.kind)
          ? FloatingActionButton(
              onPressed: busy
                  ? null
                  : widget.kind == 'exceptions'
                  ? exception
                  : compose,
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: busy ? null : load,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            if (data != null && widget.kind == 'diagnostics') ...diagnostics(),
            if (data != null && widget.kind == 'explore') ...[
              const Text(
                'الكلمات المستبعدة تخفي منشورات الاستكشاف التي تحتويها. المواضيع المختارة تصفّي بالنص؛ اتركها فارغة لعرض الكل.',
              ),
              TextField(
                controller: first,
                maxLength: 1200,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'كلمات مستبعدة، افصل بفاصلة',
                ),
              ),
              TextField(
                controller: second,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'مواضيع مفضلة'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => send('PUT', path, {
                        'keywords': words(first.text),
                        'topics': words(second.text),
                      }),
                child: const Text('حفظ'),
              ),
              for (final item in (data?['hidden'] as List? ?? []))
                ListTile(
                  title: Text(
                    item['type'] == 'post' ? 'منشور مخفي' : 'حساب مخفي',
                  ),
                  subtitle: Text(item['id']),
                  trailing: IconButton(
                    tooltip: 'إلغاء الإخفاء',
                    icon: const Icon(Icons.undo),
                    onPressed: busy
                        ? null
                        : () => send('DELETE', '/v1/me/explore-hidden', {
                            'type': item['type'],
                            'id': item['id'],
                          }),
                  ),
                ),
            ],
            if (data != null && widget.kind == 'contentPrivacy') ...[
              const Text(
                'تطبق على تعليقات الآخرين في منشوراتك وعلى الإشارة إلى يوزرك. الحظر يبقى أقوى من هذه الخيارات.',
              ),
              for (final field in const {
                'comments': 'من يعلق على منشوراتي؟',
                'mentions': 'من يذكرني بالمنشورات والستوري؟',
              }.entries)
                DropdownButtonFormField<String>(
                  key: ValueKey('${field.key}-${data![field.key]}'),
                  initialValue: data![field.key] as String,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: field.value),
                  items: const [
                    DropdownMenuItem(value: 'everyone', child: Text('الجميع')),
                    DropdownMenuItem(
                      value: 'following',
                      child: Text('الأشخاص الذين أتابعهم'),
                    ),
                    DropdownMenuItem(value: 'nobody', child: Text('لا أحد')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => data![field.key] = v),
                ),
              TextField(
                controller: first,
                maxLines: 3,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'كلمات تمنعها بتعليقات الآخرين، افصل بفاصلة',
                ),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => send('PUT', path, {
                        'comments': data!['comments'],
                        'mentions': data!['mentions'],
                        'words': words(first.text),
                      }),
                child: const Text('حفظ'),
              ),
            ],
            if (widget.kind == 'gifts')
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'سجل هدايا الغرف التجريبية فقط. لا توجد مشتريات حقيقية أو إمكانية سحب.',
                  ),
                ),
              ),
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: entry(item),
                ),
              ),
            if (data?['nextCursor'] != null)
              TextButton(
                onPressed: busy ? null : () => load(more: true),
                child: const Text('عناصر أقدم'),
              ),
            if (items.isEmpty &&
                data != null &&
                ![
                  'diagnostics',
                  'explore',
                  'contentPrivacy',
                ].contains(widget.kind))
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد عناصر بعد.', textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }

  Widget entry(Map<String, dynamic> item) {
    if (widget.kind == 'notices')
      return ListTile(
        leading: Icon(
          item['read'] == true
              ? Icons.drafts_outlined
              : Icons.mark_email_unread_outlined,
        ),
        title: Text(switch (item['kind']) {
          'support' => 'رد جديد من الدعم',
          'mention_post' => 'إشارة في منشور',
          'mention_story' => 'إشارة في ستوري',
          'schedule' => 'موعد غرفة',
          _ => 'تنبيه جديد',
        }),
        subtitle: Text(item['createdAt'] as String),
        onTap: () => widget.accounts.push.onOpenNotice?.call(
          widget.accounts.user!.id,
          item['id'] as String,
        ),
      );

    if (widget.kind == 'invitations')
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'دعوة ${item['kind'] == 'game'
                ? 'لعبة'
                : item['kind'] == 'room'
                ? 'غرفة'
                : 'بث'} من ${item['sender_name']}',
          ),
          Text('تنتهي: ${item['expires_at']}'),
          Wrap(
            spacing: 8,
            children: [
              if (item['state'] != 'declined')
                FilledButton(
                  onPressed: busy ? null : () => invitation(item, true),
                  child: Text(item['state'] == 'accepted' ? 'فتح' : 'قبول'),
                ),
              if (item['state'] == 'pending')
                TextButton(
                  onPressed: busy ? null : () => invitation(item, false),
                  child: const Text('رفض'),
                ),
            ],
          ),
        ],
      );

    if (widget.kind == 'support' || widget.kind == 'adminSupport')
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['subject'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(item['body']),
          Text(switch (item['status']) {
            'answered' => 'تم الرد',
            'closed' => 'مغلق',
            _ => 'قيد المتابعة',
          }),
          if (widget.kind == 'adminSupport')
            TextButton(
              onPressed: busy ? null : () => reply(item),
              child: const Text('الرد وتحديث الحالة'),
            ),
          if ((item['reply'] as String).isNotEmpty)
            Text('رد الإدارة: ${item['reply']}'),
        ],
      );
    if (widget.kind == 'exceptions')
      return ListTile(
        title: Text(
          '${item['kind']} · ${item['allowed'] == 1 ? 'مسموح' : 'غير مسموح'}',
        ),
        subtitle: Text(item['id']),
        trailing: IconButton(
          tooltip: 'حذف الاستثناء',
          icon: const Icon(Icons.delete_outline),
          onPressed: busy
              ? null
              : () => send('DELETE', path, {
                  'id': item['id'],
                  'kind': item['kind'],
                }),
        ),
      );
    if (widget.kind == 'gifts')
      return ListTile(
        leading: const Icon(Icons.redeem),
        title: Text('${item['gift_id']} × ${item['quantity']}'),
        subtitle: Text(
          '${item['sender_id'] == widget.accounts.user?.id ? 'أرسلت' : 'استلمت'} · ${item['total']} نقطة\n${item['created_at']}',
        ),
      );
    final options = item['options'] as List, counts = item['counts'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item['question'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: busy || item['closed'] == true
                  ? null
                  : () => send('PUT', '/v1/polls/${item['id']}/vote', {
                      'choice': i,
                    }),
              child: Text(
                '${item['mine'] == i ? '✓ ' : ''}${options[i]} · ${counts[i]}',
              ),
            ),
          ),
        Text(
          item['closed'] == true
              ? 'انتهى التصويت'
              : 'الانتهاء: ${item['endsAt']}',
        ),
      ],
    );
  }

  Future<void> invitation(Map<String, dynamic> item, bool accept) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.accounts.chatRequest(
        'PUT',
        '/v1/me/invitations/${item['id']}',
        body: {'state': accept ? 'accepted' : 'declined'},
      );
      if (!mounted) return;
      if (accept) {
        final invitation = result['invitation'] as Map;
        if (item['kind'] == 'game') {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => CSharpGamesPage(
                accounts: widget.accounts,
                initialCode: invitation['code'] as String?,
              ),
            ),
          );
        } else if (item['kind'] == 'live') {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => LiveHub(accounts: widget.accounts),
            ),
          );
        } else {
          final rooms = widget.accounts.voiceRooms;
          if (await rooms.join(item['target_id'] as String) && mounted)
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => VoiceRoomPage(controller: rooms),
              ),
            );
          else if (mounted)
            throw StateError('room join');
        }
      }
      if (mounted) await load();
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'تعذّر فتح الدعوة؛ قد تكون الغرفة محمية بكلمة مرور أو انتهت الجولة.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reply(Map<String, dynamic> item) async {
    final input = TextEditingController(text: item['reply'] as String);
    String status = item['status'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('رد الدعم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: input, maxLength: 3000, maxLines: 5),
                DropdownButton<String>(
                  value: status,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'open',
                      child: Text('قيد المتابعة'),
                    ),
                    DropdownMenuItem(value: 'answered', child: Text('تم الرد')),
                    DropdownMenuItem(value: 'closed', child: Text('مغلق')),
                  ],
                  onChanged: (v) => update(() => status = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final value = input.text;
    input.dispose();
    if (ok == true && mounted)
      await send('PUT', '/v1/admin/support/${item['id']}', {
        'reply': value,
        'status': status,
        'revision': item['revision'],
      });
  }

  List<Widget> diagnostics() {
    final device = data?['device'] as Map?,
        services = data?['configured'] as Map?;
    return [
      const Text(
        'فحص الأذونات لا يسجّل صوتاً ولا يفتح الكاميرا. وجود إعداد الخدمة لا يثبت اتصالها.',
      ),
      FilledButton.icon(
        icon: const Icon(Icons.mic_outlined),
        label: const Text('تسجيل وفحص المايك محلياً'),
        onPressed: widget.accounts.liveAudioBusy
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                isDismissible: false,
                enableDrag: false,
                builder: (_) => const VoiceRecorderSheet(diagnostic: true),
              ),
      ),
      if (widget.accounts.liveAudioBusy)
        const Text('أنهِ المكالمة أو غادر الغرفة قبل فحص المايك.'),
      OutlinedButton.icon(
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('فحص صورة الكاميرا محلياً'),
        onPressed: widget.accounts.liveAudioBusy
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CameraCheckPage(accounts: widget.accounts),
                ),
              ),
      ),
      for (final key in const {
        'microphone': 'الميكروفون',
        'camera': 'الكاميرا',
        'notifications': 'إذن الإشعارات',
      }.entries)
        ListTile(
          title: Text(key.value),
          subtitle: Text(
            device == null
                ? 'الفحص الأصلي متاح في نسخة الهاتف بعد تثبيت النسخة الجديدة'
                : device[key.key] == true
                ? 'الإذن مسموح'
                : 'اسمح بالإذن من إعدادات الهاتف عند حاجتك للميزة',
          ),
          leading: Icon(
            device?[key.key] == true
                ? Icons.check_circle_outline
                : Icons.info_outline,
          ),
        ),
      for (final key in const {
        'calls': 'المكالمات',
        'rooms': 'الغرف',
        'live': 'البث',
        'media': 'رفع وسائط المنشورات',
      }.entries)
        ListTile(
          title: Text(key.value),
          subtitle: Text(
            services?[key.key] == true
                ? 'الإعداد موجود؛ يحتاج اختبار اتصال فعلي'
                : 'الخدمة غير مهيأة على الخادم',
          ),
          leading: Icon(
            services?[key.key] == true
                ? Icons.settings_outlined
                : Icons.cloud_off,
          ),
        ),
      ListTile(
        title: const Text('حجم المعاينات القابلة للتنظيف'),
        subtitle: Text(
          '${((data?['previewBytes'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MB',
        ),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                await MediaPreferences.instance.clearPreviews();
                if (mounted) await load();
              },
        child: const Text('تنظيف المعاينات فقط'),
      ),
    ];
  }
}
