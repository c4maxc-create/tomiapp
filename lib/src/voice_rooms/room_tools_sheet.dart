import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A bounded, scrollable action grid whose labels respect accessibility text size.
class RoomToolsSheet extends StatelessWidget {
  const RoomToolsSheet({
    super.key,
    required this.actions,
    required this.accent,
  });
  final List<(IconData, String, VoidCallback)> actions;
  final Color accent;
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: MediaQuery.sizeOf(context).height < 500 ? .96 : .82,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'وظائف الغرفة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق وظائف الغرفة',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 20),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 460 ? 4 : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 10) / columns;
                  final style = DefaultTextStyle.of(context).style.merge(
                    const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  );
                  var labelHeight = 0.0;
                  for (final action in actions) {
                    final painter = TextPainter(
                      text: TextSpan(text: action.$2, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout(maxWidth: math.max(1, width - 16));
                    labelHeight = math.max(labelHeight, painter.height);
                    painter.dispose();
                  }
                  return GridView.builder(
                    key: const Key('room-tools-grid'),
                    padding: const EdgeInsets.only(bottom: 8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: math.max(100, 29 + 12 + labelHeight + 24),
                    ),
                    itemCount: actions.length,
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return Material(
                        color: accent.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: ValueKey('room-tool-${action.$2}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: action.$3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(action.$1, color: accent, size: 29),
                                const SizedBox(height: 12),
                                Text(
                                  action.$2,
                                  textAlign: TextAlign.center,
                                  style: style,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
