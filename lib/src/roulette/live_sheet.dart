import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../identity/charisma_badge.dart';
import 'live_controller.dart';

Future<void> showLiveRoulette(BuildContext context, AccountController accounts, String roomId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * .84, child: LiveRouletteSheet(accounts: accounts, roomId: roomId)),
);

class LiveRouletteSheet extends StatefulWidget {
  const LiveRouletteSheet({super.key, required this.accounts, required this.roomId});
  final AccountController accounts;
  final String roomId;
  @override
  State<LiveRouletteSheet> createState() => _LiveRouletteSheetState();
}
class _LiveRouletteSheetState extends State<LiveRouletteSheet> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final c = LiveRouletteController(widget.accounts, widget.roomId);
  Timer? paintClock;
  late final motion = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  bool foreground = true;
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    c.addListener(updateMotion);
    paintClock = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && foreground && c.state != null) setState(() {}); });
  }
  void updateMotion() {
    if (!mounted) return;
    if (foreground && c.state?['phase'] == 'spinning' && !MediaQuery.disableAnimationsOf(context)) {
      if (!motion.isAnimating) {
        final progress = ((c.serverNow - (c.state!['bettingEndsAt'] as num)) / 7000).clamp(0.0, 1.0).toDouble();
        motion.forward(from: progress);
      }
    } else { motion.stop(); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState value) { foreground = value == AppLifecycleState.resumed; c.lifecycle(foreground); updateMotion(); }
  @override
  void dispose() { paintClock?.cancel(); WidgetsBinding.instance.removeObserver(this); c.removeListener(updateMotion); motion.dispose(); c.dispose(); super.dispose(); }
  Future<void> panel(String title, Widget content) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (_) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .65, child: Column(children: [Padding(padding: const EdgeInsets.all(12), child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), Expanded(child: content)]))),
  );
  Future<void> rules() => panel('طريقة اللعب', ListView(padding: const EdgeInsets.all(18), children: [
    const Text('اختر قيمة القطعة ثم اضغط خانة خلال العد التنازلي. الرهان يُخصم عند تأكيده. مدة الرهان 30 ثانية، الدوران 7 ثوانٍ، وعرض النتيجة 5 ثوانٍ. الجميع يشاهد نتيجة الخادم نفسها.'),
    const SizedBox(height: 12),
    const Text('الربح = مجموع قطعك على الخانة الفائزة × مضاعفها. السلطة تفوّز كل الخانات من فئتها بمضاعف كل خانة. تظهر إحدى السلطتين عشوائيًا كل ساعتين إلى ست ساعات.'),
    const SizedBox(height: 12),
    const Text('النسب التالية للجولات العشوائية العادية. إذا حُددت الجولة من المالك تظهر علامة «جولة يحددها المالك».'),
    for (final p in (c.state?['slots'] as List? ?? [])) ListTile(leading: Text('${p['icon']}', style: const TextStyle(fontSize: 28)), title: Text('${p['label']} ×${p['multiplier']}'), trailing: Text('${p['chancePercent']}%')),
    const Text('جوائز ترتيب اليوم: 2000 و1000 و500 كوينز. يُرتب اليوم حسب مجموع الأرباح وتُصرف الجوائز مرة واحدة عند انتقال اليوم بتوقيت بغداد.'),
  ]));
  Future<void> history() => panel('آخر ثماني جولات', ListView(padding: const EdgeInsets.all(12), children: [
    for (final r in (c.state?['recentRounds'] as List? ?? [])) ListTile(
      leading: Text('${r['result']['icon']}', style: const TextStyle(fontSize: 30)),
      title: Text('${r['result']['label']} • ${r['day']}'),
      subtitle: Text(r['participated'] == true ? 'رهانك ${r['totalBet']} • الربح ${r['payout']} • الصافي ${(r['payout'] as num) - (r['totalBet'] as num)}' : 'لم تشارك في هذه الجولة'),
    ),
  ]));
  Future<void> leaderboard() async {
    try {
      final d = await c.leaderboard(); if (!mounted) return;
      await panel('أبرز الفائزين • ${d['day']}', ListView(padding: const EdgeInsets.all(12), children: [
        for (final pair in (d['users'] as List).indexed) ListTile(
          leading: AccountAvatar(AccountUser.fromJson((pair.$2['user'] as Map).cast<String,dynamic>()), size: 42),
          title: Text('${pair.$1 + 1}. ${pair.$2['user']['displayName']}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الأرباح ${pair.$2['total_payout']} • مرات الفوز ${pair.$2['wins']}'), CharismaBadge(AccountUser.fromJson((pair.$2['user'] as Map).cast<String,dynamic>()).identity)]),
        ),
        if ((d['users'] as List).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد أرباح مسجلة اليوم بعد.')),
      ]));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر تحميل الترتيب؛ حاول مجددًا.'))); }
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: Listenable.merge([c, motion]), builder: (context, _) {
    final d = c.state, phase = d?['phase'] as String? ?? 'waiting';
    final ends = d == null ? 0 : (d[phase == 'betting' ? 'bettingEndsAt' : phase == 'spinning' ? 'spinEndsAt' : 'resultsEndsAt'] as num).toInt();
    final seconds = math.max(0, ((ends - c.serverNow) / 1000).ceil());
    return PopScope(canPop: !c.busy, child: Material(
      color: const Color(0xF2111026), borderRadius: const BorderRadius.vertical(top: Radius.circular(26)), clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Row(children: [
          IconButton(tooltip: 'إغلاق اللعبة', onPressed: c.busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close, color: _gold)),
          const Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: Text('روليت TOMI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _gold)))),
          IconButton(tooltip: 'سجل الجولات', onPressed: history, icon: const Icon(Icons.history, color: _gold)),
          IconButton(tooltip: 'طريقة اللعب', onPressed: rules, icon: const Icon(Icons.help_outline, color: _gold)),
        ]),
        if (c.loading) const LinearProgressIndicator(),
        if (d?['controlled'] == true) const Text('جولة يحددها المالك', style: TextStyle(fontSize: 11, color: _gold)),
        if (c.pending != null) TextButton.icon(key: const Key('live-recover-bet'), onPressed: c.busy ? null : c.submit, icon: const Icon(Icons.restore), label: Text(c.busy ? 'نتحقق من الرهان…' : 'استعادة الرهان')),
        Expanded(child: Stack(children: [
          SingleChildScrollView(child: Column(children: [
        if (c.error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3), child: Text(c.error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFB1C2), fontSize: 12))),
            if (d != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _Board(state: d, now: c.serverNow, seconds: seconds, enabled: c.canBet, onBet: c.bet)),
            const Padding(padding: EdgeInsets.only(top: 5, bottom: 8), child: Wrap(alignment: WrapAlignment.center, spacing: 36, children: [Text('🍖 سلطة اللحوم', style: TextStyle(color: _gold)), Text('🥗 سلطة الفواكه', style: TextStyle(color: _gold))])),
          ])),
          if (d != null && phase == 'results') Positioned.fill(child: ColoredBox(color: const Color(0xD9100C1A), child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${d['result']['icon']}', style: const TextStyle(fontSize: 66)),
            Text('${d['result']['label']}', style: const TextStyle(fontSize: 24, color: _gold, fontWeight: FontWeight.bold)),
            Text(d['myResult']?['participated'] == true ? 'مكافأتك ${d['myResult']['payout']} • رهانك ${d['myResult']['totalBet']}' : 'أنت لم تشارك في هذه الجولة', textAlign: TextAlign.center),
            Text('الجولة القادمة خلال $seconds', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            for (final w in (d['winners'] as List)) ListTile(dense: true, leading: AccountAvatar(AccountUser.fromJson((w['user'] as Map).cast<String,dynamic>()), size: 36), title: Text('${w['user']['displayName']}'), subtitle: CharismaBadge(AccountUser.fromJson((w['user'] as Map).cast<String,dynamic>()).identity), trailing: Text('+${w['payout']}', style: const TextStyle(color: _gold))),
          ]))))),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          IconButton(key: const Key('live-repeat-bet'), tooltip: 'تكرار آخر رهان', onPressed: c.canBet && (d?['lastBets'] as List? ?? []).isNotEmpty ? c.repeat : null, icon: const Icon(Icons.repeat, color: _gold)),
          for (final n in const [5000,1000,100,20]) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: ChoiceChip(label: FittedBox(fit: BoxFit.scaleDown, child: Text('$n')), selected: c.denomination == n, selectedColor: const Color(0xFFBE7A28), onSelected: c.busy || c.pending != null ? null : (_) => c.choose(n)))),
        ])),
        SizedBox(height: 38, child: Row(children: [
          TextButton(onPressed: history, child: const Text('سجل النتائج', style: TextStyle(fontSize: 11, color: _gold))),
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final r in (d?['recentRounds'] as List? ?? [])) Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text('${r['result']['icon']}', style: const TextStyle(fontSize: 23)))]))),
        ])),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 7), child: Row(children: [const Icon(Icons.toll, color: _gold, size: 21), const SizedBox(width: 6), Expanded(child: FittedBox(alignment: AlignmentDirectional.centerStart, fit: BoxFit.scaleDown, child: Text('${d?['coins'] ?? '…'} كوينز', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)))), IconButton(tooltip: 'ترتيب اليوم', onPressed: leaderboard, icon: const Icon(Icons.leaderboard, color: _gold))]))),
      ]),
    ));
  });
}
const _gold = Color(0xFFF5CA72);

