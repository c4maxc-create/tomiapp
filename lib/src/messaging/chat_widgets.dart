import '../design/tomi_tokens.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChatPalette {
  ChatPalette(this.dark);
  factory ChatPalette.of(BuildContext c) =>
      ChatPalette(Theme.of(c).brightness == Brightness.dark);
  final bool dark;
  Color get background =>
      dark ? TomiColors.background : const Color(0xFFF2F4F7);
  Color get surface => dark ? TomiColors.surface : Colors.white;
  Color get raised => dark ? TomiColors.raised : const Color(0xFFEDF0F4);
  Color get outgoing => dark ? TomiColors.outgoing : const Color(0xFFD8E8FF);
  Color get incoming => dark ? TomiColors.raised : Colors.white;
  Color get text => dark ? TomiColors.text : const Color(0xFF17212D);
  Color get muted => dark ? TomiColors.muted : const Color(0xFF74808F);
  Color get line => dark ? TomiColors.border : const Color(0xFFE8ECF1);
  Color get accent => TomiColors.accent;
}

class ChatSurface extends StatelessWidget {
  const ChatSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context), base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: p.background,
        colorScheme: base.colorScheme.copyWith(
          primary: p.accent,
          onPrimary: p.dark ? TomiColors.background : Colors.white,
          surface: p.surface,
          onSurface: p.text,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: p.background,
          foregroundColor: p.text,
          titleSpacing: 0,
          scrolledUnderElevation: 0,
          elevation: 0,
        ),
        dividerColor: p.line,
        iconTheme: IconThemeData(color: p.text),
        textTheme: base.textTheme.apply(
          bodyColor: p.text,
          displayColor: p.text,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: p.surface,
          showDragHandle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: p.raised,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: p.accent, width: 1.2),
          ),
          hintStyle: TextStyle(color: p.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 13,
          ),
        ),
      ),
      child: child,
    );
  }
}

