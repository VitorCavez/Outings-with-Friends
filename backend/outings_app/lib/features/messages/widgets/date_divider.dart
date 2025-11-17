// lib/features/messages/widgets/date_divider.dart
import 'package:flutter/material.dart';

class DateDivider extends StatelessWidget {
  const DateDivider(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: c.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(height: 1, thickness: 1, color: c.outlineVariant),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.outlineVariant),
            ),
            child: Text(label, style: textStyle),
          ),
          Expanded(
            child: Divider(height: 1, thickness: 1, color: c.outlineVariant),
          ),
        ],
      ),
    );
  }
}
