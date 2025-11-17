// lib/features/outings/widgets/suggested_itinerary_card.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/api_client.dart';

class SuggestedItem {
  final String title;
  final String? locationName;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? notes;
  final int orderIndex;
  SuggestedItem({
    required this.title,
    this.locationName,
    this.startTime,
    this.endTime,
    this.notes,
    required this.orderIndex,
  });

  factory SuggestedItem.fromJson(Map<String, dynamic> j) => SuggestedItem(
    title: j['title'] as String? ?? 'Untitled',
    locationName: j['locationName'] as String?,
    startTime: j['startTime'] != null
        ? DateTime.tryParse(j['startTime'] as String)
        : null,
    endTime: j['endTime'] != null
        ? DateTime.tryParse(j['endTime'] as String)
        : null,
    notes: j['notes'] as String?,
    orderIndex: (j['orderIndex'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toCreateJson() => {
    'title': title,
    if (locationName != null) 'locationName': locationName,
    if (startTime != null) 'startTime': startTime!.toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toIso8601String(),
    if (notes != null) 'notes': notes,
    'orderIndex': orderIndex,
  };
}

class SuggestedItineraryCard extends StatefulWidget {
  const SuggestedItineraryCard({
    super.key,
    required this.outingId,
    required this.api,
  });

  final String outingId;
  final ApiClient api;

  @override
  State<SuggestedItineraryCard> createState() => _SuggestedItineraryCardState();
}

class _SuggestedItineraryCardState extends State<SuggestedItineraryCard> {
  bool _loading = true;
  bool _hidden = false; // becomes true if current itinerary is not empty
  List<SuggestedItem> _items = [];
  bool _adding = false;

  late final DateFormat _dfDate = DateFormat('EEE, MMM d');
  late final DateFormat _dfTime = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _hidden = false;
      _items = [];
    });
    try {
      // 1) Check if current itinerary has items
      final r1 = await widget.api.get(
        '/api/outings/${widget.outingId}/itinerary',
      );
      if (r1.statusCode == 200) {
        final map = jsonDecode(r1.body) as Map<String, dynamic>;
        final List data = (map['data'] as List? ?? []);
        if (data.isNotEmpty) {
          if (mounted) {
            setState(() {
              _hidden = true;
              _loading = false;
            });
          }
          return; // do not show suggested if itinerary already exists
        }
      }

      // 2) Load suggested plan
      final r2 = await widget.api.get(
        '/api/outings/${widget.outingId}/itinerary/suggested',
      );
      if (r2.statusCode != 200) {
        // If endpoint not implemented, just hide card quietly
        if (mounted) {
          setState(() {
            _hidden = true;
            _loading = false;
          });
        }
        return;
      }
      final map2 = jsonDecode(r2.body) as Map<String, dynamic>;
      final List data2 = (map2['data'] as List? ?? []);
      final items = data2
          .map((e) => SuggestedItem.fromJson(e as Map<String, dynamic>))
          .toList()
          .cast<SuggestedItem>();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hidden = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _addAll() async {
    if (_items.isEmpty) return;
    setState(() => _adding = true);
    try {
      for (final it in _items) {
        final r = await widget.api.postJson(
          '/api/outings/${widget.outingId}/itinerary',
          it.toCreateJson(),
        );
        if (r.statusCode != 201 && r.statusCode != 200) {
          throw Exception('Failed to add "${it.title}" (${r.statusCode})');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggested itinerary added')),
      );
      // After adding, hide the card
      setState(() {
        _hidden = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add all failed: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  String _fmtRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return '';
    if (start != null && end != null) {
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      if (sameDay) {
        return '${_dfDate.format(start)} • ${_dfTime.format(start)}–${_dfTime.format(end)}';
      } else {
        return '${_dfDate.format(start)} ${_dfTime.format(start)} → ${_dfDate.format(end)} ${_dfTime.format(end)}';
      }
    }
    if (start != null) {
      return '${_dfDate.format(start)} • ${_dfTime.format(start)}';
    }
    // end != null
    return '${_dfDate.format(end!)} • ${_dfTime.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Suggested plan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: LinearProgressIndicator(),
              ),
            if (!_loading && _items.isEmpty)
              const Text('No suggestions available right now.'),
            if (!_loading && _items.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._items
                  .take(5)
                  .map(
                    (e) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(e.title),
                      subtitle: Text(
                        [
                          if (e.locationName != null) e.locationName!,
                          if (e.startTime != null)
                            'Start: ${_fmtRange(e.startTime, null)}',
                          if (e.endTime != null)
                            'End: ${_dfDate.format(e.endTime!)} • ${_dfTime.format(e.endTime!)}',
                        ].join(' • '),
                        style: TextStyle(color: subtle),
                      ),
                    ),
                  ),
              if (_items.length > 5)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 8),
                  child: Text(
                    '+ ${_items.length - 5} more…',
                    style: TextStyle(color: subtle),
                  ),
                ),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _adding ? null : _addAll,
                    icon: const Icon(Icons.playlist_add),
                    label: _adding
                        ? const Text('Adding…')
                        : const Text('Add all to itinerary'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
