import 'external_auth_ui.dart';
import 'social_profile.dart';
import 'avatar_editor.dart';
import '../social/story_screens.dart' show socialBackground;

import 'package:flutter/material.dart';

import '../widgets.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_models.dart';
import 'account_widgets.dart';

class AccountProfileScreen extends StatelessWidget {
  const AccountProfileScreen({
    super.key,
    required this.accounts,
    this.visible = true,
  });
  final AccountController accounts;
  final bool visible;
  @override
  Widget build(BuildContext context) {
    final user = accounts.user;
    return user == null
        ? const SizedBox.shrink()
        : SocialProfileView(
            key: ValueKey(user.id),
            accounts: accounts,
            initialUser: user,
            own: true,
            visible: visible,
          );
  }
}

class EditAccountPage extends StatefulWidget {
  const EditAccountPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends State<EditAccountPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.accounts.user!.displayName,
  );
  late final username = TextEditingController(
    text: widget.accounts.user!.username,
  );
  late final bio = TextEditingController(text: widget.accounts.user!.bio);
  late String avatar = widget.accounts.user!.avatarPreset;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    username.dispose();
    bio.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.accounts.updateProfile(
        username: username.text,
        name: name.text,
        bio: bio.text,
        avatarPreset: avatar,
      );
      if (mounted) {
        Navigator.pop(context);
        showNote(context, 'حفظنا البروفايل');
      }
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر الحفظ؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (widget.accounts.user != null)
            Center(child: AccountAvatar(widget.accounts.user!, size: 96)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('edit-photo-gallery'),
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AvatarEditorPage(accounts: widget.accounts),
                      ),
                    );
                    if (mounted && widget.accounts.user != null)
                      setState(() {
                        avatar = widget.accounts.user!.avatarPreset;
                      });
                  },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('اختيار صورة من الاستوديو'),
          ),
          const Text(
            'اختَر صورتك',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in avatarSymbols.entries)
                ChoiceChip(
                  label: Text(entry.value.isEmpty ? 'حروف اسمي' : entry.value),
                  selected: avatar == entry.key,
                  onSelected: busy
                      ? null
                      : (_) => setState(() => avatar = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 22),
          TextFormField(
            key: const Key('edit-account-name'),
            controller: name,
            enabled: !busy,
            maxLength: 30,
            validator: nameError,
            decoration: const InputDecoration(
              labelText: 'الاسم',
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('edit-account-username'),
            controller: username,
            enabled: !busy,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            validator: usernameError,
            decoration: const InputDecoration(
              labelText: 'اليوزر',
              prefixText: '@',
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('edit-account-bio'),
            controller: bio,
            enabled: !busy,
            minLines: 2,
            maxLines: 4,
            maxLength: 140,
            validator: (value) => (value ?? '').trim().runes.length > 140
                ? 'النبذة بحد أقصى 140 حرفًا'
                : null,
            decoration: const InputDecoration(
              labelText: 'النبذة',
              errorMaxLines: 3,
            ),
          ),
          if (error != null) AccountErrorMessage(error!),
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('save-account'),
            onPressed: busy ? null : save,
            child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ التعديلات'),
          ),
        ],
      ),
    ),
  );
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  String? error;
  bool busy = false;
  bool hasPassword = true;
  @override
  void initState() {
    super.initState();
    widget.accounts
        .chatRequest('GET', '/v1/me/auth/methods')
        .then((d) {
          if (mounted) setState(() => hasPassword = d['hasPassword'] != false);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final proof = await sensitiveCredential(
        context,
        widget.accounts,
        current.text,
      );
      await widget.accounts.changePassword(
        current.text,
        next.text,
        identityToken: proof['identityToken'] as String?,
      );
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر تغيير كلمة المرور؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تغيير كلمة المرور')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'بعد التغيير تنتهي جلساتك القديمة ونجهّز لك رمز استرجاع جديد.',
            style: TextStyle(height: 1.7),
          ),
          const SizedBox(height: 22),
          PasswordField(
            controller: current,
            label: hasPassword
                ? 'كلمة المرور الحالية'
                : 'يتم تأكيد حساب المزوّد عند المتابعة',
            enabled: !busy && hasPassword,
            validator: (value) => hasPassword && (value ?? '').isEmpty
                ? 'اكتب كلمة المرور الحالية'
                : null,
          ),
          const SizedBox(height: 18),
          PasswordField(
            controller: next,
            label: 'كلمة المرور الجديدة',
            enabled: !busy,
            isNew: true,
            validator: passwordError,
          ),
          const SizedBox(height: 18),
          PasswordField(
            controller: confirmation,
            label: 'تأكيد كلمة المرور',
            enabled: !busy,
            isNew: true,
            validator: (value) =>
                value == next.text ? null : 'كلمتا المرور مختلفتان',
          ),
          if (error != null) AccountErrorMessage(error!),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'جارٍ التغيير…' : 'حفظ كلمة المرور'),
          ),
        ],
      ),
    ),
  );
}

class UserAccountPage extends StatelessWidget {
  const UserAccountPage({
    super.key,
    required this.accounts,
    required this.initialUser,
  });
  final AccountController accounts;
  final AccountUser initialUser;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    body: SafeArea(
      child: SocialProfileView(
        accounts: accounts,
        initialUser: initialUser,
        own: initialUser.id == accounts.user?.id,
      ),
    ),
  );
}
