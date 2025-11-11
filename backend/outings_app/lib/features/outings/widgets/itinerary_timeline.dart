// lib/features/outings/widgets/itinerary_timeline.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/itinerary_item.dart';
import '../../../services/api_client.dart';
import '../../../services/itinerary_service.dart';

class ItineraryTimeline extends StatefulWidget {
  const ItineraryTimeline({
    super.key,
    required this.outingId,
    required this.api,
  });

  final String outingId;
  final ApiClient api;

  @override
  State<ItineraryTimeline> createState() => _ItineraryTimelineState();
}

class _ItineraryTimelineState extends State<ItineraryTimeline> {
  late final ItineraryService _svc;
  bool _loading = false;
  List<ItineraryItem> _items = [];

  @override
  void initState() {
    super.initState();
    _svc = ItineraryService(widget.api);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.list(widget.outingId);
      list.sort((a, b) {
        final oi = a.orderIndex.compareTo(b.orderIndex);
        if (oi != 0) return oi;
        final as = a.startTime?.millisecondsSinceEpoch ?? 0;
        final bs = b.startTime?.millisecondsSinceEpoch ?? 0;
        return as.compareTo(bs);
      });
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load itinerary: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('EEE, MMM d • HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No itinerary yet. Add steps from the Plan tab.'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 24),
      itemBuilder: (ctx, i) {
        final it = _items[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // timeline dot
            Column(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (i != _items.length - 1)
                  Container(
                    width: 2, height: 40,
                    color: Theme.of(context).dividerColor,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  if (it.locationName != null)
                    Text(it.locationName!, style: const TextStyle(color: Colors.black54)),
                  if (it.startTime != null || it.endTime != null)
                    Text(
                      '${_fmt(it.startTime)}'
                      '${it.endTime != null ? ' → ${DateFormat('HH:mm').format(it.endTime!)}' : ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  if (it.notes?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(it.notes!, style: const TextStyle(height: 1.3)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
