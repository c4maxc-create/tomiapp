import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../identity/charisma_badge.dart';
import '../widgets.dart';
import 'live_controller.dart';
import 'live_round.dart';

Future<void> showLiveRoulette(BuildContext context, AccountController accounts, String? roomId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => SizedBox(
    height: MediaQuery.sizeOf(sheetContext).height * .88,
    child: LiveRouletteSheet(accounts: accounts, roomId: roomId),
  ),
);

class LiveRouletteSheet extends StatefulWidget {
  const LiveRouletteSheet({super.key, required this.accounts, required this.roomId});
  final AccountController accounts;
  final String? roomId;
  @override
  State<LiveRouletteSheet> createState() => _LiveRouletteSheetState();
}

class _LiveRouletteSheetState extends State<LiveRouletteSheet> with WidgetsBindingObserver {
  late final c = LiveRouletteController(widget.accounts, widget.roomId);
  final clock = ValueNotifier<int>(0);
  Timer? paintClock;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    paintClock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && foreground && c.state != null) clock.value++;
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    c.lifecycle(foreground);
    if (mounted) setState(() {});
  }
  @override
  void dispose() {
    paintClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose(); c.dispose(); super.dispose();
  }
  Future<void> panel(String title, Widget content) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (sheetContext) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .68,
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        Expanded(child: content),
      ]),
    )),
  );
  Future<void> rules() => panel('طريقة اللعب', ListView(padding: const EdgeInsets.all(18), children: [
    const Text('اختَر القطعة ثم اضغط خانة. الرهان 30 ثانية، الدوران 7 ثوانٍ، والنتيجة وأفضل 3 فائزين 5 ثوانٍ. النتيجة واحدة من الخادم للجميع.'),
    const SizedBox(height: 12),
    const Text('تُخصم القطع عند تأكيد الرهان. الربح = القطع الفائزة × مضاعف خانتها. التكرار يعيد قطع آخر جولة شاركت بها. حد الجولة 80 قطعة.'),
    const SizedBox(height: 12),
    const Text('السلطة تفوّز خانات فئتها، كل خانة بمضاعفها. تظهر إحدى السلطتين عشوائيًا كل ساعتين إلى ست ساعات. HOT يوضح أبرز الخانات، دون كشف مبالغ الآخرين أثناء الرهان.'),
    const SizedBox(height: 12),
    const Text('النسب للجولات العشوائية العادية. الجولة المحددة من المالك تحمل علامة واضحة، ويُحفظ اختياره قبل فتح رهاناتها.'),
    for (final p in (c.state?['slots'] as List? ?? const [])) ListTile(
      leading: Text('${p['icon']}', style: const TextStyle(fontSize: 28)),
      title: Text('${p['label']} ×${p['multiplier']}'), trailing: Text('${p['chancePercent']}%'),
    ),
    const Text('ترتيب اليوم منفصل عن فائزِي الجولة. جوائزه 2000 و1000 و500 كوينز، وتُصرف مرة واحدة عند انتقال اليوم بتوقيت بغداد.'),
  ]));
  Future<void> history() => panel('آخر ثماني جولات', ListView(padding: const EdgeInsets.all(12), children: [
    if ((c.state?['recentRounds'] as List? ?? const []).isEmpty)
      const Padding(padding: EdgeInsets.all(24), child: Text('تظهر النتائج هنا بعد اكتمال أول جولة.')),
    for (final r in (c.state?['recentRounds'] as List? ?? const [])) Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TomiCard(padding: const EdgeInsets.all(12), child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Text('${r['result']['icon']}', style: const TextStyle(fontSize: 30)),
        title: Text('${r['result']['label']} • ${r['day']}'),
        subtitle: Text(r['participated'] == true ? 'رهانك ${r['totalBet']} • الربح ${r['payout']} • الصافي ${(r['payout'] as num) - (r['totalBet'] as num)}' : 'لم تشارك في هذه الجولة'),
      )),
    ),
  ]));
  Future<void> leaderboard() async {
    try {
      final d = await c.leaderboard();
      if (!mounted || !c.current) return;
      await panel('ترتيب اليوم • ${d['day']}', ListView(padding: const EdgeInsets.all(12), children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('هذا ترتيب اليوم؛ أفضل 3 في الجولة يظهرون تلقائيًا عند نهايتها.')),
        for (final pair in (d['users'] as List).indexed) ListTile(
          leading: AccountAvatar(AccountUser.fromJson((pair.$2['user'] as Map).cast<String,dynamic>()), size: 42),
          title: Text('${pair.$1 + 1}. ${pair.$2['user']['displayName']}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الأرباح ${pair.$2['total_payout']} • مرات الفوز ${pair.$2['wins']}'),
            CharismaBadge(AccountUser.fromJson((pair.$2['user'] as Map).cast<String,dynamic>()).identity),
          ]),
        ),
        if ((d['users'] as List).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد أرباح مسجلة اليوم بعد.')),
      ]));
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر تحميل ترتيب اليوم؛ حاول مجددًا.');
    }
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, builder: (context, _) {
    final d = c.state;
    return PopScope(canPop: !c.busy, child: Material(
      color: TomiColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(TomiRadius.sheet)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SizedBox(height: 48, child: Row(children: [
          IconButton(tooltip: 'إغلاق اللعبة', onPressed: c.busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          const Icon(Icons.casino_outlined, size: 19, color: TomiColors.gold),
          const SizedBox(width: 8),
          const Expanded(child: FittedBox(alignment: AlignmentDirectional.centerStart, fit: BoxFit.scaleDown, child: Text('روليت TOMI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: TomiColors.text)))),
          IconButton(tooltip: 'سجل الجولات', onPressed: history, icon: const Icon(Icons.history_rounded)),
          IconButton(tooltip: 'طريقة اللعب', onPressed: rules, icon: const Icon(Icons.help_outline_rounded)),
        ])),
        ValueListenableBuilder<int>(valueListenable: clock, builder: (context, tick, _) => _PhaseStrip(
          round: LiveRoundView(d, c.serverNow), loading: c.loading,
        )),
        _StatusStrip(controller: c),
        Expanded(child: RepaintBoundary(child: ValueListenableBuilder<int>(
          valueListenable: clock,
          builder: (context, tick, _) {
            final round = LiveRoundView(d, c.serverNow);
            return Stack(key: const Key('live-wheel-stage'), fit: StackFit.expand, children: [
              if (d != null) _WheelStage(state: d, controller: c, foreground: foreground),
              if (d == null) Center(child: c.loading ? const CircularProgressIndicator() : const Icon(Icons.wifi_off_rounded, size: 42, color: TomiColors.muted)),
              if (round.phase == LiveRoundPhase.results)
                Positioned.fill(child: _RoundResults(key: ValueKey('live-round-results-${round.id}'), round: round)),
            ]);
          },
        ))),
        _BetStrip(controller: c),
        _RecentStrip(rounds: d?['recentRounds'] as List? ?? const [], onHistory: history),
        SafeArea(top: false, child: SizedBox(height: 44, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            const Icon(Icons.toll_rounded, color: TomiColors.gold, size: 20),
            const SizedBox(width: 8),
            const Text('رصيدك', style: TextStyle(fontSize: 12, color: TomiColors.muted)),
            const SizedBox(width: 8),
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text('${d?['coins'] ?? '…'}', style: const TextStyle(color: TomiColors.gold, fontWeight: FontWeight.w800, fontSize: 17)))),
            IconButton(tooltip: 'ترتيب اليوم', onPressed: c.current ? leaderboard : null, icon: const Icon(Icons.leaderboard_outlined, color: TomiColors.accent)),
          ]),
        ))),
      ]),
    ));
  });
}