String chatTime(DateTime? time, {bool inbox = false}) {
  if (time == null) return '';
  final d = time.toLocal(),
      now = DateTime.now(),
      today = DateTime(now.year, now.month, now.day),
      day = DateTime(d.year, d.month, d.day),
      age = today.difference(day).inDays;
  if (inbox && age == 1) return 'أمس';
  if (inbox && age > 1) return '${d.day}/${d.month}';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String chatDay(DateTime? date) {
  if (date == null) return '';
  final d = date.toLocal(),
      n = DateTime.now(),
      days = DateTime(
        n.year,
        n.month,
        n.day,
      ).difference(DateTime(d.year, d.month, d.day)).inDays;
  return days == 0
      ? 'اليوم'
      : days == 1
      ? 'أمس'
      : '${d.day}/${d.month}/${d.year}';
}

String documentSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';
const animatedStickerIds = ['gif_heart', 'gif_wave', 'gif_party'];
const tomiStickers = {
  'gif_heart': ('قلب متحرك', Icons.favorite_rounded),
  'gif_wave': ('هلا متحركة', Icons.waving_hand_rounded),
  'gif_party': ('احتفال متحرك', Icons.celebration_rounded),
  'hello': ('هلا', Icons.waving_hand_rounded),
  'love': ('أحبك', Icons.favorite_rounded),
  'laugh': ('هههه', Icons.sentiment_very_satisfied_rounded),
  'thanks': ('تسلم', Icons.auto_awesome_rounded),
  'wow': ('واو!', Icons.star_rounded),
  'sad': ('زعلان', Icons.water_drop_rounded),
  'sleep': ('تصبح على خير', Icons.bedtime_rounded),
  'party': ('مبروك!', Icons.celebration_rounded),
  'angry': ('معصّب', Icons.whatshot_rounded),
  'cool': ('على راحتك', Icons.face_retouching_natural_rounded),
  'coffee': ('قهوة؟', Icons.coffee_rounded),
  'hug': ('حضن كبير', Icons.handshake_rounded),
};

class TomiSticker extends StatelessWidget {
  const TomiSticker({super.key, required this.id, this.size = 128});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = tomiStickers[id] ?? tomiStickers['hello']!;
    if (animatedStickerIds.contains(id) &&
        !MediaQuery.disableAnimationsOf(context)) {
      return Semantics(
        label: 'GIF ${s.$1}',
        image: true,
        child: Image.asset(
          'assets/stickers/$id.gif',
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }
    return Semantics(
      label: 'ملصق ${s.$1}',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CustomPaint(painter: _StickerPainter(id))),
            Positioned(
              top: size * .04,
              right: size * .02,
              child: Icon(
                s.$2,
                size: size * .25,
                color: id == 'love'
                    ? const Color(0xFFFF7FA8)
                    : const Color(0xFFFFD979),
              ),
            ),
            Positioned(
              bottom: size * .02,
              left: 0,
              right: 0,
              child: Text(
                s.$1,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: math.max(10, size * .11),
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: ChatPalette.of(context).dark
                      ? const Color(0xFFBBDCFF)
                      : TomiColors.outgoing,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerPainter extends CustomPainter {
  _StickerPainter(this.id);
  final String id;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);
    final body = RRect.fromRectAndRadius(
          const Rect.fromLTWH(25, 28, 80, 77),
          const Radius.circular(31),
        ),
        white = Paint()..color = const Color(0xFFEAF4FF),
        blue = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF94C9FF), Color(0xFF488AE8), Color(0xFF4165C7)],
          ).createShader(body.outerRect);
    canvas.drawShadow(
      Path()..addRRect(body),
      const Color(0xFF0C274A),
      5,
      false,
    );
    final outline = Paint()
      ..color = const Color(0xFFD8EBFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(24, 59), 10, blue);
    canvas.drawCircle(const Offset(106, 59), 10, blue);
    canvas.drawRRect(body, blue);
    canvas.drawRRect(body, outline);
    canvas.drawLine(const Offset(63, 29), const Offset(63, 18), outline);
    canvas.drawCircle(
      const Offset(63, 15),
      6,
      Paint()..color = const Color(0xFFFFD979),
    );
    for (final x in [48.0, 80.0]) {
      if (id == 'sleep') {
        canvas.drawLine(
          Offset(x - 6, 60),
          Offset(x + 6, 60),
          Paint()
            ..color = const Color(0xFF19395D)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, 59), width: 19, height: 24),
          white,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x + 1, 61), width: 8, height: 13),
          Paint()..color = const Color(0xFF153659),
        );
        canvas.drawCircle(Offset(x + 3, 57), 2, white);
      }
    }
    final mouth = Paint()
      ..color = const Color(0xFF183958)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (id == 'wow')
      canvas.drawOval(const Rect.fromLTWH(57, 77, 14, 19), mouth);
    else if (id == 'sad' || id == 'angry')
      canvas.drawArc(
        const Rect.fromLTWH(52, 81, 25, 16),
        math.pi,
        math.pi,
        false,
        mouth,
      );
    else
      canvas.drawArc(
        const Rect.fromLTWH(49, 70, 30, 24),
        0,
        math.pi,
        false,
        mouth,
      );
    canvas.drawOval(
      const Rect.fromLTWH(32, 72, 13, 7),
      Paint()..color = const Color(0xFFFFB1C6).withValues(alpha: .7),
    );
    canvas.drawOval(
      const Rect.fromLTWH(86, 72, 13, 7),
      Paint()..color = const Color(0xFFFFB1C6).withValues(alpha: .7),
    );
    if (id == 'angry') {
      canvas.drawLine(const Offset(40, 43), const Offset(55, 48), mouth);
      canvas.drawLine(const Offset(74, 48), const Offset(89, 43), mouth);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StickerPainter old) => old.id != id;
}

class ChatWallpaper extends CustomPainter {
  ChatWallpaper(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (double y = 20; y < s.height; y += 76) {
      for (double x = 18; x < s.width; x += 76) {
        c.save();
        c.translate(x + (y % 152 == 20 ? 0 : 24), y);
        c.rotate(-.18);
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 24, 18),
            const Radius.circular(6),
          ),
          p,
        );
        c.drawLine(const Offset(6, 18), const Offset(4, 24), p);
        c.drawLine(const Offset(4, 24), const Offset(14, 18), p);
        c.drawCircle(const Offset(42, 33), 7, p);
        c.drawLine(const Offset(40, 44), const Offset(45, 51), p);
        c.drawLine(const Offset(45, 44), const Offset(40, 51), p);
        c.restore();
      }
    }
  }

  @override
  bool shouldRepaint(ChatWallpaper old) => old.color != color;
}
