import '../preferences/network_media_image.dart';
import '../identity/identity_avatar.dart';

import 'package:flutter/material.dart';

import '../widgets.dart';
import 'account_models.dart';

String? usernameError(String? value) =>
    RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch((value ?? '').trim())
    ? null
    : 'استخدم 3 إلى 20 حرفًا إنكليزيًا أو رقمًا أو _';

String? nameError(String? value) {
  final length = (value ?? '').trim().runes.length;
  return length >= 2 && length <= 30 ? null : 'الاسم من حرفين إلى 30 حرفًا';
}

String? passwordError(String? value) {
  final length = (value ?? '').runes.length;
  return length >= 15 && length <= 128
      ? null
      : 'اكتب عبارة مرور من 15 إلى 128 حرفًا';
}

class AccountErrorMessage extends StatelessWidget {
  const AccountErrorMessage(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: TomiCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: TomiColors.pink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: TomiColors.text, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountAvatar extends StatelessWidget {
  const AccountAvatar(this.user, {super.key, this.size = 80});
  final AccountUser user;
  final double size;
  @override
  Widget build(BuildContext context) => IdentityDecoration(
    identity: user.identity,
    size: size,
    name: user.displayName,
    child: base(context),
  );
  Widget base(BuildContext context) {
    if (user.avatarUrl != null)
      return Semantics(
        label: 'صورة ${user.displayName}',
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: NetworkMediaImage(
              user.avatarUrl!,
              key: ValueKey(user.avatarId),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) =>
                  Avatar(user.displayName, size: size, highlight: true),
            ),
          ),
        ),
      );
    final symbol = avatarSymbols[user.avatarPreset] ?? '';
    if (symbol.isEmpty)
      return Avatar(user.displayName, size: size, highlight: true);
    return Semantics(
      label: 'صورة ${user.displayName}',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TomiColors.raised,
          border: Border.all(color: TomiColors.accent, width: 2),
        ),
        child: Text(
          symbol,
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: size * .48),
        ),
      ),
    );
  }
}

class AccountStats extends StatelessWidget {
  const AccountStats(this.user, {super.key});
  final AccountUser user;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stat(user.postsCount, 'منشورات'),
      _stat(user.followersCount, 'متابعون'),
      _stat(user.followingCount, 'يتابع'),
    ],
  );
  Widget _stat(int number, String label) => Expanded(
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$number',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: TomiColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.isNew = false,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool isNew;
  final bool enabled;
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    textDirection: TextDirection.ltr,
    autofillHints: [
      widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
    ],
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.isNew ? 'تگدر تستخدم عبارة طويلة وسهلة تتذكرها' : null,
      helperMaxLines: 3,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: hidden ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
        onPressed: widget.enabled
            ? () => setState(() => hidden = !hidden)
            : null,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
