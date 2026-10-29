import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pending_store.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../widgets.dart';

String rouletteRequestId() {
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String roulettePrizeText(Map p) => switch (p['kind'] ?? 'coins') {
  'charisma' => '+${p['coins']} كارزما',
  'frame' => 'إطار • ${p['days']} أيام',
  'entrance' => 'دخول • ${p['days']} أيام',
  'none' => 'حظ أوفر',
  _ => '+${p['coins']} كوينز',
};

class RoulettePage extends StatefulWidget {
  const RoulettePage({super.key, required this.accounts, required this.roomId});
  final AccountController accounts;
  final String roomId;
  @override
  State<RoulettePage> createState() => _RoulettePageState();
}

class _RoulettePageState extends State<RoulettePage>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final userId = widget.accounts.user!.id;
  late final session = widget.accounts.sessionRevision;
  bool get current =>
      mounted &&
      widget.accounts.user?.id == userId &&
      widget.accounts.sessionRevision == session;
  String get storageKey =>
      'tomi.roulette.pending.${widget.accounts.api.baseUrl}.$userId.${widget.roomId}';
  Map<String, dynamic>? state, result;
  List<Map<String, dynamic>> prizes = [];
  String? error, pendingId;
  bool loading = true, busy = false;
  double from = 0, target = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final prefs = await RoulettePendingStore.getInstance();
      final saved = await prefs.getString(storageKey);
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/rooms/${widget.roomId}/roulette',
      );
      if (!current) return;
      setState(() {
        state = d;
        pendingId = saved;
        prizes = (d['config']['prizes'] as List)
            .map((p) => (p as Map).cast<String, dynamic>())
            .toList();
      });
    } on AccountFailure catch (f) {
      if (current) setState(() => error = f.message);
    } catch (_) {
      if (current) setState(() => error = 'تعذّر تحميل الروليت؛ جرّب مجددًا.');
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  Future<void> spin() async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final prefs = await RoulettePendingStore.getInstance();
      if (!current) return;
      pendingId ??= rouletteRequestId();
      final saved = await prefs.setString(storageKey, pendingId!);
      if (!saved) throw StateError('Pending spin could not be saved');
      if (!current) return;
      final d = await widget.accounts.chatRequest(
        'POST',
        '/v1/rooms/${widget.roomId}/roulette/spin',
        body: {'requestId': pendingId},
      );
      if (!current) return;
      final items = (d['prizes'] as List)
          .map((p) => (p as Map).cast<String, dynamic>())
          .toList();
      final index = (d['index'] as num).toInt();
      final normalized =
          (2 * math.pi - index * 2 * math.pi / items.length) % (2 * math.pi);
      from = target % (2 * math.pi);
      target = from + 8 * math.pi + (normalized - from) % (2 * math.pi);
      setState(() {
        prizes = items;
        result = null;
      });
      if (!MediaQuery.disableAnimationsOf(context)) {
        await animation.forward(from: 0).orCancel;
      } else {
        animation.value = 1;
      }
      if (!current) return;
      HapticFeedback.mediumImpact();
      setState(() {
        result = d;
        state = {
          ...state!,
          'remaining': d['remaining'],
          'recent': [
            d,
            ...(state?['recent'] as List? ?? []).where(
              (r) => r['requestId'] != d['requestId'],
            ),
          ].take(10).toList(),
        };
      });
      await prefs.remove(storageKey);
      pendingId = null;
      widget.accounts.voiceRooms.applyWallet({
        'coins': d['coins'],
        'nextClaim': widget.accounts.voiceRooms.nextClaim,
      });
      widget.accounts.voiceRooms.notify();
      try {
        await widget.accounts.reloadMe();
      } catch (_) {
        /* Rewards are already committed; profile can refresh later. */
      }
    } on AccountFailure catch (f) {
      // Definite rejections never consume a turn. Transport failures keep the
      // same request id so Retry recovers the original server result.
      if (f.status >= 400 && f.status < 500) {
        final prefs = await RoulettePendingStore.getInstance();
        await prefs.remove(storageKey);
        pendingId = null;
      }
      if (current)
        setState(() {
          error = f.message;
          if (state != null && f.code == 'ROULETTE_LIMIT')
            state = {...state!, 'remaining': 0};
          if (state != null && f.code == 'ROULETTE_ACCESS')
            state = {...state!, 'allowed': false};
        });
    } on TickerCanceled {
      /* The room page was closed during animation. */
    } catch (_) {
      if (current)
        setState(() => error = 'تعذّر تأكيد النتيجة؛ اضغط استعادة المحاولة.');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = state?['allowed'] == true,
        remaining = (state?['remaining'] as num?)?.toInt() ?? 0;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدار الحظ • TOMI'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton.icon(
              key: const Key('roulette-spin'),
              onPressed:
                  !busy &&
                      !loading &&
                      state != null &&
                      (pendingId != null || allowed && remaining > 0)
                  ? spin
                  : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.casino_outlined),
              label: Text(
                busy
                    ? 'نؤكّد النتيجة…'
                    : pendingId != null
                    ? 'استعادة المحاولة'
                    : 'دوّر مجانًا',
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'لحظة حظ داخل غرفتك',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'محاولات مجانية • المتبقي اليوم $remaining',
              textAlign: TextAlign.center,
              style: const TextStyle(color: TomiColors.accent),
            ),
            const SizedBox(height: 4),
            const Text(
              'تتجدد المحاولات الساعة 12 ليلًا بتوقيت بغداد.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: TomiColors.muted),
            ),
            if (loading) const LinearProgressIndicator(),
            if (prizes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: animation,
                            builder: (context, _) => Transform.rotate(
                              angle:
                                  from +
                                  (target - from) *
                                      Curves.easeOutCubic.transform(
                                        animation.value,
                                      ),
                              child: CustomPaint(
                                size: const Size.square(380),
                                painter: RoulettePainter(prizes),
                              ),
                            ),
                          ),
                          const Positioned(
                            top: 0,
                            child: Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 46,
                              color: TomiColors.gold,
                            ),
                          ),
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: TomiColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: TomiColors.gold,
                                width: 3,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                busy ? 'TOMI' : 'لفّها',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: TomiColors.gold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (result != null)
              TomiCard(
                child: Column(
                  children: [
                    Text(
                      '${result!['prize']['icon']} ${result!['prize']['label']}',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${roulettePrizeText(result!['prize'] as Map)} • رصيدك ${result!['coins']}',
                      style: const TextStyle(color: TomiColors.gold),
                    ),
                  ],
                ),
              ),
            if (result != null &&
                ['frame', 'entrance'].contains(result!['prize']['kind']))
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'أُضيفت الجائزة لمتجر الغرفة. اضغط العنصر لتفعيله.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TomiColors.pink),
                ),
              ),
            if (state != null && !allowed)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'الروليت غير مفعّلة لحسابك حاليًا.',
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            const SizedBox(height: 20),
            const Text(
              'الجوائز وفرص ظهورها',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final p in prizes)
              ListTile(
                dense: true,
                leading: Text(
                  '${p['icon']}',
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text('${p['label']}'),
                subtitle: Text(roulettePrizeText(p)),
                trailing: Text(
                  '${((p['weight'] as num) * 100 / prizes.fold<num>(0, (a, p) => a + (p['weight'] as num))).toStringAsFixed(1)}%',
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'آخر محاولاتك',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final p in (state?['recent'] as List? ?? []))
              ListTile(
                dense: true,
                title: Text('${p['prize']['icon']} ${p['prize']['label']}'),
                trailing: Text(roulettePrizeText(p['prize'] as Map)),
                subtitle: Text('${p['day']}'),
              ),
          ],
        ),
      ),
    );
  }
}

class RoulettePainter extends CustomPainter {
  RoulettePainter(this.prizes);
  final List<Map<String, dynamic>> prizes;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero),
        radius = size.shortestSide / 2 - 14,
        step = 2 * math.pi / prizes.length;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const colors = [
      Color(0xFF22545A),
      Color(0xFF403253),
      Color(0xFF26516E),
      Color(0xFF6B4B35),
    ];
    for (var i = 0; i < prizes.length; i++) {
      final start = -math.pi / 2 - step / 2 + i * step;
      canvas.drawArc(
        rect,
        start,
        step,
        true,
        Paint()..color = colors[i % colors.length],
      );
      canvas.drawArc(
        rect,
        start,
        step,
        true,
        Paint()
          ..color = TomiColors.gold.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final angle = -math.pi / 2 + i * step;
      final text = TextPainter(
        text: TextSpan(
          text: '${prizes[i]['icon']}\n${prizes[i]['label']}',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * .12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * .65);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * .68);
      text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = TomiColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    for (var i = 0; i < 32; i++) {
      final a = i * math.pi / 16;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * (radius + 7),
        2,
        Paint()..color = TomiColors.gold,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RoulettePainter oldDelegate) =>
      oldDelegate.prizes != prizes;
}
