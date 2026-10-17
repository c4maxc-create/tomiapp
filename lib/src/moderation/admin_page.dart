import 'dart:async';

import 'package:flutter/material.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import '../messaging/video_media.dart';
import '../social/social_models.dart';
import 'moderation_controller.dart';
import 'moderation_widgets.dart';

Map<String, dynamic> _map(Object? value) =>
    (value as Map?)?.cast<String, dynamic>() ?? {};
int _number(Object? value) => (value as num?)?.toInt() ?? 0;
String _role(String value) => switch (value) {
  'owner' => 'مالك التطبيق',
  'moderator' => 'مشرف التطبيق',
  _ => 'عضو',
};

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final model = ModerationController(widget.accounts);
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(start());
  }

  Future<void> start() async {
    await model.loadAccess();
    if (model.current && model.staff) await model.load();
  }

  @override
  void dispose() {
    search.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إدارة التطبيق')),
    body: AnimatedBuilder(
      animation: model,
      builder: (context, _) => RefreshIndicator(
        onRefresh: () async {
          await model.loadAccess();
          if (model.staff) await model.load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            if (model.accessLoading) const LinearProgressIndicator(),
            AdminPendingBanner(model),
            if (!model.accessLoading && !model.staff)
              const Text(
                'هذه الصفحة لإدارة التطبيق المخوّلة. صلاحية مشرف الغرفة لا تمنح صلاحية إدارة التطبيق.',
              ),
            if (model.staff) ...[
              Text(
                _role(model.role),
                style: const TextStyle(
                  color: TomiColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final e in {
                    'reports': 'البلاغات',
                    'users': 'الحسابات',
                    'rooms': 'الغرف',
                    'metrics': 'المراقبة',
                    'audit': 'سجل الإدارة',
                    if (model.role == 'owner') 'staff': 'المشرفون',
                  }.entries)
                    ChoiceChip(
                      key: ValueKey('admin-tab-${e.key}'),
                      label: Text(e.value),
                      selected: model.section == e.key,
                      onSelected: (_) {
                        search.clear();
                        unawaited(model.load(selected: e.key));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (model.section == 'reports')
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in {
                      ...reportStatusLabels,
                      'all': 'كل الحالات',
                    }.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: model.filter == e.key,
                        onSelected: (_) => model.load(selectedFilter: e.key),
                      ),
                  ],
                ),
              if (model.section == 'rooms')
                Wrap(
                  spacing: 6,
                  children: [
                    for (final e in {
                      'open': 'المفتوحة',
                      'closed': 'المغلقة',
                      'all': 'كل الغرف',
                    }.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: model.filter == e.key,
                        onSelected: (_) => model.load(selectedFilter: e.key),
                      ),
                  ],
                ),
              if (['users', 'staff'].contains(model.section))
                TextField(
                  key: const Key('admin-user-search'),
                  controller: search,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: 'بحث باليوزر',
                    suffixIcon: IconButton(
                      tooltip: 'بحث',
                      onPressed: () => model.load(search: search.text.trim()),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (q) => model.load(search: q.trim()),
                ),
              if (model.loading) const LinearProgressIndicator(),
              if (model.section == 'metrics' && model.metrics.isNotEmpty)
                _OperationsView(model.metrics),
              if (!model.loading &&
                  model.items.isEmpty &&
                  model.section != 'metrics' &&
                  model.error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد عناصر بهذه القائمة.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final row in model.items)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: switch (model.section) {
                    'reports' => reportCard(context, row),
                    'users' || 'staff' => accountCard(context, row),
                    'rooms' => roomCard(context, row),
                    _ => auditCard(row),
                  },
                ),
              if (model.nextBefore != null)
                TextButton(
                  onPressed: model.loading
                      ? null
                      : () => model.load(more: true),
                  child: const Text('عرض الأقدم'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget reportCard(BuildContext context, Map<String, dynamic> row) {
    final snapshot = _map(row['snapshot']), user = _map(snapshot['user']);
    return TomiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            reportStatusLabels[row['status']] ?? 'بلاغ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: TomiColors.accent,
            ),
          ),
          Text(reportReasonLabels[row['reason']] ?? 'سبب آخر'),
          Text('@${user['username'] ?? ''}  ${snapshot['title'] ?? ''}'),
          Text(
            row['description'] as String? ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AdminReportPage(
                  model: model,
                  reportId: row['id'] as String,
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('فتح البلاغ والمراجعة'),
          ),
        ],
      ),
    );
  }

  Widget accountCard(BuildContext context, Map<String, dynamic> row) {
    final user = AccountUser.fromJson(_map(row['user'])),
        state = _map(row['state']),
        protected = user.id == model.owner || state['role'] == 'owner';
    final suspended = state['suspended'] == true,
        moderator = state['role'] == 'moderator';
    return TomiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AccountAvatar(user, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${user.displayName}\n@${user.username}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_role(state['role'] as String? ?? 'member')} • ${suspended ? 'موقوف' : 'متاح'}',
          ),
          SelectableText(
            user.id,
            style: const TextStyle(fontSize: 11, color: TomiColors.muted),
          ),
          if (model.role == 'owner' && !protected)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: model.actionLocked
                      ? null
                      : () => confirmAdminAction(
                          context,
                          model,
                          action: moderator
                              ? 'revoke_moderator'
                              : 'grant_moderator',
                          targetId: user.id,
                          revision: _number(state['roleRevision']),
                        ),
                  child: Text(moderator ? 'إلغاء الإشراف' : 'تعيين مشرف'),
                ),
                OutlinedButton(
                  onPressed: model.actionLocked || moderator
                      ? null
                      : () => confirmAdminAction(
                          context,
                          model,
                          action: suspended ? 'restore_user' : 'suspend_user',
                          targetId: user.id,
                          revision: _number(state['restrictionRevision']),
                        ),
                  child: Text(suspended ? 'إلغاء الإيقاف' : 'إيقاف الحساب'),
                ),
              ],
            ),
          if (model.role == 'owner' && moderator)
            const Text(
              'ألغِ صلاحية المشرف قبل إيقاف الحساب.',
              style: TextStyle(fontSize: 12, color: TomiColors.muted),
            ),
        ],
      ),
    );
  }

  Widget roomCard(BuildContext context, Map<String, dynamic> row) => TomiCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          row['title'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          '${row['state'] == 'open' ? 'مفتوحة' : 'مغلقة'} • ${row['memberCount']} مشارك',
        ),
        SelectableText(
          row['id'] as String,
          style: const TextStyle(fontSize: 11, color: TomiColors.muted),
        ),
        if (row['state'] == 'open')
          OutlinedButton.icon(
            onPressed: model.actionLocked
                ? null
                : () => confirmAdminAction(
                    context,
                    model,
                    action: 'close_room',
                    targetId: row['id'] as String,
                    revision: _number(_map(row['moderation'])['revision']),
                  ),
            icon: const Icon(Icons.meeting_room_outlined),
            label: const Text('إغلاق الغرفة'),
          ),
      ],
    ),
  );
  Widget auditCard(Map<String, dynamic> row) => TomiCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          adminActionLabels[row['action']] ?? 'إجراء إدارة',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(row['reason'] as String? ?? ''),
        Text(
          'الوقت: ${row['createdAt']}',
          style: const TextStyle(fontSize: 12, color: TomiColors.muted),
        ),
        SelectableText(
          'المنفّذ: ${row['actorId']}\nالهدف: ${row['targetId']}',
          style: const TextStyle(fontSize: 11, color: TomiColors.muted),
        ),
      ],
    ),
  );
}