class _PhaseStrip extends StatelessWidget {
  const _PhaseStrip({required this.round, required this.loading});
  final LiveRoundView round;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final color = round.phase == LiveRoundPhase.betting ? TomiColors.accent : TomiColors.gold;
    return SizedBox(height: 48, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Expanded(child: Row(children: [
          Icon(round.phase == LiveRoundPhase.betting ? Icons.touch_app_outlined : Icons.timelapse_rounded, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(
            loading ? 'جارٍ الاتصال بالجولة…' : '${round.label}${round.state?['controlled'] == true ? ' • جولة يحددها المالك' : ''}',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
          ))),
          const SizedBox(width: 8),
          FittedBox(child: Text('${round.seconds} ث', style: const TextStyle(fontSize: 13, color: TomiColors.text, fontWeight: FontWeight.w800))),
        ])),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
          minHeight: 3, value: loading ? null : round.progress, color: color, backgroundColor: TomiColors.raised,
        )),
        const SizedBox(height: 5),
      ]),
    ));
  }
}

/// Always occupies the same space: pending, errors and recovery cannot move the wheel.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});
  final LiveRouletteController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = c.busy ? 'نتحقق من الرهان…' : c.error ?? (c.pending != null ? 'محاولة محفوظة؛ استعدها للتحقق من نتيجتها' : c.state?['allowed'] == false ? 'اللعبة غير مفعّلة لحسابك' : 'اختر القطعة ثم اضغط الخانة');
    final color = c.error != null ? TomiColors.pink : TomiColors.muted;
    return SizedBox(key: const Key('live-status-strip'), height: 44, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Material(color: TomiColors.surface, borderRadius: BorderRadius.circular(12), child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: c.error == null ? null : () => showInfo(context, 'حالة الرهان', c.error!),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
          SizedBox(width: 16, height: 16, child: c.busy ? const CircularProgressIndicator(strokeWidth: 2) : Icon(c.error == null ? Icons.info_outline_rounded : Icons.error_outline_rounded, size: 16, color: color)),
          const SizedBox(width: 7),
          Expanded(child: Semantics(label: text, child: FittedBox(alignment: AlignmentDirectional.centerStart, fit: BoxFit.scaleDown, child: Text(text, style: TextStyle(fontSize: 11, color: color))))),
          if (c.pending != null) TextButton(
            key: const Key('live-recover-bet'), onPressed: c.busy || !c.current ? null : c.submit,
            child: const FittedBox(child: Text('استعادة', style: TextStyle(fontSize: 11))),
          ),
        ])),
      )),
    ));
  }
}

