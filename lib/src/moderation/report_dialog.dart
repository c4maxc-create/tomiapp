import 'package:flutter/material.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../social/social_models.dart';
import 'moderation_controller.dart';

Future<void> showReportDialog(
  BuildContext context,
  AccountController accounts, {
  required String targetType,
  required String targetId,
  required String title,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(
      accounts: accounts,
      targetType: targetType,
      targetId: targetId,
      title: title,
    ),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('وصل البلاغ. تگدر تتابع حالته من «بلاغاتي» بحسابك.'),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.accounts,
    required this.targetType,
    required this.targetId,
    required this.title,
  });
  final AccountController accounts;
  final String targetType, targetId, title;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late final owner = widget.accounts.user?.id,
      session = widget.accounts.sessionRevision;
  final description = TextEditingController();
  String reason = 'spam', requestId = newRequestId();
  String? error;
  bool busy = false;
  Map<String, dynamic>? frozen;
  bool get current =>
      mounted &&
      owner != null &&
      widget.accounts.user?.id == owner &&
      widget.accounts.sessionRevision == session;
  Future<void> send() async {
    if (!current || busy) return;
    frozen ??= Map<String, dynamic>.unmodifiable({
      'requestId': requestId,
      'targetType': widget.targetType,
      'targetId': widget.targetId,
      'reason': reason,
      'description': description.text.trim(),
    });
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.accounts.chatRequest('POST', '/v1/reports', body: frozen!);
      if (current) Navigator.pop(context, true);
    } on AccountFailure catch (f) {
      if (current)
        setState(() {
          error = f.status == 404
              ? 'المحتوى غير متاح أو السيرفر يحتاج تحديث 0.12.'
              : f.message;
          if ([400, 403, 404, 409, 410, 429].contains(f.status)) {
            frozen = null;
            requestId = newRequestId();
          }
        });
    } catch (_) {
      if (current)
        setState(
          () => error = 'تعذّر تأكيد وصول البلاغ. أعد التحقق بنفس الطلب.',
        );
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.accounts,
    builder: (context, _) => AlertDialog(
      scrollable: true,
      title: const Text('إبلاغ الإدارة'),
      content: !current
          ? const Text('انتهت جلسة الحساب؛ أغلق النافذة وسجّل الدخول.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title),
                const SizedBox(height: 12),
                const Text(
                  'تصل تفاصيل البلاغ لإدارة التطبيق، وتظهر لك حالته من «بلاغاتي». لا تضع كلمة مرور أو رمز استرجاع هنا.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('report-reason'),
                  initialValue: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'سبب البلاغ'),
                  items: [
                    for (final entry in reportReasonLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: busy || frozen != null
                      ? null
                      : (value) => setState(() => reason = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('report-description'),
                  controller: description,
                  enabled: !busy && frozen == null,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل إضافية (اختياري)',
                  ),
                ),
                if (error != null) AccountErrorMessage(error!),
                if (frozen != null && !busy)
                  const Text(
                    'الطلب ثابت إلى أن نتأكد من نتيجته؛ إعادة التحقق لا تنشئ بلاغًا ثانيًا.',
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('إغلاق'),
        ),
        FilledButton(
          key: const Key('send-report'),
          onPressed: current && !busy ? send : null,
          child: Text(
            busy
                ? 'جارٍ التحقق…'
                : frozen != null
                ? 'إعادة التحقق'
                : 'إرسال البلاغ',
          ),
        ),
      ],
    ),
  );
}
