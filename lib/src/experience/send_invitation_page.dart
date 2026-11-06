import 'dart:async';
import 'package:flutter/material.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../social/social_models.dart' show newRequestId;

class SendInvitationPage extends StatefulWidget {
  const SendInvitationPage({
    super.key,
    required this.accounts,
    required this.kind,
    required this.targetId,
  });
  final AccountController accounts;
  final String kind, targetId;
  @override
  State<SendInvitationPage> createState() => _SendInvitationPageState();
}

class _SendInvitationPageState extends State<SendInvitationPage> {
  final input = TextEditingController();
  final requests = <String, String>{}, sent = <String>{};
  List<AccountUser> users = [];
  Timer? timer;
  int epoch = 0;
  bool searching = false;
  String? sending, error;
  late final owner = widget.accounts.user?.id;
  late final session = widget.accounts.sessionRevision;
  bool get current =>
      mounted &&
      widget.accounts.user?.id == owner &&
      widget.accounts.sessionRevision == session;
  void changed(String text) {
    timer?.cancel();
    final e = ++epoch;
    setState(() {
      users = [];
      error = null;
      searching = text.trim().replaceFirst('@', '').length >= 2;
    });
    if (searching)
      timer = Timer(const Duration(milliseconds: 350), () async {
        try {
          final result = await widget.accounts.search(text.trim());
          if (current && e == epoch)
            setState(() => users = result.where((u) => u.id != owner).toList());
        } on AccountFailure catch (f) {
          if (current && e == epoch) setState(() => error = f.message);
        } catch (_) {
          if (current && e == epoch)
            setState(() => error = 'تعذّر البحث؛ جرّب مرة ثانية.');
        } finally {
          if (current && e == epoch) setState(() => searching = false);
        }
      });
  }

  Future<void> send(AccountUser user) async {
    if (!current || sending != null || sent.contains(user.id)) return;
    setState(() {
      sending = user.id;
      error = null;
    });
    try {
      await widget.accounts.chatRequest(
        'POST',
        '/v1/me/invitations',
        body: {
          'recipientId': user.id,
          'kind': widget.kind,
          'targetId': widget.targetId,
          'requestId': requests.putIfAbsent(user.id, newRequestId),
        },
      );
      if (current) setState(() => sent.add(user.id));
    } on AccountFailure catch (f) {
      if (current) setState(() => error = f.message);
    } catch (_) {
      if (current)
        setState(() => error = 'تعذّر تأكيد الدعوة؛ أعد المحاولة بنفس الطلب.');
    } finally {
      if (current) setState(() => sending = null);
    }
  }

  @override
  void dispose() {
    epoch++;
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == 'room' ? 'دعوة إلى الغرفة' : 'دعوة لمشاهدة البث',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'تظهر الدعوة لصديقك في مركز الدعوات. إعداداته الشخصية والحظر تبقى مطبّقة.',
        ),
        TextField(
          controller: input,
          onChanged: changed,
          decoration: const InputDecoration(
            labelText: 'ابحث بالاسم أو اليوزر',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (searching) const LinearProgressIndicator(),
        if (error != null) AccountErrorMessage(error!),
        for (final user in users)
          ListTile(
            leading: AccountAvatar(user, size: 44),
            title: Text(user.displayName),
            subtitle: Text('@${user.username}'),
            trailing: IconButton(
              tooltip: sent.contains(user.id)
                  ? 'تم إرسال الدعوة'
                  : 'إرسال الدعوة',
              onPressed: sending != null || sent.contains(user.id)
                  ? null
                  : () => send(user),
              icon: Icon(
                sent.contains(user.id)
                    ? Icons.check_circle_outline
                    : Icons.send_outlined,
              ),
            ),
          ),
        if (!searching && users.isEmpty && input.text.trim().length >= 2)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('ماكو حسابات مطابقة.'),
          ),
      ],
    ),
  );
}
