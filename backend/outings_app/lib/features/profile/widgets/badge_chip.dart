// lib/features/profile/widgets/badge_chip.dart
import 'package:flutter/material.dart';

class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
