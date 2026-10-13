import 'package:flutter/material.dart';

import '../widgets.dart';
import '../social/social_screens.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_models.dart';
import 'account_widgets.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  String? error;
  bool loggingOut = false;

  Future<void> refresh() async {
    try {
      await widget.accounts.reloadMe();
      if (mounted) setState(() => error = null);
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    }
  }

  Future<void> logout() async {
    if (loggingOut) return;
    setState(() {
      loggingOut = true;
      error = null;
    });
    try {
      await widget.accounts.logout();
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر إنهاء جلسة الدخول؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.accounts,
    builder: (context, _) {
      final user = widget.accounts.user;
      if (user == null) return const SizedBox.shrink();
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          key: const PageStorageKey('account-profile-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const SectionHeading(
              'حسابي',
              subtitle: 'بياناتك محفوظة، وترافقك بكل جهاز',
            ),
            if (error != null) AccountErrorMessage(error!),
            if (widget.accounts.storageWarning != null)
              AccountErrorMessage(widget.accounts.storageWarning!),
            TomiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: AccountAvatar(user, size: 90)),
                  const SizedBox(height: 16),
                  Text(
                    user.displayName,
                    key: const Key('saved-profile-name'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${user.username}',
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TomiColors.muted),
                  ),
                  if (user.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      user.bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.6),
                    ),
                  ],
                  const SizedBox(height: 22),
                  AccountStats(user),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('edit-account'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            EditAccountPage(accounts: widget.accounts),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل البروفايل'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('my-posts'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('منشوراتي')),
                    body: SocialFeedScreen(
                      accounts: widget.accounts,
                      userId: user.id,
                      title: 'منشوراتي',
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('عرض منشوراتي'),
            ),
            const SizedBox(height: 16),
            TomiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'أمان الحساب',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ChangePasswordPage(accounts: widget.accounts),
                      ),
                    ),
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('تغيير كلمة المرور'),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const Key('account-logout'),
                    onPressed: loggingOut ? null : logout,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(
                      loggingOut ? 'جارٍ تسجيل الخروج…' : 'تسجيل الخروج',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const TomiCard(
              child: Text(
                'الحساب والمنشورات واللايكات والتعليقات فعّالة. المحادثات والغرف والألعاب والأرصدة تبقى معاينة.',
                style: TextStyle(color: TomiColors.muted, height: 1.7),
              ),
            ),
          ],
        ),
      );
    },
  );
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
    appBar: AppBar(title: const Text('تعديل البروفايل')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
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
      await widget.accounts.changePassword(current.text, next.text);
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
            label: 'كلمة المرور الحالية',
            enabled: !busy,
            validator: (value) =>
                (value ?? '').isEmpty ? 'اكتب كلمة المرور الحالية' : null,
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

class UserAccountPage extends StatefulWidget {
  const UserAccountPage({
    super.key,
    required this.accounts,
    required this.initialUser,
  });
  final AccountController accounts;
  final AccountUser initialUser;
  @override
  State<UserAccountPage> createState() => _UserAccountPageState();
}

class _UserAccountPageState extends State<UserAccountPage> {
  late AccountUser user = widget.initialUser;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final fresh = await widget.accounts.userById(user.id);
      if (mounted)
        setState(() {
          user = fresh;
          error = null;
        });
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    }
  }

  Future<void> toggleFollow() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await widget.accounts.follow(user.id, !user.isFollowing);
      if (mounted) setState(() => user = updated);
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('البروفايل')),
    body: RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(22),
        children: [
          if (error != null) AccountErrorMessage(error!),
          TomiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: AccountAvatar(user, size: 90)),
                const SizedBox(height: 18),
                Text(
                  user.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '@${user.username}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TomiColors.muted),
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    user.bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.7),
                  ),
                ],
                const SizedBox(height: 24),
                AccountStats(user),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('follow-account'),
                  onPressed: busy ? null : toggleFollow,
                  icon: Icon(
                    user.isFollowing
                        ? Icons.person_remove_outlined
                        : Icons.person_add_outlined,
                  ),
                  label: Text(
                    busy
                        ? 'جارٍ الحفظ…'
                        : user.isFollowing
                        ? 'إلغاء المتابعة'
                        : 'متابعة',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('منشورات ' + user.displayName)),
                  body: SocialFeedScreen(
                    accounts: widget.accounts,
                    userId: user.id,
                    title: 'منشوراته',
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.grid_view_rounded),
            label: const Text('عرض المنشورات'),
          ),
          const SizedBox(height: 18),
          const Text(
            'المحادثات بين الحسابات تتفعّل في التحديث القادم.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TomiColors.muted, height: 1.6),
          ),
        ],
      ),
    ),
  );
}
