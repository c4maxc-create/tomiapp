part of 'admin_page.dart';

Future<void> adjustManagedBalance(
  BuildContext context,
  ModerationController model,
  AccountUser user,
  Map<String, dynamic> state,
) async {
  final amount = TextEditingController(),
      reason = TextEditingController(),
      form = GlobalKey<FormState>();
  var currency = 'coins', withdraw = false;
  final data = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        scrollable: true,
        title: Text('رصيد @${user.username}'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'كوينز: ${_number(state['coins'])} • كارزما: ${_number(state['charisma'])}',
              ),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'نوع الرصيد'),
                items: const [
                  DropdownMenuItem(value: 'coins', child: Text('كوينز')),
                  DropdownMenuItem(value: 'charisma', child: Text('كارزما')),
                ],
                onChanged: (v) => refresh(() => currency = v!),
              ),
              SwitchListTile(
                title: Text(withdraw ? 'سحب من الرصيد' : 'إضافة إلى الرصيد'),
                value: withdraw,
                onChanged: (v) => refresh(() => withdraw = v),
              ),
              TextFormField(
                key: const Key('admin-balance-amount'),
                controller: amount,
                keyboardType: TextInputType.number,
                maxLength: 13,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n <= 0 || n > 9000000000000
                      ? 'اكتب مبلغًا صحيحًا موجبًا.'
                      : null;
                },
              ),
              TextFormField(
                key: const Key('admin-action-reason'),
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'سبب التعديل'),
                validator: (v) => (v ?? '').trim().runes.length < 4
                    ? 'اكتب سببًا من أربعة أحرف.'
                    : null,
              ),
              const Text(
                'تُحفظ العملية باسم منفّذها مع الرصيد قبل التعديل وبعده. سجل الهدايا التاريخي يبقى محفوظًا.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: const Key('confirm-balance'),
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(c, {
                  'action': '${withdraw ? 'withdraw' : 'add'}_$currency',
                  'amount': int.parse(amount.text),
                  'reason': reason.text.trim(),
                });
            },
            child: const Text('تأكيد التعديل'),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    amount.dispose();
    reason.dispose();
  });
  if (data != null && context.mounted)
    await model.runCommand({
      ...data,
      'targetId': user.id,
      'expectedRevision': _number(state['adminRevision']),
    });
}

Future<void> editStaffPermissions(
  BuildContext context,
  ModerationController model,
  AccountUser user,
  Map<String, dynamic> state,
) async {
  final selected =
      (state['permissions'] as List? ??
              staffPermissionLabels.keys.where((p) => p != 'bans').toList())
          .cast<String>()
          .toSet();
  final reason = TextEditingController(), form = GlobalKey<FormState>();
  final data = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        scrollable: true,
        title: Text('صلاحيات @${user.username}'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in staffPermissionLabels.entries)
                CheckboxListTile(
                  key: ValueKey('permission-${e.key}'),
                  title: Text(e.value),
                  value: selected.contains(e.key),
                  onChanged: (v) => refresh(() {
                    if (v == true)
                      selected.add(e.key);
                    else
                      selected.remove(e.key);
                  }),
                ),
              const Text(
                'تعديل الأرصدة وتعيين المشرفين وإنشاء الحسابات المميزة تبقى للمالك.',
              ),
              TextFormField(
                key: const Key('admin-action-reason'),
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'سبب منح أو تعديل الصلاحيات',
                ),
                validator: (v) => (v ?? '').trim().runes.length < 4
                    ? 'اكتب سبب الإجراء.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: const Key('save-staff-permissions'),
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(c, {
                  'permissions': staffPermissionLabels.keys
                      .where(selected.contains)
                      .toList(),
                  'reason': reason.text.trim(),
                });
            },
            child: const Text('حفظ الصلاحيات'),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => reason.dispose());
  if (data != null && context.mounted)
    await model.runCommand({
      ...data,
      'action': 'grant_moderator',
      'targetId': user.id,
      'expectedRevision': _number(state['roleRevision']),
    });
}

Future<void> createManagedAccount(
  BuildContext context,
  ModerationController model,
) async {
  final username = TextEditingController(),
      name = TextEditingController(),
      password = TextEditingController(),
      reason = TextEditingController(),
      form = GlobalKey<FormState>();
  var special = true;
  final data = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        scrollable: true,
        title: const Text('إنشاء حساب جديد'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('managed-username'),
                controller: username,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
                validator: usernameError,
              ),
              TextFormField(
                key: const Key('managed-name'),
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
                validator: nameError,
              ),
              PasswordField(
                controller: password,
                label: 'كلمة مرور الحساب الجديد',
                isNew: true,
                validator: passwordError,
              ),
              CheckboxListTile(
                title: const Text('حساب مميز'),
                value: special,
                onChanged: (v) => refresh(() => special = v == true),
              ),
              TextFormField(
                key: const Key('admin-action-reason'),
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'سبب إنشاء الحساب',
                ),
                validator: (v) => (v ?? '').trim().runes.length < 4
                    ? 'اكتب سبب الإجراء.'
                    : null,
              ),
              const Text(
                'سلم بيانات الدخول لصاحب الحساب ليغيّر كلمة المرور عند أول دخول. بيانات الدخول لا تُكتب في سجل الإدارة.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: const Key('create-managed-account'),
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(c, {
                  'action': 'create_account',
                  'targetId': newRequestId(),
                  'expectedRevision': 0,
                  'username': username.text.trim(),
                  'displayName': name.text.trim(),
                  'password': password.text,
                  'special': special,
                  'reason': reason.text.trim(),
                });
            },
            child: const Text('إنشاء الحساب'),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    username.dispose();
    name.dispose();
    password.dispose();
    reason.dispose();
  });
  if (data == null || !context.mounted) return;
  final done = await model.runCommand(data);
  if (!done || !context.mounted) return;
  final code = model.createdRecoveryCode;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: const Text('تم إنشاء الحساب'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('@${data['username']}'),
          if (code != null) ...[
            const Text('رمز الاسترداد يظهر مرة واحدة. سلّمه لصاحب الحساب.'),
            SelectableText(code, textDirection: TextDirection.ltr),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy),
              label: const Text('نسخ رمز الاسترداد'),
            ),
          ] else
            const Text(
              'تم التحقق من الحساب الموجود دون تغيير كلمة مروره. يمكن لصاحبه تجديد رمز الاسترداد من إعدادات حسابه.',
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('تم')),
      ],
    ),
  );
  model.createdRecoveryCode = null;
}