class AdminReportPage extends StatefulWidget {
  const AdminReportPage({
    super.key,
    required this.model,
    required this.reportId,
  });
  final ModerationController model;
  final String reportId;
  @override
  State<AdminReportPage> createState() => _AdminReportPageState();
}

class _AdminReportPageState extends State<AdminReportPage> {
  bool showImage = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.model.loadDetail(widget.reportId));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.model;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل البلاغ')),
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final data = c.detailId == widget.reportId ? c.detail : null,
              r = _map(data?['report']),
              snapshot = _map(r['snapshot']),
              live = _map(data?['target']),
              state = _map(live['state']);
          return RefreshIndicator(
            onRefresh: () => c.loadDetail(widget.reportId),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                AdminPendingBanner(c),
                if (c.detailLoading) const LinearProgressIndicator(),
                if (c.detailError != null) AccountErrorMessage(c.detailError!),
                if (!c.staff)
                  const Text('لم تعد صلاحية المراجعة متاحة لهذا الحساب.'),
                if (r.isNotEmpty && c.staff) ...[
                  Text(
                    reportStatusLabels[r['status']] ?? 'بلاغ',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(reportReasonLabels[r['reason']] ?? 'سبب آخر'),
                  Text(
                    'صاحب البلاغ: ${_map(data?['reporter'])['displayName'] ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  TomiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'تفاصيل صاحب البلاغ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(r['description'] as String? ?? ''),
                        const SizedBox(height: 12),
                        const Text(
                          'ملخص المحتوى وقت البلاغ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('@${_map(snapshot['user'])['username'] ?? ''}'),
                        if ((snapshot['title'] as String? ?? '').isNotEmpty)
                          Text(snapshot['title'] as String),
                        if ((snapshot['text'] as String? ?? '').isNotEmpty)
                          SelectableText(snapshot['text'] as String),
                        if (snapshot['hasImage'] == true)
                          const Text('يتضمن صورة.'),
                        if (snapshot['hasVideo'] == true)
                          const Text('يتضمن فيديو.'),
                        if (live.isEmpty)
                          const Text(
                            'المحتوى غير موجود الآن؛ ملخص البلاغ محفوظ.',
                          ),
                        if (live['video'] is Map)
                          VideoTile(
                            video: PostVideo(_map(live['video'])),
                            source: () async {
                              await c.loadDetail(widget.reportId);
                              final video = _map(
                                _map(c.detail?['target'])['video'],
                              );
                              return video['url'] is String
                                  ? Uri.parse(video['url'] as String)
                                  : null;
                            },
                          ),
                        if (live['imageUrl'] is String) ...[
                          TextButton(
                            onPressed: () =>
                                setState(() => showImage = !showImage),
                            child: Text(
                              showImage ? 'إخفاء الصورة' : 'عرض الصورة الحالية',
                            ),
                          ),
                          if (showImage)
                            Image.network(
                              live['imageUrl'] as String,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Text(
                                'تعذّر عرض الصورة؛ حدّث البلاغ وحاول.',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if ((r['note'] as String? ?? '').isNotEmpty)
                    TomiCard(
                      child: Text('ملاحظات الإدارة الخاصة:\n${r['note']}'),
                    ),
                  if ((r['publicMessage'] as String? ?? '').isNotEmpty)
                    Text('الرد الظاهر لصاحب البلاغ: ${r['publicMessage']}'),
                  OutlinedButton.icon(
                    onPressed: c.actionLocked
                        ? null
                        : () => reviewReport(context, c, r),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('مراجعة الحالة والملاحظات'),
                  ),
                  if (live.isNotEmpty && r['targetType'] == 'post')
                    FilledButton(
                      onPressed: c.actionLocked
                          ? null
                          : () => confirmAdminAction(
                              context,
                              c,
                              action: state['hidden'] == true
                                  ? 'restore_post'
                                  : 'hide_post',
                              targetId: r['targetId'] as String,
                              revision: _number(state['revision']),
                              reportId: widget.reportId,
                            ),
                      child: Text(
                        state['hidden'] == true
                            ? 'استعادة المنشور'
                            : 'إخفاء المنشور',
                      ),
                    ),
                  if (live.isNotEmpty &&
                      r['targetType'] == 'room' &&
                      state['roomState'] == 'open')
                    FilledButton(
                      onPressed: c.actionLocked
                          ? null
                          : () => confirmAdminAction(
                              context,
                              c,
                              action: 'close_room',
                              targetId: r['targetId'] as String,
                              revision: _number(state['revision']),
                              reportId: widget.reportId,
                            ),
                      child: const Text('إغلاق الغرفة'),
                    ),
                  if (live.isNotEmpty &&
                      r['targetType'] == 'account' &&
                      c.role == 'owner' &&
                      state['role'] == 'member' &&
                      r['targetId'] != c.owner)
                    FilledButton(
                      onPressed: c.actionLocked
                          ? null
                          : () => confirmAdminAction(
                              context,
                              c,
                              action: state['suspended'] == true
                                  ? 'restore_user'
                                  : 'suspend_user',
                              targetId: r['targetId'] as String,
                              revision: _number(state['restrictionRevision']),
                              reportId: widget.reportId,
                            ),
                      child: Text(
                        state['suspended'] == true
                            ? 'إلغاء إيقاف الحساب'
                            : 'إيقاف الحساب',
                      ),
                    ),
                  SelectableText(
                    'رقم البلاغ: ${r['id']}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: TomiColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OperationsView extends StatelessWidget {
  const _OperationsView(this.data);
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final requests = _map(data['requests']),
        process = _map(data['process']),
        db = _map(data['database']);
    final labels = <String, String>{
      'طلبات آخر ساعة': '${requests['count'] ?? 0}',
      'أخطاء الخادم': '${requests['serverErrors'] ?? 0}',
      'متوسط الاستجابة': '${requests['averageMs'] ?? 0} ms',
      '95% من الاستجابات': requests['p95OverFiveSeconds'] == true
          ? 'أكثر من 5 ثوانٍ'
          : 'حتى ${requests['p95UpperMs'] ?? 0} ms',
      'ذاكرة العملية':
          '${(_number(process['rssBytes']) / 1048576).toStringAsFixed(1)} MB',
      'الغرف المفتوحة': '${db['open_rooms'] ?? 0}',
      'المشاركون الآن': '${db['room_participants'] ?? 0}',
      'المكالمات الحالية': '${db['active_calls'] ?? 0}',
      'بلاغات تنتظر المعالجة': '${db['pending_reports'] ?? 0}',
      'مهام صوت تنتظر التنفيذ': '${db['pending_voice_jobs'] ?? 0}',
      'الحسابات': '${db['users'] ?? 0}',
      'الحسابات الموقوفة': '${db['suspended_users'] ?? 0}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'قياسات نسخة الخادم الحالية. نافذة الطلبات آخر ساعة، وتبدأ من جديد عند تشغيل الخادم. ليست فحص ضغط أو قياسًا لكل نسخ الخدمة.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in labels.entries)
                SizedBox(
                  width: box.maxWidth < 320
                      ? box.maxWidth
                      : (box.maxWidth - 8) / 2,
                  child: TomiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(color: TomiColors.muted),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          e.value,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'الصور المسجّلة: ${(_number(db['image_bytes']) / 1048576).toStringAsFixed(1)} MB\nالصوتيات المسجّلة: ${(_number(db['audio_bytes']) / 1048576).toStringAsFixed(1)} MB\nالفيديو المسجّل: ${(_number(db['video_bytes']) / 1048576).toStringAsFixed(1)} MB',
        ),
        const Text(
          'هذه تقديرات من سجلات الملفات، وتشمل ملفات قد تكون قيد الرفع أو الحذف. لا تمثل فاتورة التخزين أو دقائق الصوت. راجع استهلاك مزود الخدمة قبل توسيع الاستخدام.',
        ),
        Text(
          'آخر عينة للبيانات: ${data['databaseSampleAt'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: TomiColors.muted),
        ),
      ],
    );
  }
}
