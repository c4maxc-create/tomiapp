import 'dart:async';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';

class GameInviteSheet extends StatefulWidget {
  const GameInviteSheet({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<GameInviteSheet> createState() => _GameInviteSheetState();
}

class _GameInviteSheetState extends State<GameInviteSheet> {
  Timer? debounce;
  int generation = 0;
  bool loading = false;
  String? error;
  List<AccountUser> users = [];
  void search(String text) {
    debounce?.cancel();
    final request = ++generation;
    setState(() {
      users = [];
      error = null;
      loading = text.trim().length >= 2;
    });
    if (loading)
      debounce = Timer(const Duration(milliseconds: 250), () async {
        try {
          final found = await widget.accounts.search(text.trim());
          if (!mounted || request != generation) return;
          setState(() {
            users = found
                .where((u) => u.id != widget.accounts.user?.id)
                .toList();
            loading = false;
          });
        } catch (_) {
          if (mounted && request == generation)
            setState(() {
              error = 'تعذّر البحث؛ جرّب مجددًا.';
              loading = false;
            });
        }
      });
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            const Text(
              'ادعُ صديقك للعبة',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: search,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'ابحث باسم أو يوزر صديقك',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            Expanded(
              child: ListView(
                children: [
                  for (final user in users)
                    ListTile(
                      leading: AccountAvatar(user, size: 38),
                      title: Text(user.displayName),
                      subtitle: Text('@${user.username}'),
                      trailing: const Icon(Icons.send_outlined),
                      onTap: () => Navigator.pop(context, user.id),
                    ),
                ],
              ),
            ),
            const Text(
              'اختيار الحساب يرسل له كود الغرفة برسالة داخل TOMI.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