class _Board extends StatelessWidget {
  const _Board({required this.state, required this.now, required this.seconds, required this.enabled, required this.onBet});
  final Map<String,dynamic> state;
  final int now, seconds;
  final bool enabled;
  final Future<void> Function(int) onBet;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final size = math.min(box.maxWidth, 380.0), cells = state['slots'] as List, phase = state['phase'];
    var active = -1;
    if (state['result'] != null) {
      final target = (state['result']['displaySlot'] as num).toInt();
      if (phase == 'spinning' && !MediaQuery.disableAnimationsOf(context)) {
        final p = ((now - (state['bettingEndsAt'] as num)) / 7000).clamp(0.0,1.0).toDouble();
        final eased = Curves.easeOutCubic.transform(p);
        active = ((32 + target) * eased).floor() % 8;
      } else { active = target; }
    }
    return Center(child: SizedBox(width: size, height: size, child: Stack(alignment: Alignment.center, children: [
      Positioned.fill(child: CustomPaint(painter: _RingPainter(cells))),
      Container(width: size * .29, height: size * .29, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const RadialGradient(colors: [Color(0xFFFFE6A0), Color(0xFFC58B31), Color(0xFF593917)]), border: Border.all(color: _gold, width: 3), boxShadow: const [BoxShadow(color: Color(0x99EFB24C), blurRadius: 15)]), child: FittedBox(child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(phase == 'betting' ? 'اختر الآن' : phase == 'spinning' ? 'تدور' : 'النتيجة', style: const TextStyle(color: Color(0xFF402A10), fontWeight: FontWeight.w800, fontSize: 12)), Text('$seconds', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF402A10)))])))),
      for (var i = 0; i < cells.length; i++) _cell(size, cells[i] as Map, i, active),
    ])));
  });
  Widget _cell(double size, Map cell, int i, int active) {
    final angle = -math.pi / 2 + i * math.pi / 4, side = size * .205, center = size / 2, radius = size * .365;
    final amount = (state['ownBets'] as List).where((c) => c['slot'] == i).fold<num>(0, (n,c) => n + (c['denomination'] as num));
    return Positioned(left: center + math.cos(angle) * radius - side / 2, top: center + math.sin(angle) * radius - side / 2, width: side, height: side,
      child: Semantics(label: 'رهان على ${cell['label']}، المضاعف ${cell['multiplier']}، رهانك $amount', button: true, enabled: enabled, child: InkWell(key: Key('live-slot-$i'), onTap: enabled ? () => onBet(i) : null, borderRadius: BorderRadius.circular(16), child: Container(
        padding: const EdgeInsets.all(3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: active == i ? const [Color(0xFFFFEDAA), Color(0xFFBF3E30)] : const [Color(0xFFC98C36),Color(0xFF382231),Color(0xFF9C5629)]), border: Border.all(color: active == i ? Colors.white : _gold, width: active == i ? 3 : 2), boxShadow: [BoxShadow(color: (active == i ? Colors.orange : Colors.black).withValues(alpha: .5), blurRadius: active == i ? 18 : 4)]),
        child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${cell['icon']}', style: const TextStyle(fontSize: 29)),
          Text('×${cell['multiplier']}${amount > 0 ? ' • $amount' : ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: _gold)),
          if ((cell['hotRank'] as num) > 0) Text('HOT ${cell['hotRank']}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFFFB7B7))),
        ])),
      ))));
  }
}
class _RingPainter extends CustomPainter {
  _RingPainter(this.cells);
  final List cells;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.width * .25;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var angle = -math.pi / 2;
    for (var i = 0; i < cells.length; i++) {
      final sweep = (cells[i]['chancePercent'] as num) * math.pi / 50;
      canvas.drawArc(rect, angle, sweep, false, Paint()..color = (i.isEven ? _gold : const Color(0xFF7F522B))..style = PaintingStyle.stroke..strokeWidth = 7);
      angle += sweep;
    }
    for (var i = 0; i < 32; i++) {
      final a = i * math.pi / 16;
      canvas.drawCircle(center + Offset(math.cos(a),math.sin(a)) * radius, 2.2, Paint()..color = const Color(0xFFFFE7B0));
    }
  }
  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.cells != cells;
}
