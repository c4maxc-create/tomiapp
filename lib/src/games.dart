import 'package:flutter/material.dart';

import 'model.dart';
import 'widgets.dart';
import 'accounts/account_controller.dart';
import 'gaming/game_hub.dart';
import 'gaming/csharp_games_page.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key, required this.store, this.accounts, this.visible=true});
  final TomiStore store;
  final AccountController? accounts;
  final bool visible;

  @override
  Widget build(BuildContext context) => accounts == null ? preview(context) : supportsCSharpGames ? CSharpGamesPage(key:ValueKey(accounts!.user?.id),accounts:accounts!,visible:visible) : GameHub(key:ValueKey(accounts!.user?.id),accounts:accounts!,visible:visible);
  Widget preview(BuildContext context) => ListView(key: const PageStorageKey('games-scroll'),
    padding: const EdgeInsets.all(18), children: [
      const SectionHeading('الألعاب', subtitle: 'تحدّي صغير، ووناسة أكبر'),
      TomiCard(child: Row(children: [
        const Icon(Icons.workspace_premium_outlined, color: TomiColors.gold, size: 34),
        const SizedBox(width: 14),
        Expanded(child: Text('مستواك ${store.level}\nارفع XP بتحدّي الأسئلة التجريبي',
          style: const TextStyle(height: 1.7))),
      ])),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = constraints.maxWidth >= 320 * textScale ? 2 : 1;
        final cardWidth = (constraints.maxWidth - 14 * (columns - 1)) / columns;
        final cards = [
          _game(context, 'تحدّي الأسئلة', 'اختبار فردي تجريبي', '🧠', const Color(0xFF5D468E),
            () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => QuizPage(store: store)))),
          _game(context, 'توميرو', 'معاينة بطاقة اللعبة', '♠', const Color(0xFF5E3D69),
            () => _details(context, 'توميرو', 'لعبة الطاولة المخطط لها في TOMI.')),
          _game(context, 'دومينو', 'معاينة بطاقة اللعبة', '🎲', const Color(0xFF3B5479),
            () => _details(context, 'دومينو', 'بطاقة تصميم للعبة الدومينو.')),
          _game(context, 'سلّم وثعبان', 'معاينة بطاقة اللعبة', '🐍', const Color(0xFF675A46),
            () => _details(context, 'سلّم وثعبان', 'بطاقة تصميم للعبة السلم والثعبان.')),
        ];
        // Cards keep their natural height when text wraps or is enlarged.
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final card in cards) SizedBox(width: cardWidth, child: card),
        ]);
      }),
      const SizedBox(height: 20),
      const Text('تحدّي الأسئلة قابل للتجربة. باقي الألعاب بطاقات تصميم، واللعب الجماعي يُضاف لاحقًا.',
        style: TextStyle(color: TomiColors.muted, height: 1.7, fontSize: 12)),
    ]);

  Widget _game(BuildContext context, String title, String subtitle, String symbol, Color color, VoidCallback onTap) =>
    InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Container(
      constraints: const BoxConstraints(minHeight: 170),
      padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [color, TomiColors.surface])),
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(symbol, style: const TextStyle(fontSize: 37)),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: TomiColors.muted, fontSize: 10)),
      ]),
    ));

  void _details(BuildContext context, String name, String body) => showInfo(context, name,
    '$body\nهذه بطاقة تصميم؛ اللعب بهذه اللعبة واللعب الجماعي غير متاحين في نسخة المعاينة.');
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.store});
  final TomiStore store;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const questions = [
    ('شنو عاصمة العراق؟', ['بغداد', 'كربلاء', 'البصرة', 'الموصل'], 0),
    ('كم يوم بالأسبوع؟', ['خمسة', 'ستة', 'سبعة', 'ثمانية'], 2),
    ('شنو الكوكب المعروف بالكوكب الأحمر؟', ['الأرض', 'المشتري', 'الزهرة', 'المريخ'], 3),
    ('شنو أكبر محيط بالعالم؟', ['الأطلسي', 'الهادئ', 'الهندي', 'المتجمد'], 1),
  ];
  int index = 0;
  int score = 0;
  int? choice;
  bool finished = false;

  void next() {
    if (choice == null || finished) return;
    if (choice == questions[index].$3) score++;
    if (index == questions.length - 1) {
      widget.store.awardQuizXp(score * 25);
      setState(() => finished = true);
    } else {
      setState(() { index++; choice = null; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('تحدّي الأسئلة')),
    body: ListView(padding: const EdgeInsets.all(22), children: [
      const TinyLabel('تحدّي فردي تجريبي'),
      const SizedBox(height: 20),
      if (finished) ...[
        FeaturePlaceholder(icon: Icons.emoji_events_outlined, title: 'أحسنت! $score / 4',
          body: 'كسبت ${score * 25} XP تجريبي\nمستوى حسابك الآن: ${widget.store.level}'),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('الرجوع للألعاب')),
      ] else ...[
        Text('السؤال ${index + 1} من ${questions.length}', style: const TextStyle(color: TomiColors.muted)),
        const SizedBox(height: 14),
        LinearProgressIndicator(value: (index + 1) / questions.length,
          color: TomiColors.accent, backgroundColor: TomiColors.raised),
        const SizedBox(height: 28),
        Text(questions[index].$1, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.6)),
        const SizedBox(height: 22),
        for (var option = 0; option < 4; option++) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(onPressed: () => setState(() => choice = option),
            style: OutlinedButton.styleFrom(alignment: Alignment.centerRight,
              backgroundColor: choice == option ? TomiColors.accent.withAlpha(35) : TomiColors.surface,
              side: BorderSide(color: choice == option ? TomiColors.accent : TomiColors.border),
              padding: const EdgeInsets.all(20)),
            child: Text(questions[index].$2[option], style: const TextStyle(fontSize: 17)))),
        const SizedBox(height: 12),
        FilledButton(onPressed: choice == null ? null : next,
          child: Text(index == questions.length - 1 ? 'عرض النتيجة' : 'التالي')),
      ],
    ]),
  );
}
