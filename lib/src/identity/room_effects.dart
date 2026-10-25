import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../accounts/account_widgets.dart';
import '../voice_rooms/room_models.dart';

class RoomEffectsController extends ChangeNotifier {
  RoomEffectsController(Iterable<RoomEvent> seed) {
    for (final e in seed) if (e.sequence > highWater) highWater = e.sequence;
  }
  final waiting = Queue<RoomEvent>();
  RoomEvent? active;
  Timer? timer;
  int highWater = 0;
  bool disposed = false, visible = true;
  void ingest(Iterable<RoomEvent> rows) {
    if (disposed) return;
    final sorted = rows.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final e in sorted) {
      if (e.sequence <= highWater) continue;
      highWater = e.sequence;
      if (!visible || e.kind != 'gift' && e.effect?['kind'] != 'entrance')
        continue;
      final created = DateTime.tryParse(e.data['createdAt'] as String? ?? '');
      if (created != null && DateTime.now().difference(created).inSeconds > 15)
        continue;
      if (waiting.length == 4) waiting.removeFirst();
      waiting.add(e);
    }
    if (active == null) next();
  }

  void next() {
    timer?.cancel();
    active = waiting.isEmpty ? null : waiting.removeFirst();
    if (active != null) timer = Timer(const Duration(seconds: 3), next);
    if (!disposed) notifyListeners();
  }

  void visibility(bool value) {
    visible = value;
    if (!value) {
      timer?.cancel();
      waiting.clear();
      active = null;
      if (!disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    waiting.clear();
    super.dispose();
  }
}

class RoomEffectOverlay extends StatefulWidget {
  const RoomEffectOverlay({super.key, required this.event});
  final RoomEvent event;
  @override
  State<RoomEffectOverlay> createState() => _RoomEffectOverlayState();
}

class _RoomEffectOverlayState extends State<RoomEffectOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  bool reduce = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      animation.stop();
      animation.value = .5;
    } else if (!animation.isAnimating && animation.value == 0) {
      animation.forward();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) animation.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final e = widget.event,
        entrance = e.effect?['kind'] == 'entrance',
        gift = e.gift;
    final style =
        e.effect?['styleId'] as String? ??
        switch (gift?['giftId']) {
          'rose' => 'petals',
          'crown' => 'royal',
          'diamond' => 'crystal',
          'rocket' => 'launch',
          'car' => 'road',
          _ => 'pulse',
        };
    final emoji = entrance
        ? switch (style) {
            'fire' => '🔥',
            'royal' => '👑',
            'comet' => '☄️',
            _ => '✨',
          }
        : switch (gift?['giftId']) {
            'rose' => '🌹',
            'heart' => '💜',
            'applause' => '👏',
            'cake' => '🎂',
            'diamond' => '💎',
            'crown' => '👑',
            'car' => '🏎️',
            'rocket' => '🚀',
            _ => '✨',
          };
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (c, _) => LayoutBuilder(
          builder: (c, box) {
            final t = animation.value,
                opacity = reduce
                    ? 1.0
                    : (t * 6).clamp(0, 1) * (1 - ((t - .8) * 5).clamp(0, 1));
            return Opacity(
              opacity: opacity.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!reduce)
                    CustomPaint(
                      painter: _EffectParticles(t, e.sequence, style),
                    ),
                  Center(
                    child: Transform.translate(
                      offset: reduce
                          ? Offset.zero
                          : Offset(
                              style == 'road' ? (1 - t) * box.maxWidth * .4 : 0,
                              style == 'launch'
                                  ? (1 - t) * 90
                                  : math.sin(t * math.pi) * -14,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              colors: [Color(0xee301a58), Color(0xee102d54)],
                            ),
                            border: Border.all(
                              color: const Color(0xfff6d37c),
                              width: 1.3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66302769),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Text(
                                emoji,
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(fontSize: 36),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entrance
                                          ? '${e.actor.displayName} وصل للسالفة'
                                          : '${e.actor.displayName} أرسل ${e.text} ×${gift?['quantity'] ?? 1}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      entrance
                                          ? 'مستوى المستخدم ${e.actor.identity.level}'
                                          : 'إلى ${e.recipient?.displayName ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xfff6d37c),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              AccountAvatar(e.actor, size: 42),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EffectParticles extends CustomPainter {
  const _EffectParticles(this.t, this.seed, this.style);
  final double t;
  final int seed;
  final String style;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        range = size.shortestSide * .6;
    const colors = [
      Color(0xfff6d37c),
      Color(0xffff72ad),
      Color(0xff6fe1eb),
      Color(0xffb495ff),
    ];
    for (var i = 0; i < 24; i++) {
      final angle = i * 2.399963 + (seed % 17) * .17,
          progress = (t + i * .017) % 1;
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * range * progress;
      final p = Paint()
            ..color = colors[i % 4].withValues(alpha: (1 - progress) * .9),
          r = 2.0 + (i % 4);
      if (style == 'crystal' || style == 'royal') {
        final path = Path()
          ..moveTo(position.dx, position.dy - r)
          ..lineTo(position.dx + r / 2, position.dy)
          ..lineTo(position.dx, position.dy + r)
          ..lineTo(position.dx - r / 2, position.dy)
          ..close();
        canvas.drawPath(path, p);
      } else if (style == 'confetti') {
        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.rotate(angle + t * 4);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: r, height: r * 2),
          p,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(position, r, p);
      }
    }
  }

  @override
  bool shouldRepaint(_EffectParticles old) =>
      old.t != t || old.seed != seed || old.style != style;
}
