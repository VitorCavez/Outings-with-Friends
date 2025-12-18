// lib/features/outings/widgets/itinerary_timeline.dart
import 'dart:math' as math;

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
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load itinerary: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('EEE, MMM d • HH:mm').format(dt.toLocal());
  }

  Future<_ItemFormData?> _openItemEditor({ItineraryItem? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    DateTime? start = existing?.startTime;
    DateTime? end = existing?.endTime;

    final result = await showModalBottomSheet<_ItemFormData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickStart() async {
              final now = DateTime.now();
              final base = start ?? now;
              final date = await showDatePicker(
                context: ctx,
                initialDate: base,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(base),
              );
              if (time == null) return;
              setModalState(() {
                start = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                if (end != null && end!.isBefore(start!)) {
                  end = start!.add(const Duration(hours: 1));
                }
              });
            }

            Future<void> pickEnd() async {
              final now = DateTime.now();
              final base = end ?? start ?? now;
              final date = await showDatePicker(
                context: ctx,
                initialDate: base,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(base),
              );
              if (time == null) return;
              setModalState(() {
                end = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            final bottom = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    existing == null
                        ? 'Add itinerary item'
                        : 'Edit itinerary item',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickStart,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            start == null
                                ? 'Start time'
                                : DateFormat(
                                    'EEE, d MMM • HH:mm',
                                  ).format(start!.toLocal()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickEnd,
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(
                            end == null
                                ? 'End time'
                                : DateFormat(
                                    'EEE, d MMM • HH:mm',
                                  ).format(end!.toLocal()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final title = titleCtrl.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Title is required'),
                                ),
                              );
                              return;
                            }
                            Navigator.of(ctx).pop(
                              _ItemFormData(
                                title: title,
                                notes: notesCtrl.text.trim().isEmpty
                                    ? null
                                    : notesCtrl.text.trim(),
                                startTime: start,
                                endTime: end,
                              ),
                            );
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _addItem() async {
    final data = await _openItemEditor();
    if (data == null) return;

    try {
      final maxOrder = _items.isEmpty
          ? 0
          : _items
                .map((e) => e.orderIndex)
                .fold<int>(0, (prev, v) => math.max(prev, v));
      await _svc.create(
        widget.outingId,
        title: data.title,
        notes: data.notes,
        startTime: data.startTime,
        endTime: data.endTime,
        orderIndex: maxOrder + 1,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create item failed: $e')));
    }
  }

  Future<void> _editItem(ItineraryItem item) async {
    final data = await _openItemEditor(existing: item);
    if (data == null) return;

    try {
      await _svc.update(
        widget.outingId,
        item.id,
        title: data.title,
        notes: data.notes,
        startTime: data.startTime,
        endTime: data.endTime,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update item failed: $e')));
    }
  }

  Future<void> _deleteItem(ItineraryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove “${item.title}” from the itinerary?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ok = await _svc.remove(widget.outingId, item.id);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Delete failed')));
        await _load();
        return;
      }
      setState(() {
        _items.removeWhere((e) => e.id == item.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete item failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primaryText = scheme.onSurface;
    final subtle = scheme.onSurfaceVariant;

    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _loading ? null : _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh itinerary'),
            ),
          ],
        ),
        if (_loading && _items.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4.0),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 4),
        if (_items.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No itinerary yet. Tap "Add item" to create one.',
              style: TextStyle(color: subtle),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (ctx, i) {
              final it = _items[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // timeline dot + line
                  Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i != _items.length - 1)
                        Container(
                          width: 2,
                          height: 40,
                          color: theme.dividerColor,
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: primaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (it.locationName != null)
                          Text(
                            it.locationName!,
                            style: TextStyle(color: subtle),
                          ),
                        if (it.startTime != null || it.endTime != null)
                          Text(
                            '${_fmt(it.startTime)}'
                            '${it.endTime != null ? ' → ${DateFormat('HH:mm').format(it.endTime!.toLocal())}' : ''}',
                            style: TextStyle(color: subtle),
                          ),
                        if (it.notes?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            it.notes!,
                            style: TextStyle(height: 1.3, color: primaryText),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _editItem(it),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _deleteItem(it),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.error,
                              ),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ItemFormData {
  final String title;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;

  _ItemFormData({
    required this.title,
    this.notes,
    this.startTime,
    this.endTime,
  });
}
