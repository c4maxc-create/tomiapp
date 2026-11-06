import 'package:flutter/material.dart';
import '../accounts/account_models.dart';
import '../gaming/game_models.dart';
import '../widgets.dart';
import 'identity_models.dart';

class TomiProgressTiles extends StatelessWidget {
  const TomiProgressTiles({
    super.key,
    required this.user,
    this.compact = false,
  });
  final bool compact;
  final AccountUser user;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: badge(
          context,
          key: const Key('profile-charisma-tile'),
          color: const Color(0xff13bed0),
          label: '${user.identity.charisma}',
          icon: Icons.diamond_rounded,
          onTap: () => showCharismaProgress(context, user.identity),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: badge(
          context,
          key: const Key('profile-game-level-tile'),
          color: const Color(0xffff744c),
          label: 'Lv.${user.gameProgress.level}',
          icon: Icons.sports_esports_rounded,
          onTap: () => showGameProgress(context, user.gameProgress),
        ),
      ),
    ],
  );
  Widget badge(
    BuildContext context, {
    required Key key,
    required Color color,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) => Material(
    key: key,
    color: color,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 5 : 9,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: compact ? 13 : 21),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 12 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _progressSheet(
  BuildContext context,
  String title,
  List<Widget> content,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheetContext) => SizedBox(
    height: MediaQuery.sizeOf(sheetContext).height * .78,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          ...content,
        ],
      ),
    ),
  ),
);

Future<void> showCharismaProgress(
  BuildContext context,
  UserIdentity identity,
) => _progressSheet(context, 'رحلة الكارزما', [
  Text(
    'مستواك الحالي ${identity.charismaLevel} من ${identity.charismaMaxLevel}',
    key: const Key('charisma-current-max'),
    style: const TextStyle(
      fontSize: 20,
      color: TomiColors.gold,
      fontWeight: FontWeight.w800,
    ),
  ),
  const SizedBox(height: 8),
  Text('رصيد دعم الهدايا ${identity.charisma}'),
  const SizedBox(height: 14),
  LinearProgressIndicator(
    value: identity.charismaProgress,
    minHeight: 7,
    borderRadius: BorderRadius.circular(8),
  ),
  const SizedBox(height: 10),
  Text(
    identity.charismaNext == null
        ? 'وصلت إلى آخر مستوى للكارزما ✨'
        : 'باقي ${identity.charismaRemaining} دعم للوصول إلى المستوى ${identity.charismaLevel + 1}',
    key: const Key('charisma-remaining'),
  ),
  const SizedBox(height: 12),
  const Text(
    'تزيد الكارزما من الهدايا والدعم المستلم، ومنها دعم نفسك. اللعب يزيد خبرة اللعب بصورة منفصلة.',
    style: TextStyle(color: TomiColors.muted, height: 1.7),
  ),
  const SizedBox(height: 18),
  for (var level = 0; level < UserIdentity.charismaThresholds.length; level++)
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        level <= identity.charismaLevel
            ? Icons.verified_rounded
            : Icons.lock_outline,
        color: level <= identity.charismaLevel
            ? TomiColors.gold
            : TomiColors.muted,
      ),
      title: Text('المستوى $level'),
      subtitle: Text('${UserIdentity.charismaThresholds[level]} دعم'),
      trailing: level == identity.charismaLevel
          ? const Text('أنت هنا', style: TextStyle(color: TomiColors.accent))
          : null,
    ),
]);

Future<void> showGameProgress(
  BuildContext context,
  GameProgress progress,
) => _progressSheet(context, 'مستوى اللعب', [
  Text(
    'المستوى ${progress.level} من ${GameProgress.maxLevel}',
    style: const TextStyle(
      fontSize: 23,
      color: TomiColors.accent,
      fontWeight: FontWeight.w800,
    ),
  ),
  const SizedBox(height: 8),
  Text('${progress.xp} XP إجمالي'),
  const SizedBox(height: 14),
  LinearProgressIndicator(
    value: progress.progress,
    minHeight: 7,
    borderRadius: BorderRadius.circular(8),
  ),
  const SizedBox(height: 10),
  Text(
    progress.next == null
        ? 'وصلت إلى آخر مستوى ✨'
        : 'باقي ${progress.remaining} XP للمستوى ${progress.level + 1}',
  ),
  const SizedBox(height: 16),
  const Text(
    'أونو والسلم والأفعى وجاكارو والجمل: 60 XP للفائز أو عضو الفريق الفائز و20 XP لإكمال الجولة، بعد 30 ثانية وثلاث حركات فعلية منك. الروليت: 10 XP بعد تسوية الجولة التي شاركت بها، دون ارتباط بحجم رهانك أو ربحك. أول20جولة مؤهلة في اليوم تمنح خبرة، ويتجدد الحد منتصف الليل بتوقيت بغداد. الخروج واللعب التلقائي وحدهما لا يمنحان خبرة.',
    style: TextStyle(height: 1.8, color: TomiColors.muted),
  ),
  const SizedBox(height: 12),
  const Text(
    'الهدايا والشراء لا يرفعان مستوى اللعب. العملات والكارزما وخبرة اللعب أرصدة منفصلة.',
  ),
]);
