import 'package:flutter/material.dart';

class DateDivider extends StatelessWidget {
  final String label;
  const DateDivider(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }
}
