import 'package:flutter/material.dart';

import 'design/tomi_tokens.dart';
export 'design/tomi_tokens.dart';

void showNote(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> showInfo(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('تمام'),
        ),
      ],
    ),
  );
}

class TomiCard extends StatelessWidget {
  const TomiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: TomiColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TomiRadius.card),
      side: BorderSide(color: TomiColors.border.withAlpha(140)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44, this.highlight = false});
  final String name;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(highlight ? 3 : 0),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: highlight
            ? const [TomiColors.accent, TomiColors.pink]
            : const [Color(0xFF61519B), Color(0xFF353F68)],
      ),
    ),
    child: Container(
      decoration: const BoxDecoration(
        color: TomiColors.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'T' : String.fromCharCode(name.runes.first),
        style: TextStyle(
          fontSize: size * .38,
          fontWeight: FontWeight.w700,
          color: TomiColors.accent,
        ),
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: const TextStyle(color: TomiColors.muted, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class TinyLabel extends StatelessWidget {
  const TinyLabel(this.text, {super.key, this.color = TomiColors.accent});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class LandscapeArt extends StatelessWidget {
  const LandscapeArt({super.key, this.video = false});
  final bool video;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.6,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: SunsetPainter()),
          if (video)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 68,
              ),
            ),
          Positioned(
            right: 14,
            bottom: 14,
            child: Text(
              video ? 'بطاقة فيديو تجريبية' : 'لحظات تقرّبنا',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (video)
            const Positioned(left: 12, top: 12, child: TinyLabel('00:24')),
        ],
      ),
    ),
  );
}

class SunsetPainter extends CustomPainter {
  const SunsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF594581), Color(0xFFD78CA3), Color(0xFFF2C6AD)],
      ).createShader(area);
    canvas.drawRect(area, sky);
    canvas.drawCircle(
      Offset(size.width * .73, size.height * .38),
      size.height * .13,
      Paint()..color = const Color(0xFFFFDDB2),
    );
    for (var i = 0; i < 3; i++) {
      final base = size.height * (.62 + i * .1);
      final path = Path()..moveTo(0, base);
      path.cubicTo(
        size.width * .25,
        base - 62,
        size.width * .38,
        base + 44,
        size.width * .54,
        base - 16,
      );
      path.cubicTo(
        size.width * .76,
        base - 64,
        size.width * .88,
        base + 34,
        size.width,
        base - 22,
      );
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = [
            const Color(0xFF625078),
            const Color(0xFF3F3B63),
            const Color(0xFF272C4B),
          ][i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant SunsetPainter oldDelegate) => false;
}

class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => TomiCard(
    child: Column(
      children: [
        Icon(icon, size: 54, color: TomiColors.accent),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: TomiColors.muted, height: 1.8),
        ),
      ],
    ),
  );
}
