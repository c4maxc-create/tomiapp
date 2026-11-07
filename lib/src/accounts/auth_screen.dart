import 'external_identity.dart';
import 'external_auth_ui.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import '../privacy/privacy_screens.dart';

enum AuthMode { login, register, recover }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  final name = TextEditingController();
  final password = TextEditingController();
  final mfaCode = TextEditingController();
  bool needsMfa = false;
  List<String> identityProviders = [];
  String? identityProject;
  final confirmation = TextEditingController();
  final recovery = TextEditingController();
  AuthMode mode = AuthMode.login;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(widget.accounts.api.warmUp());
    unawaited(loadProviders());
  }

  Future<void> loadProviders() async {
    try {
      final d = await widget.accounts.api.publicRequest(
        'GET',
        '/v1/auth/providers',
      );
      if (mounted)
        setState(() {
          identityProject = d['projectId'] as String?;
          identityProviders = (d['providers'] as List? ?? []).cast<String>();
        });
    } catch (_) {}
  }

  Future<void> externalLogin(String provider) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ExternalIdentity.ensure(identityProject);
      if (!mounted) return;
      String? token;
      if (provider == 'phone') {
        token = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const PhoneIdentityPage()),
        );
      } else
        token = await ExternalIdentity.authenticate(provider);
      if (token == null) return;
      try {
        await widget.accounts.federatedLogin(token);
      } on AccountFailure catch (e) {
        if (e.code != 'MFA_REQUIRED' || !mounted) rethrow;
        final code = TextEditingController();
        final value = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('التحقق بخطوتين'),
            content: TextField(
              controller: code,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'رمز المصادقة أو رمز احتياط',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('رجوع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, code.text.trim()),
                child: const Text('تأكيد'),
              ),
            ],
          ),
        );
        if (value == null) return;
        await widget.accounts.federatedLogin(token, mfaCode: value);
      }
    } catch (e) {
      if (mounted) setState(() => error = ExternalIdentity.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      username,
      name,
      password,
      mfaCode,
      confirmation,
      recovery,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void switchMode(AuthMode value) {
    setState(() {
      mode = value;
      needsMfa = false;
      mfaCode.clear();
      error = null;
      password.clear();
      confirmation.clear();
      recovery.clear();
    });
    form.currentState?.reset();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      switch (mode) {
        case AuthMode.login:
          await widget.accounts.login(
            username.text,
            password.text,
            mfaCode: needsMfa ? mfaCode.text.trim() : null,
          );
          break;
        case AuthMode.register:
          await widget.accounts.register(
            username.text,
            name.text,
            password.text,
          );
          break;
        case AuthMode.recover:
          await widget.accounts.recover(
            username.text,
            recovery.text,
            password.text,
            mfaCode: needsMfa ? mfaCode.text.trim() : null,
          );
          break;
      }
    } on AccountFailure catch (failure) {
      if (mounted)
        setState(() {
          error = failure.message;
          if (failure.code == 'MFA_REQUIRED') needsMfa = true;
        });
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر إكمال العملية؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = mode == AuthMode.login
        ? 'أهلًا برجعتك'
        : mode == AuthMode.register
        ? 'مكانك يبدأ هنا'
        : 'نرجّع حسابك';
    final action = mode == AuthMode.login
        ? 'تسجيل الدخول'
        : mode == AuthMode.register
        ? 'إنشاء حساب'
        : 'استرجاع الحساب';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              children: [
                const Center(
                  child: Text(
                    'TOMI',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                      color: TomiColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'لحظاتك، أصدقاءك، وعالمك',
                    style: TextStyle(color: TomiColors.muted),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  mode == AuthMode.recover
                      ? 'استخدم رمز الاسترجاع اللي حفظته عند إنشاء الحساب.'
                      : 'يوزر وباسوورد، بدون إيميل أو رقم هاتف.',
                  style: const TextStyle(color: TomiColors.muted, height: 1.6),
                ),
                const SizedBox(height: 22),
                AutofillGroup(
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mode == AuthMode.register) ...[
                          TextFormField(
                            key: const Key('account-name'),
                            controller: name,
                            enabled: !busy,
                            maxLength: 30,
                            validator: nameError,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'اسمك',
                              errorMaxLines: 3,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          key: const Key('account-username'),
                          controller: username,
                          enabled: !busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.username],
                          validator: usernameError,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'اليوزر',
                            prefixText: '@',
                            errorMaxLines: 3,
                          ),
                        ),
                        if (mode == AuthMode.recover) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('account-recovery'),
                            controller: recovery,
                            enabled: !busy,
                            autocorrect: false,
                            textDirection: TextDirection.ltr,
                            validator: (value) =>
                                RegExp(r'^[A-Fa-f0-9]{40}$').hasMatch(
                                  (value ?? '').replaceAll(
                                    RegExp(r'[\s-]'),
                                    '',
                                  ),
                                )
                                ? null
                                : 'الصق رمز الاسترجاع كاملًا',
                            decoration: const InputDecoration(
                              labelText: 'رمز الاسترجاع',
                              errorMaxLines: 3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (needsMfa && mode != AuthMode.register) ...[
                          TextFormField(
                            key: const Key('account-mfa'),
                            controller: mfaCode,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'رمز المصادقة أو رمز احتياط',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'أدخل رمز المصادقة'
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        PasswordField(
                          key: const Key('account-password'),
                          controller: password,
                          label: mode == AuthMode.recover
                              ? 'كلمة المرور الجديدة'
                              : 'كلمة المرور',
                          isNew: mode != AuthMode.login,
                          enabled: !busy,
                          validator: mode != AuthMode.login
                              ? passwordError
                              : (value) => (value ?? '').isEmpty
                                    ? 'اكتب كلمة المرور'
                                    : null,
                        ),
                        if (mode != AuthMode.login) ...[
                          const SizedBox(height: 16),
                          PasswordField(
                            key: const Key('account-confirmation'),
                            controller: confirmation,
                            label: 'تأكيد كلمة المرور',
                            isNew: true,
                            enabled: !busy,
                            validator: (value) => value == password.text
                                ? null
                                : 'كلمتا المرور مختلفتان',
                          ),
                        ],
                        if (error != null) AccountErrorMessage(error!),
                        if (busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 14),
                            child: Text(
                              'جارٍ الاتصال بالخدمة… قد يحتاج الاتصال الأول بعض الوقت.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: TomiColors.muted,
                                height: 1.6,
                              ),
                            ),
                          ),
                        const SizedBox(height: 22),
                        if (mode == AuthMode.register)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'بإنشاء حساب، تقر بقراءة شروط الاستخدام وقواعد المجتمع وسياسة الخصوصية. يمكنك فتحها أدناه قبل المتابعة.',
                              style: TextStyle(height: 1.6),
                            ),
                          ),
                        FilledButton(
                          key: const Key('account-submit'),
                          onPressed: busy ? null : submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(action),
                          ),
                        ),
                        if (mode == AuthMode.login)
                          IdentityButtons(
                            enabled: identityProviders,
                            onSelected: externalLogin,
                            busy: busy,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('auth-privacy'),
                  onPressed: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PrivacyCenterPage(accounts: widget.accounts),
                          ),
                        ),
                  child: const Text('الخصوصية والشروط وحذف الحساب'),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (mode != AuthMode.register)
                      TextButton(
                        key: const Key('auth-switch-register'),
                        onPressed: busy
                            ? null
                            : () => switchMode(AuthMode.register),
                        child: const Text('إنشاء حساب جديد'),
                      ),
                    if (mode != AuthMode.login)
                      TextButton(
                        key: const Key('auth-switch-login'),
                        onPressed: busy
                            ? null
                            : () => switchMode(AuthMode.login),
                        child: const Text('عندي حساب'),
                      ),
                    if (mode != AuthMode.recover)
                      TextButton(
                        key: const Key('auth-switch-recover'),
                        onPressed: busy
                            ? null
                            : () => switchMode(AuthMode.recover),
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                  ],
                ),
                if (mode == AuthMode.register)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'اسمك ويوزرك ونبذتك يظهرون للمستخدمين. بعد التسجيل نحفظ لك رمز استرجاع خاص.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TomiColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RecoveryCodeScreen extends StatelessWidget {
  const RecoveryCodeScreen({
    super.key,
    required this.code,
    required this.onSaved,
  });
  final String code;
  final VoidCallback onSaved;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('احفظ رمز الاسترجاع')),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Icon(Icons.key_rounded, color: TomiColors.gold, size: 58),
        const SizedBox(height: 20),
        const Text(
          'هذا مفتاح رجعتك للحساب',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'احفظه بمكان خاص وآمن. تحتاجه إذا نسيت كلمة المرور؛ كل استخدام يبدّله برمز جديد.',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 22),
        TomiCard(
          child: SelectableText(
            code.split('-').join('\n'),
            key: const Key('recovery-code'),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              height: 1.6,
              letterSpacing: 1,
              color: TomiColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) showNote(context, 'نسخنا الرمز');
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('نسخ الرمز'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('recovery-saved'),
          onPressed: onSaved,
          child: const Text('حفظت الرمز، نكمل'),
        ),
      ],
    ),
  );
}
