import 'dart:async';

import 'package:flutter/material.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_profile.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'ranking_controller.dart';

class ContributionRankingPage extends StatefulWidget {
  const ContributionRankingPage({
    super.key,
    required this.accounts,
    this.roomId,
  });
  final AccountController accounts;
  final String? roomId;
  @override
  State<ContributionRankingPage> createState() =>
      _ContributionRankingPageState();
}

class _ContributionRankingPageState extends State<ContributionRankingPage> {
  late final model = RankingController(widget.accounts, roomId: widget.roomId);
  @override
  void initState() {
    super.initState();
    unawaited(model.load());
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.roomId == null ? 'نجوم تومي' : 'مساهمو الغرفة'),
    ),
    body: AnimatedBuilder(
      animation: model,
      builder: (c, _) => RefreshIndicator(
        onRefresh: model.load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final period in const {
                  'daily': 'اليوم',
                  'weekly': 'هذا الأسبوع',
                  'all': 'كل الوقت',
                }.entries)
                  ChoiceChip(
                    key: ValueKey('ranking-${period.key}'),
                    label: Text(period.value),
                    selected: model.period == period.key,
                    onSelected: (_) => model.load(selected: period.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'الترتيب حسب قيمة الهدايا التجريبية المرسلة. اليوم من منتصف الليل، والأسبوع من الاثنين، بتوقيت بغداد. لا توجد جوائز مالية.',
              style: TextStyle(height: 1.6, color: TomiColors.muted),
            ),
            if (model.loading) const LinearProgressIndicator(),
            if (model.error != null) AccountErrorMessage(model.error!),
            if (!model.loading && model.error == null && model.leaders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'بعد ماكو مساهمات بهالفترة.',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final row in model.leaders)
              Builder(
                builder: (c) {
                  final user = AccountUser.fromJson(
                    row['user'] as Map<String, dynamic>,
                  );
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    leading: AccountAvatar(user, size: 42),
                    title: Text(
                      '${row['rank'] ?? ''} ${user.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'مستوى ${user.identity.level} • ${row['points']} نقطة',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: user.id == widget.accounts.user?.id
                        ? null
                        : () => Navigator.push(
                            c,
                            MaterialPageRoute<void>(
                              builder: (_) => UserAccountPage(
                                accounts: widget.accounts,
                                initialUser: user,
                              ),
                            ),
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}
