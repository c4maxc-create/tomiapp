import '../identity/charisma_badge.dart';
import '../messaging/chat_screens.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_models.dart';
import 'account_profile.dart';
import 'account_widgets.dart';

class AccountSearchPage extends StatefulWidget {
  const AccountSearchPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AccountSearchPage> createState() => _AccountSearchPageState();
}

class _AccountSearchPageState extends State<AccountSearchPage> {
  final input = TextEditingController();
  Timer? debounce;
  List<AccountUser> users = [];
  bool busy = false;
  String? error;
  int generation = 0;
  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  void changed(String text) {
    debounce?.cancel();
    final request = ++generation;
    setState(() {
      error = null;
      users = [];
      busy = text.trim().replaceFirst('@', '').runes.length >= 2;
    });
    if (busy)
      debounce = Timer(
        const Duration(milliseconds: 350),
        () => search(request, text),
      );
  }

  Future<void> search(int request, String text) async {
    try {
      final result = await widget.accounts.search(text);
      if (mounted && request == generation)
        setState(() {
          users = result;
          busy = false;
          error = null;
        });
    } on AccountFailure catch (failure) {
      if (mounted && request == generation)
        setState(() {
          error = failure.message;
          busy = false;
        });
    } catch (_) {
      if (mounted && request == generation)
        setState(() {
          error = 'تعذّر البحث؛ جرّب مرة ثانية.';
          busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('البحث عن أشخاص')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          key: const Key('account-search-input'),
          controller: input,
          autofocus: true,
          maxLength: 40,
          autocorrect: false,
          onChanged: changed,
          decoration: const InputDecoration(
            hintText: 'اكتب الاسم أو اليوزر',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 14),
        if (input.text.trim().replaceFirst('@', '').runes.length < 2)
          const Text(
            'اكتب حرفين على الأقل حتى نبحث عن الحسابات.',
            style: TextStyle(color: TomiColors.muted, height: 1.6),
          )
        else if (busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null) ...[
          AccountErrorMessage(error!),
          OutlinedButton(
            onPressed: () => changed(input.text),
            child: const Text('إعادة المحاولة'),
          ),
        ] else if (users.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('ما لقينا حساب بهذا الاسم.'),
          ),
        for (final user in users)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TomiCard(
              padding: const EdgeInsets.all(6),
              child: ListTile(
                leading: AccountAvatar(user, size: 44),
                title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.displayName), CharismaBadge(user.identity)]),
                subtitle: Text(
                  '@${user.username}',
                  textDirection: TextDirection.ltr,
                ),
                trailing: IconButton(
                  tooltip: 'مراسلة',
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () =>
                      openPrivateChat(context, widget.accounts, user.id),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => UserAccountPage(
                        accounts: widget.accounts,
                        initialUser: user,
                      ),
                    ),
                  );
                  if (mounted) changed(input.text);
                },
              ),
            ),
          ),
      ],
    ),
  );
}
