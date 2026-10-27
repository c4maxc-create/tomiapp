import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'identity_models.dart';

class IdentityDecoration extends StatelessWidget {
  const IdentityDecoration({
    super.key,
    required this.identity,
    required this.size,
    required this.name,
    required this.child,
  });
  final UserIdentity identity;
  final double size;
  final String name;
  final Widget child;
  @override
  Widget build(BuildContext c) {
    final base = identity.frameId == 'none' && identity.portraitId == 'none'
        ? child
        : _IdentityMotion(
            identity: identity,
            size: size,
            name: name,
            child: child,
          );
    if (!identity.special) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        PositionedDirectional(
          end: -2,
          bottom: -2,
          child: Semantics(
            label: 'حساب مميز',
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xfff6cd76),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.verified,
                color: const Color(0xff362b57),
                size: math.max(12, size * .25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentityMotion extends StatefulWidget {
  const _IdentityMotion({
    required this.identity,
    required this.size,
    required this.name,
    required this.child,
  });
  final UserIdentity identity;
  final double size;
  final String name;
  final Widget child;
  @override
  State<_IdentityMotion> createState() => _IdentityMotionState();
}

class _IdentityMotionState extends State<_IdentityMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool visible = true, enabled = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    sync();
  }

  void sync() {
    if (enabled && visible) {
      if (!motion.isAnimating) motion.repeat();
    } else {
      motion.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: motion,
      child: widget.child,
      builder: (c, child) {
        final id = widget.identity.portraitId, t = enabled ? motion.value : 0.0;
        final face = id == 'none'
            ? child!
            : Semantics(
                label: 'صورة ${widget.name}',
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xff172d55), Color(0xff553476)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Transform.rotate(
                    angle: math.sin(t * math.pi * 2) * .055,
                    child: Transform.scale(
                      scale: .96 + .04 * math.sin(t * math.pi * 2),
                      child: Text(
                        id == 'moon'
                            ? '🌙'
                            : id == 'panda'
                            ? '🐼'
                            : '✦',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: widget.size * .48,
                          color: const Color(0xffffdd95),
                        ),
                      ),
                    ),
                  ),
                ),
              );
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            foregroundPainter: _IdentityFrame(widget.identity.frameId, t),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipOval(child: face),
            ),
          ),
        );
      },
    ),
  );
}

class _IdentityFrame extends CustomPainter {
  const _IdentityFrame(this.id, this.phase);
  final String id;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    if (id == 'none') return;
    final colors = switch (id) {
      'flame' => const [
        Color(0xffff4b20),
        Color(0xffffc146),
        Color(0xffff204f),
      ],
      'ice' => const [Color(0xff7eeaff), Color(0xffeaffff), Color(0xff6188ff)],
      'rose' => const [Color(0xffff72ad), Color(0xffffd0e4), Color(0xffa970ed)],
      'royal' => const [
        Color(0xffffd77d),
        Color(0xffeaa74f),
        Color(0xfffff0c5),
      ],
      'aurora' => const [
        Color(0xff6fe1eb),
        Color(0xff7e8bff),
        Color(0xffec8cd8),
      ],
      _ => const [Color(0xff6fe1eb), Color(0xffae79f9), Color(0xff6fe1eb)],
    };
    final center = size.center(Offset.zero), radius = size.shortestSide / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
        transform: GradientRotation(phase * math.pi * 2),
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, radius, paint);
    for (var i = 0; i < 3; i++) {
      final a = phase * math.pi * 2 + i * math.pi * 2 / 3;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * radius,
        1.7,
        Paint()..color = colors[i],
      );
    }
    if (id == 'royal') {
      final w = size.width, cx = w / 2;
      final crown = Path()
        ..moveTo(cx - 7, 4)
        ..lineTo(cx - 9, -1)
        ..lineTo(cx - 3, 1)
        ..lineTo(cx, -5)
        ..lineTo(cx + 3, 1)
        ..lineTo(cx + 9, -1)
        ..lineTo(cx + 7, 4)
        ..close();
      canvas.drawPath(crown, Paint()..color = colors.first);
    }
  }

  @override
  bool shouldRepaint(_IdentityFrame old) => id != old.id || phase != old.phase;
}