class _BetStrip extends StatelessWidget {
  const _BetStrip({required this.controller});
  final LiveRouletteController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(height: 56, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(children: [
      for (final n in const [20,100,1000,5000]) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Semantics(
        selected: c.denomination == n,
        child: Material(
          color: c.denomination == n ? TomiColors.gold : TomiColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: Key('live-chip-$n'), borderRadius: BorderRadius.circular(12),
            onTap: c.current && !c.busy && c.pending == null ? () => c.choose(n) : null,
            child: SizedBox.expand(child: Padding(padding: const EdgeInsets.all(6), child: FittedBox(fit: BoxFit.scaleDown, child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.denomination == n ? TomiColors.background : TomiColors.text))))),
          ),
        ),
      ))),
      IconButton(key: const Key('live-repeat-bet'), tooltip: 'تكرار آخر رهان', onPressed: c.canBet && (c.state?['lastBets'] as List? ?? const []).isNotEmpty ? c.repeat : null, icon: const Icon(Icons.repeat_rounded)),
    ])));
  }
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.rounds, required this.onHistory});
  final List rounds;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) => Container(height: 44, margin: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(
    color: TomiColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: TomiColors.border.withValues(alpha: .6)),
  ), child: Row(children: [
    TextButton(onPressed: onHistory, child: const FittedBox(child: Text('آخر النتائج', style: TextStyle(fontSize: 11)))),
    Expanded(child: rounds.isEmpty ? const Text('تظهر بعد أول جولة', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: TomiColors.muted)) : ListView.builder(
      key: const Key('live-recent-results'), scrollDirection: Axis.horizontal, itemExtent: 35, itemCount: rounds.take(8).length,
      itemBuilder: (context, i) => Tooltip(message: '${rounds[i]['result']['label']}', child: Center(child: Text('${rounds[i]['result']['icon']}', style: const TextStyle(fontSize: 24)))),
    )),
    const SizedBox(width: 8),
  ]));
}

