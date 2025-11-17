// lib/features/messages/widgets/new_messages_divider.dart
import 'package:flutter/material.dart';
import 'package:outings_app/theme/app_theme.dart';

class NewMessagesDivider extends StatelessWidget {
  const NewMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final brand = theme.extension<BrandColors>();

    // A soft pill that stands out on light & dark without using pure white.
    final bg = c.primaryContainer; // themed container color
    final fg = c.onPrimaryContainer; // readable text color
    final dot = brand?.info ?? c.primary; // tiny accent

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(height: 1, thickness: 1, color: c.outlineVariant),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_manual_record, size: 10, color: dot),
                const SizedBox(width: 6),
                Text(
                  'New messages',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Divider(height: 1, thickness: 1, color: c.outlineVariant),
          ),
        ],
      ),
    );
  }
}
