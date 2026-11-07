import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'external_identity.dart';
import 'account_api.dart';
import 'account_controller.dart';

Future<Map<String, dynamic>> sensitiveCredential(
  BuildContext context,
  AccountController accounts,
  String password,
) async {
  Map<String, dynamic> methods;
  try {
    methods = await accounts.chatRequest('GET', '/v1/me/auth/methods');
  } on AccountFailure catch (e) {
    if (e.status == 404) return {'password': password};
    rethrow;
  }
  if (methods['hasPassword'] != false) return {'password': password};
  await ExternalIdentity.ensure(methods['projectId'] as String?);
  if (!context.mounted)
    throw const AccountFailure('CANCELLED', 'أُلغي التأكيد.');
  final user = FirebaseAuth.instance.currentUser;
  if (user == null)
    throw const AccountFailure(
      'IDENTITY_REAUTH',
      'سجّل دخولك مجدداً بنفس الطريقة لتأكيد هذا الإجراء.',
    );
  final provider = user.providerData.firstOrNull?.providerId;
  String? token;
  if (provider == 'phone') {
    token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PhoneIdentityPage(reauth: true)),
    );
  } else {
    token = await ExternalIdentity.authenticate(switch (provider) {
      'google.com' => 'google',
      'facebook.com' => 'facebook',
      'apple.com' => 'apple',
      _ => throw const AccountFailure(
        'IDENTITY_REAUTH',
        'أعد تسجيل الدخول لتأكيد الإجراء.',
      ),
    }, reauth: true);
  }
  if (token == null) throw const AccountFailure('CANCELLED', 'أُلغي التأكيد.');
  return {'identityToken': token};
}

class IdentityButtons extends StatelessWidget {
  const IdentityButtons({
    super.key,
    required this.enabled,
    required this.onSelected,
    this.busy = false,
  });
  final List<String> enabled;
  final ValueChanged<String> onSelected;
  final bool busy;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) {
      final columns =
          box.maxWidth < 300 || MediaQuery.textScalerOf(c).scale(14) > 20
          ? 1
          : 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('أو اختَر طريقة الدخول', textAlign: TextAlign.center),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in const ['google', 'phone', 'facebook', 'apple'])
                SizedBox(
                  width: (box.maxWidth - (columns - 1) * 10) / columns,
                  child: OutlinedButton.icon(
                    onPressed: busy || !enabled.contains(p)
                        ? null
                        : () => onSelected(p),
                    icon: p == 'google'
                        ? const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : Icon(switch (p) {
                            'phone' => Icons.phone_android,
                            'facebook' => Icons.facebook,
                            _ => Icons.apple,
                          }),
                    label: Text(switch (p) {
                      'google' => 'Google',
                      'phone' => 'رقم الهاتف',
                      'facebook' => 'Facebook',
                      _ => 'Apple',
                    }),
                  ),
                ),
            ],
          ),
          if (enabled.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'طرق الدخول الخارجية تحتاج تفعيل الإدارة وإعداد Firebase.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      );
    },
  );
}

class PhoneIdentityPage extends StatefulWidget {
  const PhoneIdentityPage({super.key, this.reauth = false, this.link = false});
  final bool reauth, link;
  @override
  State<PhoneIdentityPage> createState() => _PhoneIdentityPageState();
}

