import '../accounts/external_auth_ui.dart';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';

class SecurityProtectionPage extends StatefulWidget {
  const SecurityProtectionPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<SecurityProtectionPage> createState() => _SecurityProtectionPageState();
}

class _SecurityProtectionPageState extends State<SecurityProtectionPage> {
  final password = TextEditingController(), code = TextEditingController();
  Map<String, dynamic>? status;
  String? secret, error;
  List<String> recovery = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await widget.accounts.chatRequest('GET', '/v1/me/security');
      if (mounted) setState(() => status = d);
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> action(String name) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final credential = (name == 'setup' || name == 'disable')
          ? await sensitiveCredential(context, widget.accounts, password.text)
          : <String, dynamic>{};
      final d = await widget.accounts.chatRequest(
        'POST',
        '/v1/me/security/$name',
        body: {...credential, if (name != 'setup') 'code': code.text.trim()},
      );
      if (!mounted) return;
      setState(() {
        secret = d['secret'] as String?;
        recovery = (d['recoveryCodes'] as List? ?? []).cast<String>();
      });
      password.clear();
      code.clear();
      await load();
      if (mounted && name == 'verify')
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم التأكيد؛ يمكنك العودة للإدارة لمدة 15 دقيقة.'),
          ),
        );
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = status?['enabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('حماية الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.verified_user_outlined, size: 52),
          const SizedBox(height: 16),
          Text(
            enabled ? 'التحقق بخطوتين مفعّل' : 'التحقق بخطوتين',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'استخدم تطبيق مصادقة على جهازك. احتفظ برموز الاحتياط بمكان آمن خارج التطبيق. كل رمز احتياط يعمل مرة واحدة.',
          ),
          if (status?['available'] == false)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'تحتاج الميزة إعداد مفتاح المصادقة لدى إدارة الخادم أولاً.',
              ),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (recovery.isNotEmpty) ...[
            const Text('احفظ هذه الرموز الآن؛ لن تظهر مرة ثانية:'),
            SelectableText(
              recovery.join('\n'),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 16),
          ],
          if (secret != null) ...[
            const Text(
              'أضف حساب TOMI في تطبيق المصادقة واختر إدخال مفتاح الإعداد يدوياً:',
            ),
            SelectableText(secret!, textDirection: TextDirection.ltr),
            const Text(
              'بعد إضافة المفتاح أدخل الرمز لتأكيد التفعيل. ينتهي الإعداد بعد 10 دقائق.',
            ),
          ],
          if (status?['available'] == true || enabled) ...[
            if (secret == null)
              TextField(
                key: const Key('security-password'),
                controller: password,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور TOMI إن كانت موجودة',
                ),
              ),
            if (enabled || secret != null)
              TextField(
                key: const Key('security-code'),
                controller: code,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'رمز المصادقة أو رمز احتياط',
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => action(
                      enabled
                          ? 'verify'
                          : secret == null
                          ? 'setup'
                          : 'enable',
                    ),
              child: Text(
                enabled
                    ? 'تأكيد إجراء حساس'
                    : secret == null
                    ? 'بدء إعداد المصادقة'
                    : 'تفعيل المصادقة',
              ),
            ),
            if (enabled)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('إيقاف التحقق بخطوتين؟'),
                            content: const Text(
                              'تقل حماية حسابك. يتطلب الإيقاف كلمة المرور ورمز المصادقة.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('رجوع'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('إيقاف'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true) action('disable');
                      },
                child: const Text('إيقاف التحقق بخطوتين'),
              ),
          ],
          if (busy) const LinearProgressIndicator(),
          const Divider(),
          const Text('سجل أمان حسابك'),
          for (final e in status?['events'] as List? ?? [])
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(switch (e['kind']) {
                'login' => 'تسجيل دخول',
                'mfa_enabled' => 'تفعيل المصادقة',
                'mfa_disabled' => 'إيقاف المصادقة',
                'mfa_verified' => 'تأكيد إجراء حساس',
                _ => 'تحديث أمان الحساب',
              }),
              subtitle: Text('${e['created_at']}'),
            ),
        ],
      ),
    );
  }
}
