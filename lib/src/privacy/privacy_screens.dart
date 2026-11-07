import '../accounts/external_auth_ui.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'deletion_controller.dart';

class PrivacyCenterPage extends StatefulWidget {
  const PrivacyCenterPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<PrivacyCenterPage> createState() => _PrivacyCenterPageState();
}

class _PrivacyCenterPageState extends State<PrivacyCenterPage> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  Future<void> load() async {
    if (mounted)
      setState(() {
        loading = true;
        error = null;
      });
    try {
      final d = await widget.accounts.api.publicRequest(
        'GET',
        '/v1/privacy/documents',
      );
      if (mounted) setState(() => data = d);
    } on AccountFailure catch (f) {
      if (mounted)
        setState(
          () => error = f.status == 404
              ? 'حدّث السيرفر إلى 1.0 التجريبية لعرض الوثائق والحذف.'
              : f.message,
        );
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل الوثائق؛ جرّب التحديث.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الخصوصية والحساب')),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) AccountErrorMessage(error!),
          if (data != null) ...[
            Text('نسخة الوثائق: ${data!['version']}'),
            if (data!['publicationReady'] != true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'هذه نسخة اختبار خاصة؛ بيانات الجهة المشغلة والدعم والاحتفاظ لم تعتمد للتوزيع العام بعد.',
                ),
              ),
            if (data!['operatorName'] != null)
              Text('الجهة المشغلة: ${data!['operatorName']}'),
            if (data!['supportEmail'] != null)
              SelectableText('التواصل والاعتراض: ${data!['supportEmail']}'),
            for (final doc
                in (data!['documents'] as List).cast<Map<String, dynamic>>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(doc['title'] as String),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PrivacyDocumentPage(
                      document: doc,
                      version: data!['version'] as String,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const Key('open-account-deletion'),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('حذف الحساب أو متابعة طلب سابق'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AccountDeletionPage(accounts: widget.accounts),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('نسخ رابط حذف الحساب من المتصفح'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: '${widget.accounts.api.baseUrl}/account/delete',
                ),
              );
              if (context.mounted)
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'نُسخ رابط حذف الحساب؛ يعمل دون تثبيت التطبيق.',
                    ),
                  ),
                );
            },
          ),
        ],
      ),
    ),
  );
}

class PrivacyDocumentPage extends StatelessWidget {
  const PrivacyDocumentPage({
    super.key,
    required this.document,
    required this.version,
  });
  final Map<String, dynamic> document;
  final String version;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(document['title'] as String)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('نسخة $version', style: const TextStyle(color: TomiColors.muted)),
        for (final s
            in (document['sections'] as List).cast<Map<String, dynamic>>()) ...[
          const SizedBox(height: 18),
          Text(
            s['title'] as String,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SelectableText(
            s['text'] as String,
            style: const TextStyle(height: 1.7),
          ),
        ],
      ],
    ),
  );
}

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  late final model = AccountDeletionController(widget.accounts);
  final password = TextEditingController(),
      confirmation = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(model.restore());
  }

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حذف الحساب والبيانات')),
    body: AnimatedBuilder(
      animation: Listenable.merge([model, widget.accounts]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'حذف نهائي بعد قبول الطلب',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 12),
          const Text(
            'تُحذف بيانات ملفك ودخولك ومنشوراتك، وتُفرّغ رسائلك ومرفقاتك لدى الخادم. ينتهي الاتصال وتغلق غرفك وتفقد الرصيد التجريبي. تبقى رسائل الآخرين وسجلات هدايا مشتركة باسم حساب محذوف. راجع سياسة الخصوصية للسجلات الأمنية والنسخ الاحتياطية.',
          ),
          if (model.loading || model.busy) const LinearProgressIndicator(),
          if (!model.ready && !model.loading)
            TextButton(
              onPressed: model.restore,
              child: const Text('إعادة قراءة إيصال الجهاز'),
            ),
          if (model.error != null) AccountErrorMessage(model.error!),
          if (model.localError != null) AccountErrorMessage(model.localError!),
          if (model.status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: TomiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      model.status!['message'] as String? ??
                          'آخر حالة مؤكدة للطلب',
                    ),
                    Text(
                      'ملفات تنتظر التنظيف: ${model.status!['pendingMedia'] ?? 0}',
                    ),
                    Text(
                      'مهام صوت تنتظر التنفيذ: ${model.status!['pendingVoice'] ?? 0}',
                    ),
                    SelectableText('رقم الطلب: ${model.status!['requestId']}'),
                    Text(
                      'صلاحية الإيصال: ${model.status!['receiptExpiresAt']}',
                    ),
                  ],
                ),
              ),
            ),
          if (model.pending != null) ...[
            const SizedBox(height: 14),
            const Text(
              'يوجد إيصال محفوظ على هذا الجهاز. التحقق يعرض نتيجة الطلب ولا يبدأ حذفًا جديدًا.',
            ),
            OutlinedButton(
              key: const Key('check-account-deletion'),
              onPressed: model.busy ? null : model.check,
              child: const Text('التحقق من نتيجة الطلب'),
            ),
            if (model.accepted)
              OutlinedButton(
                onPressed: model.busy
                    ? null
                    : () async {
                        await model.cleanLocal();
                        model.changed();
                      },
                child: const Text('إعادة تنظيف بيانات هذا الجهاز'),
              ),
            TextButton(
              onPressed: model.busy || model.localError != null
                  ? null
                  : () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('إزالة إيصال هذا الجهاز؟'),
                          content: const Text(
                            'هذا لا يلغي حذفًا قبله الخادم. احتفظ بالإيصال لمتابعة التنظيف عند انقطاع الاتصال.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('رجوع'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('إزالة الإيصال'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) await model.forget();
                    },
              child: const Text('إزالة إيصال هذا الجهاز فقط'),
            ),
          ],
          if (model.preview?['ownerTransferRequired'] == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'انقل ملكية التطبيق إلى حساب آخر في إعدادات الخدمة قبل حذف حساب المالك.',
              ),
            ),
          if (widget.accounts.user != null &&
              !model.accepted &&
              model.preview?['canDelete'] == true) ...[
            const SizedBox(height: 18),
            Text('الحساب الحالي: @${widget.accounts.user!.username}'),
            PasswordField(
              key: const Key('deletion-password'),
              controller: password,
              enabled: !model.busy,
              label: 'كلمة المرور الحالية',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('deletion-confirmation'),
              controller: confirmation,
              enabled: !model.busy,
              maxLength: 30,
              decoration: const InputDecoration(labelText: 'اكتب: حذف حسابي'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('send-account-deletion'),
              onPressed: model.busy || !model.ready
                  ? null
                  : () async {
                      final secret = password.text;
                      password.clear();
                      try {
                        final proof = await sensitiveCredential(
                          context,
                          widget.accounts,
                          secret,
                        );
                        await model.send(
                          secret,
                          confirmation.text,
                          identityToken: proof['identityToken'] as String?,
                        );
                      } on AccountFailure catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                      if (model.accepted) confirmation.clear();
                    },
              child: Text(
                model.pending == null
                    ? 'حذف حسابي نهائيًا'
                    : 'إعادة طلب الحذف بنفس الإيصال',
              ),
            ),
          ],
          if (widget.accounts.user == null && model.pending == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'سجّل الدخول لحذف حسابك، أو استعمل رابط حذف الحساب من المتصفح. حذف التطبيق وحده لا يحذف الحساب.',
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