class _PhoneIdentityPageState extends State<PhoneIdentityPage> {
  final phone = TextEditingController(text: '+964'),
      code = TextEditingController();
  String? verification, error;
  bool sending = false, finishing = false;
  Timer? timer;
  int remaining = 0;
  @override
  void initState() {
    super.initState();
    if (widget.reauth)
      phone.text = FirebaseAuth.instance.currentUser?.phoneNumber ?? '+964';
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> complete(PhoneAuthCredential credential) async {
    if (!mounted || finishing) return;
    setState(() => finishing = true);
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      final result = widget.reauth
          ? await user!.reauthenticateWithCredential(credential)
          : widget.link && user != null
          ? await user.linkWithCredential(credential)
          : await auth.signInWithCredential(credential);
      final token = await result.user?.getIdToken(true);
      if (mounted && token != null) Navigator.pop(context, token);
    } catch (e) {
      if (mounted) setState(() => error = ExternalIdentity.message(e));
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  Future<void> send() async {
    final number = phone.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(number)) {
      setState(() => error = 'اكتب رقمك بالصيغة الدولية، مثل +964…');
      return;
    }
    if (sending || remaining > 0) return;
    setState(() {
      sending = true;
      error = null;
      remaining = 60;
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => remaining = remaining > 0 ? remaining - 1 : 0);
      if (remaining == 0) t.cancel();
    });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: number,
        verificationCompleted: (credential) {
          if (mounted) unawaited(complete(credential));
        },
        verificationFailed: (e) {
          if (mounted)
            setState(() {
              error = ExternalIdentity.message(e);
              sending = false;
            });
        },
        codeSent: (id, token) {
          if (mounted)
            setState(() {
              verification = id;
              sending = false;
            });
        },
        codeAutoRetrievalTimeout: (id) {
          if (mounted)
            setState(() {
              verification = id;
              sending = false;
            });
        },
      );
    } catch (e) {
      if (mounted)
        setState(() {
          error = ExternalIdentity.message(e);
          sending = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تأكيد رقم الهاتف')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.sms_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
          'نرسل رمز تحقق إلى رقمك عبر Firebase. بالمتابعة توافق على استخدام Google للرقم لأغراض التحقق ومنع الإساءة. قد تطبّق أجور رسائل حسب الخدمة.',
        ),
        TextField(
          controller: phone,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.phone,
          enabled: !sending && !finishing && !widget.reauth,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف مع رمز البلد',
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: sending || finishing || remaining > 0 ? null : send,
          child: Text(
            remaining > 0
                ? 'إعادة الإرسال بعد $remaining ثانية'
                : verification == null
                ? 'إرسال رمز التحقق'
                : 'إعادة إرسال الرمز',
          ),
        ),
        if (verification != null) ...[
          TextField(
            controller: code,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'رمز التحقق'),
          ),
          FilledButton(
            onPressed: finishing
                ? null
                : () => complete(
                    PhoneAuthProvider.credential(
                      verificationId: verification!,
                      smsCode: code.text.trim(),
                    ),
                  ),
            child: const Text('تأكيد والدخول'),
          ),
        ],
        if (sending || finishing) const LinearProgressIndicator(),
      ],
    ),
  );
}

class AuthMethodsPage extends StatefulWidget {
  const AuthMethodsPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AuthMethodsPage> createState() => _AuthMethodsPageState();
}

class _AuthMethodsPageState extends State<AuthMethodsPage> {
  Map<String, dynamic>? methods;
  List<String> providers = [];
  final password = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final m = await widget.accounts.chatRequest('GET', '/v1/me/auth/methods');
      final p = await widget.accounts.api.publicRequest(
        'GET',
        '/v1/auth/providers',
      );
      if (mounted)
        setState(() {
          methods = m;
          providers = (p['providers'] as List? ?? []).cast<String>();
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> link(String provider) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final current = await sensitiveCredential(
        context,
        widget.accounts,
        password.text,
      );
      await widget.accounts.chatRequest(
        'POST',
        '/v1/me/auth/confirm',
        body: current,
      );
      await ExternalIdentity.ensure(methods?['projectId'] as String?);
      if (!mounted) return;
      String? token;
      if (provider == 'phone') {
        token = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PhoneIdentityPage(link: current['identityToken'] != null),
          ),
        );
      } else
        token = await ExternalIdentity.authenticate(
          provider,
          link: current['identityToken'] != null,
        );
      if (token == null) return;
      await widget.accounts.chatRequest(
        'POST',
        '/v1/me/auth/link',
        body: {
          'identityToken': token,
          if (current['password'] != null) 'password': current['password'],
          if (current['identityToken'] != null)
            'currentIdentityToken': current['identityToken'],
        },
      );
      password.clear();
      await load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم ربط طريقة الدخول بحسابك الحالي.')),
        );
    } catch (e) {
      if (mounted) setState(() => error = ExternalIdentity.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طرق الدخول وربط الحساب')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'اربط طريقة أخرى لتدخل إلى نفس حسابك. لا ندمج الحسابات اعتماداً على البريد أو الاسم؛ إذا كانت الطريقة مرتبطة بحساب آخر نحافظ على الحسابين منفصلين.',
        ),
        if (methods?['hasPassword'] != false)
          TextField(
            controller: password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'كلمة مرور حساب TOMI الحالية',
            ),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        IdentityButtons(enabled: providers, onSelected: link, busy: busy),
        if (busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