class _WheelStage extends StatelessWidget {
  const _WheelStage({required this.state, required this.controller, required this.foreground});
  final Map<String,dynamic> state;
  final LiveRouletteController controller;
  final bool foreground;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = math.min(400.0, math.max(0.0, constraints.maxWidth - 24));
    final size = math.min(width, math.max(240.0, constraints.maxHeight - 34));
    return SingleChildScrollView(key: const PageStorageKey('live-wheel-scroll'), child: SizedBox(
      height: math.max(constraints.maxHeight, size + 34),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        RepaintBoundary(child: _WheelBoard(state: state, now: () => controller.serverNow, enabled: controller.canBet, foreground: foreground, onBet: controller.bet, size: size)),
        SizedBox(height: 34, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final label in const ['🥗 سلطة الفواكه','🍖 سلطة اللحوم']) Flexible(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 11, color: TomiColors.muted))))),
        ])),
      ]),
    ));
  });
}

class _WheelBoard extends StatefulWidget {
  const _WheelBoard({required this.state, required this.now, required this.enabled, required this.foreground, required this.onBet, required this.size});
  final Map<String,dynamic> state;
  final int Function() now;
  final bool enabled, foreground;
  final Future<void> Function(int) onBet;
  final double size;
  @override
  State<_WheelBoard> createState() => _WheelBoardState();
}
class _WheelBoardState extends State<_WheelBoard> with SingleTickerProviderStateMixin {
  late final motion = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  String? spinningRound;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); syncMotion(); }
  @override
  void didUpdateWidget(covariant _WheelBoard oldWidget) { super.didUpdateWidget(oldWidget); syncMotion(); }
  void syncMotion() {
    final round = LiveRoundView(widget.state, widget.now());
    if (!widget.foreground || !TickerMode.valuesOf(context).enabled || MediaQuery.disableAnimationsOf(context) || round.phase != LiveRoundPhase.spinning) {
      motion.stop(); spinningRound = null; return;
    }
    if (!motion.isAnimating || spinningRound != round.id) {
      spinningRound = round.id; motion.forward(from: round.progress);
    }
  }
  @override
  void dispose() { motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: motion, builder: (context, _) {
    final round = LiveRoundView(widget.state, widget.now()), size = widget.size;
    final active = round.activeSlot(reducedMotion: MediaQuery.disableAnimationsOf(context));
    final cells = widget.state['slots'] as List;
    final amounts = List<num>.filled(8, 0);
    for (final chip in widget.state['ownBets'] as List) amounts[(chip['slot'] as num).toInt()] += chip['denomination'] as num;
    return Directionality(textDirection: TextDirection.ltr, child: SizedBox(key: const Key('live-wheel-board'), width: size, height: size, child: Stack(alignment: Alignment.center, children: [
      const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _RingPainter()))),
      Container(key: const Key('live-wheel-center'), width: size * .29, height: size * .29,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: const RadialGradient(colors: [Color(0xFFFFE9AF), Color(0xFFD3A653), Color(0xFF5D431D)]), border: Border.all(color: TomiColors.gold, width: 2), boxShadow: const [BoxShadow(color: Color(0x33F6CD76), blurRadius: 18)]),
        child: Padding(padding: const EdgeInsets.all(10), child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(round.phase == LiveRoundPhase.betting ? 'اختر الآن' : round.phase == LiveRoundPhase.spinning ? 'تدور' : 'انتظر', textDirection: TextDirection.rtl, style: const TextStyle(color: Color(0xFF392A14), fontSize: 12, fontWeight: FontWeight.w800)),
          Text('${round.seconds}', style: const TextStyle(color: Color(0xFF392A14), fontSize: 34, fontWeight: FontWeight.w900)),
        ]))),
      ),
      for (var i = 0; i < cells.length; i++) cell(cells[i] as Map, i, active, amounts[i]),
    ])));
  });
  Widget cell(Map data, int index, int active, num amount) {
    final size = widget.size, side = size * .205, angle = -math.pi / 2 + index * math.pi / 4, radius = size * .365;
    final selected = active == index;
    return Positioned(left: size / 2 + math.cos(angle) * radius - side / 2, top: size / 2 + math.sin(angle) * radius - side / 2, width: side, height: side,
      child: Semantics(label: 'رهان على ${data['label']}، المضاعف ${data['multiplier']}، رهانك $amount', button: true, enabled: widget.enabled, child: Material(
        color: Colors.transparent, borderRadius: BorderRadius.circular(16),
        child: InkWell(key: Key('live-slot-$index'), onTap: widget.enabled ? () => widget.onBet(index) : null, borderRadius: BorderRadius.circular(16),
          child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: selected ? const [Color(0xFFD89B47),Color(0xFF9D4838)] : const [TomiColors.raised,TomiColors.surface]),
            borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? const Color(0xFFFFE6A8) : TomiColors.gold.withValues(alpha: .7), width: 2),
            boxShadow: [BoxShadow(color: selected ? const Color(0x66F6CD76) : const Color(0x33000000), blurRadius: selected ? 16 : 6)],
          ), child: MediaQuery.withNoTextScaling(child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 10, child: (data['hotRank'] as num) > 0 ? Text('HOT ${data['hotRank']}', style: const TextStyle(fontSize: 8, color: TomiColors.pink, fontWeight: FontWeight.w800)) : const SizedBox(width: 28)),
            Text('${data['icon']}', style: const TextStyle(fontSize: 29, height: 1.1)),
            Text('×${data['multiplier']}', style: const TextStyle(fontSize: 10, color: TomiColors.gold, fontWeight: FontWeight.w700)),
            SizedBox(height: 11, child: Text(amount > 0 ? '$amount' : ' ', style: const TextStyle(fontSize: 9, color: TomiColors.text, fontWeight: FontWeight.w800))),
          ])))),
        ),
      )),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width * .253;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius + 7, Paint()..color = TomiColors.gold.withValues(alpha: .12)..style = PaintingStyle.stroke..strokeWidth = 14);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..shader = const SweepGradient(colors: [TomiColors.gold, Color(0xFF806132), Color(0xFFFFECC1), TomiColors.gold]).createShader(rect)..style = PaintingStyle.stroke..strokeWidth = 5);
    for (var i = 0; i < 32; i++) {
      final a = i * math.pi / 16;
      canvas.drawCircle(center + Offset(math.cos(a),math.sin(a)) * radius, 1.7, Paint()..color = const Color(0xFFFFE7B0));
    }
  }
  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => false;
}

