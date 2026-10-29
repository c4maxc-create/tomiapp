import 'package:flutter/material.dart';

import 'widgets.dart';

/// TOMI's orbit motif is shared by feed, conversations and account pages.
class TomiSignature extends StatelessWidget {
  const TomiSignature({super.key, this.subtitle = 'مساحتك. ناسك. لحظاتك.'});
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 8, 14, 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF253E51), Color(0xFF252340), Color(0xFF36263E)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: TomiColors.accent.withValues(alpha: .24)),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: TomiColors.accent, width: 2),
          ),
          child: const Icon(
            Icons.blur_on_rounded,
            color: TomiColors.accent,
            size: 31,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'على موجتك',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFBDD2DE),
                  height: 1.5,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.auto_awesome_rounded,
          color: TomiColors.gold,
          size: 23,
        ),
      ],
    ),
  );
}
