import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'admin_page.dart';
import 'moderation_controller.dart';

class ModerationSettingsEntry extends StatefulWidget {
  const ModerationSettingsEntry({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<ModerationSettingsEntry> createState() =>
      _ModerationSettingsEntryState();
}

class _ModerationSettingsEntryState extends State<ModerationSettingsEntry> {
  late final model = ModerationController(widget.accounts);
  void refreshAccess() {
    unawaited(model.loadAccess());
  }

  @override
  void initState() {
    super.initState();
    widget.accounts.addListener(refreshAccess);
    unawaited(model.loadAccess());
  }

  @override
  void dispose() {
    widget.accounts.removeListener(refreshAccess);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('my-reports'),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('بلاغاتي'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => MyReportsPage(accounts: widget.accounts),
            ),
          ),
        ),
        if (model.staff)
          OutlinedButton.icon(
            key: const Key('platform-admin'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('إدارة التطبيق'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AdminPage(accounts: widget.accounts),
              ),
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.copy_outlined),
          label: const Text('نسخ معرّف حسابي'),
          onPressed: () async {
            final id = widget.accounts.user?.id;
            if (id == null) return;
            await Clipboard.setData(ClipboardData(text: id));
            if (context.mounted)
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('تم نسخ معرّف حسابك.')),
              );
          },
        ),
      ],
    ),
  );
}

class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  late final model = ModerationController(widget.accounts);
  @override
  void initState() {
    super.initState();
    unawaited(model.load(selected: 'mine'));
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بلاغاتي')),
    body: AnimatedBuilder(
      animation: model,
      builder: (context, _) => RefreshIndicator(
        onRefresh: () => model.load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'تابع حالة بلاغاتك ورد الإدارة. ملاحظات المراجعة الخاصة تبقى لدى الإدارة.',
            ),
            if (model.loading) const LinearProgressIndicator(),
            if (model.error != null) AccountErrorMessage(model.error!),
            if (!model.loading && model.error == null && model.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ما عندك بلاغات لحد الآن.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final r in model.items)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TomiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        reportStatusLabels[r['status']] ?? 'بلاغ',
                        style: const TextStyle(
                          color: TomiColors.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(reportReasonLabels[r['reason']] ?? 'سبب آخر'),
                      if ((r['description'] as String? ?? '').isNotEmpty)
                        Text(r['description'] as String),
                      if ((r['publicMessage'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text('رد الإدارة: ${r['publicMessage']}'),
                        ),
                      Text(
                        'آخر تحديث: ${r['updatedAt']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: TomiColors.muted,
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
                  ),
                ),
              ),
            if (model.nextBefore != null)
              TextButton(
                onPressed: model.loading ? null : () => model.load(more: true),
                child: const Text('بلاغات أقدم'),
              ),
          ],
        ),
      ),
    ),
  );
}
