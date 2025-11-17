// lib/features/profile/widgets/outing_history_list.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/profile_service.dart';

class OutingHistoryList extends StatefulWidget {
  const OutingHistoryList({
    super.key,
    required this.userId,
    required this.profileService,
  });

  final String userId;
  final ProfileService profileService;

  @override
  State<OutingHistoryList> createState() => _OutingHistoryListState();
}

class _OutingHistoryListState extends State<OutingHistoryList> {
  bool _loading = false;
  String _role = 'all'; // all | host | guest
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.profileService.getUserHistory(
        userId: widget.userId,
        role: _role,
        limit: 50,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load history: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDT(dynamic isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString.toString());
    if (dt == null) return '';
    return DateFormat('EEE, MMM d • HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _role == 'all',
              onSelected: (v) {
                if (!v) return;
                setState(() => _role = 'all');
                _load();
              },
            ),
            ChoiceChip(
              label: const Text('Host'),
              selected: _role == 'host',
              onSelected: (v) {
                if (!v) return;
                setState(() => _role = 'host');
                _load();
              },
            ),
            ChoiceChip(
              label: const Text('Guest'),
              selected: _role == 'guest',
              onSelected: (v) {
                if (!v) return;
                setState(() => _role = 'guest');
                _load();
              },
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: LinearProgressIndicator(),
          ),
        if (!_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('No past outings yet.'),
          ),
        if (_items.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (ctx, i) {
              final o = _items[i];
              final title = (o['title'] ?? '') as String;
              final type = (o['outingType'] ?? '') as String;
              final role = (o['role'] ?? '—') as String;
              final rsvp = (o['rsvpStatus'] ?? '') as String?;
              final dtStart = _fmtDT(o['dateTimeStart']);
              final dtEnd = _fmtDT(o['dateTimeEnd']);

              return ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: Text(title),
                subtitle: Text('$type • $dtStart → $dtEnd'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Chip(label: Text(role)),
                    if (rsvp != null && rsvp.isNotEmpty)
                      Text('RSVP: $rsvp', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                onTap: () {
                  final id = (o['id'] ?? '').toString();
                  if (id.isNotEmpty) {
                    Navigator.of(context).pushNamed('/outings/$id');
                  }
                },
              );
            },
          ),
      ],
    );
  }
}
