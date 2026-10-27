import 'package:flutter/material.dart';

import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'moderation_controller.dart';

class AdminPendingBanner extends StatelessWidget {
  const AdminPendingBanner(this.model, {super.key});
  final ModerationController model;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (model.error != null) AccountErrorMessage(model.error!),
      if (model.notice != null)
        Padding(padding: const EdgeInsets.all(8), child: Text(model.notice!)),
      if (model.pendingCommand != null)
        TomiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إجراء ينتظر التأكيد: ${adminActionLabels[model.pendingCommand!['action']] ?? 'إجراء إدارة'}',
              ),
              const Text(
                'أعد التحقق بنفس الطلب. إلغاء المحاولة لا يتراجع عن إجراء قبله السيرفر.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: model.acting ? null : () => model.retryCommand(),
                    child: const Text('إعادة التحقق'),
                  ),
                  TextButton(
                    onPressed: model.acting ? null : model.discardRetry,
                    child: const Text('إلغاء إعادة المحاولة'),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (model.acting) const LinearProgressIndicator(),
    ],
  );
}

Future<void> confirmAdminAction(
  BuildContext context,
  ModerationController model, {
  required String action,
  required String targetId,
  required int revision,
  String? reportId,
}) async {
  if (model.actionLocked) return;
  final reason = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        scrollable: true,
        title: Text(adminActionLabels[action] ?? 'إجراء إدارة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (action) {
              'close_room' =>
                'تُغلق الغرفة ويُخرج المشاركون. تبقى سجلاتها، ولا تُفتح هذه الغرفة مجددًا.',
              'suspend_user' =>
                'تُلغى جلسات الحساب، وتنتهي مكالماته وتُغلق الغرف التي يملكها. إلغاء الإيقاف لاحقًا لا يعيد فتح الغرف.',
              'restore_user' =>
                'يستطيع صاحب الحساب تسجيل الدخول مجددًا؛ الجلسات القديمة تبقى ملغاة.',
              'hide_post' =>
                'يختفي المنشور من التطبيق، وتبقى بياناته متاحة للمراجعة والاستعادة.',
              'restore_post' =>
                'يعود المنشور للظهور إذا كان حساب صاحبه متاحًا ولم يحذفه.',
              'grant_moderator' =>
                'يصبح الحساب مشرفًا على بلاغات التطبيق والمحتوى والغرف، دون صلاحية تعيين المشرفين أو إيقاف الحسابات.',
              'mark_special' => 'تظهر علامة الحساب المميز على صورة المستخدم.',
              'unmark_special' => 'تُزال علامة الحساب المميز.',
              _ => 'تُسحب صلاحية إدارة التطبيق فور حفظ الإجراء.',
            }),
            const SizedBox(height: 14),
            TextField(
              key: const Key('admin-action-reason'),
              controller: reason,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'سبب الإجراء (يُحفظ بسجل الإدارة)',
              ),
              onChanged: (_) => refresh(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: const Key('confirm-admin-action'),
            onPressed: reason.text.trim().runes.length < 4
                ? null
                : () => Navigator.pop(c, reason.text.trim()),
            child: const Text('تأكيد الإجراء'),
          ),
        ],
      ),
    ),
  );
  reason.dispose();
  if (result == null || !context.mounted) return;
  await model.runCommand({
    'action': action,
    'targetId': targetId,
    'expectedRevision': revision,
    'reason': result,
    if (reportId != null) 'reportId': reportId,
  });
}

Future<void> reviewReport(
  BuildContext context,
  ModerationController model,
  Map<String, dynamic> report,
) async {
  if (model.actionLocked) return;
  var status = report['status'] as String;
  final note = TextEditingController(text: report['note'] as String? ?? ''),
      message = TextEditingController(
        text: report['publicMessage'] as String? ?? '',
      );
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        scrollable: true,
        title: const Text('مراجعة البلاغ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'حالة البلاغ'),
              items: [
                for (final e in reportStatusLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => refresh(() => status = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'ملاحظات الإدارة الخاصة',
              ),
            ),
            TextField(
              controller: message,
              minLines: 2,
              maxLines: 4,
              maxLength: 280,
              decoration: const InputDecoration(
                labelText: 'رسالة تظهر لصاحب البلاغ',
              ),
            ),
            const Text(
              'حفظ المراجعة لا ينفذ إجراءً على المحتوى تلقائيًا. استعمل زر الإجراء المناسب في تفاصيل البلاغ.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, <String, dynamic>{
              'action': 'review_report',
              'targetId': report['id'],
              'expectedRevision': report['revision'],
              'status': status,
              'note': note.text.trim(),
              'publicMessage': message.text.trim(),
              'reason': 'مراجعة البلاغ',
            }),
            child: const Text('حفظ المراجعة'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
  message.dispose();
  if (result != null && context.mounted) await model.runCommand(result);
}
