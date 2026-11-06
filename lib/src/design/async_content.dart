import 'package:flutter/material.dart';
import 'tomi_tokens.dart';

class TomiSkeleton extends StatelessWidget {
  const TomiSkeleton({super.key, this.rows = 3});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'جارٍ تحميل المحتوى',
    child: ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TomiColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: TomiColors.raised,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 140,
                          color: TomiColors.raised,
                        ),
                        const SizedBox(height: 10),
                        Container(height: 10, color: TomiColors.raised),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class TomiRetry extends StatelessWidget {
  const TomiRetry({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: TomiColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: TomiColors.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, color: TomiColors.gold),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  );
}
