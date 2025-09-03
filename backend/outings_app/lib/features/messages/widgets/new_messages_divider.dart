import 'package:flutter/material.dart';

class NewMessagesDivider extends StatelessWidget {
  const NewMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent),
            ),
            child: const Text(
              'New messages',
              style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
            ),
          ),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }
}