class _RoundResults extends StatelessWidget {
  const _RoundResults({super.key, required this.round});
  final LiveRoundView round;
  @override
  Widget build(BuildContext context) {
    final d = round.state!, result = d['result'] as Map, winners = round.winners;
    return ColoredBox(color: TomiColors.background.withValues(alpha: .94), child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Container(
        padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: TomiColors.surface, borderRadius: BorderRadius.circular(TomiRadius.card), border: Border.all(color: TomiColors.gold.withValues(alpha: .55))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('${result['icon']}', style: const TextStyle(fontSize: 38)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${result['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TomiColors.gold, fontWeight: FontWeight.w900, fontSize: 19)),
              Text(d['myResult']?['participated'] == true ? 'ربحك ${d['myResult']['payout']} • رهانك ${d['myResult']['totalBet']}' : 'لم تشارك في هذه الجولة', style: const TextStyle(fontSize: 11, color: TomiColors.muted)),
            ])),
          ]),
          const Divider(height: 22),
          const Text('أفضل 3 في هذه الجولة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (winners.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('لا يوجد فائز في هذه الجولة', style: TextStyle(color: TomiColors.muted))),
          for (final pair in winners.indexed) winner(pair.$1, pair.$2),
          const SizedBox(height: 8),
          Text('الجولة القادمة خلال ${round.seconds} ث', style: const TextStyle(fontSize: 11, color: TomiColors.accent)),
        ]),
      )),
    )));
  }
  Widget winner(int rank, Map<String,dynamic> row) {
    final user = AccountUser.fromJson((row['user'] as Map).cast<String,dynamic>());
    return Padding(key: ValueKey('live-winner-${user.id}'), padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      SizedBox(width: 23, child: Text('${rank + 1}', style: const TextStyle(color: TomiColors.gold, fontWeight: FontWeight.w900))),
      AccountAvatar(user, size: 34), const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        CharismaBadge(user.identity),
      ])),
      const SizedBox(width: 7),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 100), child: FittedBox(fit: BoxFit.scaleDown, child: Text('+${row['payout']}', style: const TextStyle(color: TomiColors.gold, fontSize: 14, fontWeight: FontWeight.w900)))),
    ]));
  }
}
