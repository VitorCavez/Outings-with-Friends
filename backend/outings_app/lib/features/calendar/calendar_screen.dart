import 'package:flutter/material.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      // No AppBar here so it blends with your main shell’s chrome
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min, // ✅ keeps layout tight & safe
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.event_available_outlined, size: 56, color: c.primary),
              const SizedBox(height: 12),
              Text(
                'Calendar',
                style: t.headlineSmall?.copyWith(color: c.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Your upcoming plans will appear here.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  Chip(
                    label: const Text('Sync coming soon'),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  Chip(
                    label: const Text('Itinerary view'),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
