import 'package:flutter/material.dart';
import 'identity_models.dart';

/// Compact public charisma counter. The accessible label keeps the full value.
class CharismaBadge extends StatelessWidget {
  const CharismaBadge(this.identity, {super.key, this.compact = false});
  final UserIdentity identity;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (identity.charisma <= 0) return const SizedBox.shrink();
    return Semantics(
      excludeSemantics: true,
      label: 'كارزما ${identity.charisma}، المستوى ${identity.charismaLevel}',
      child: Container(
        constraints: BoxConstraints(maxWidth: compact ? 58 : 126),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0x2224B8C5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x99D2AF64)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            compact ? '${identity.charismaIcon} ${identity.charismaLevel}' : '${identity.charismaIcon} ${identity.charisma} · ${identity.charismaLevel}',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF6D88D) : const Color(0xFF624411)),
          ),
        ),
      ),
    );
  }
}
