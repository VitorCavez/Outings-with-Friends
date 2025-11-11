// lib/features/profile/widgets/trip_timeline_list.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/profile_service.dart';

class TripTimelineList extends StatefulWidget {
  const TripTimelineList({
    super.key,
    required this.userId,
    required this.profileService,
  });

  final String userId;
  final ProfileService profileService;

  @override
  State<TripTimelineList> createState() => _TripTimelineListState();
}

class _TripTimelineListState extends State<TripTimelineList> {
  bool _loading = false;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.profileService.getUserTimeline(
        userId: widget.userId,
        // from/to optional; pass when you add filters
        limit: 50,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _entries = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load timeline: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtRange(dynamic s, dynamic e) {
    DateTime? ds = (s is DateTime) ? s : DateTime.tryParse('$s');
    DateTime? de = (e is DateTime) ? e : DateTime.tryParse('$e');
    if (ds == null && de == null) return '';
    final dFmt = DateFormat('EEE, MMM d');
    final tFmt = DateFormat('HH:mm');
    if (ds != null && de != null) {
      return '${dFmt.format(ds.toLocal())} • ${tFmt.format(ds.toLocal())} → ${tFmt.format(de.toLocal())}';
    }
    if (ds != null) return '${dFmt.format(ds.toLocal())} • ${tFmt.format(ds.toLocal())}';
    return '${dFmt.format(de!.toLocal())} • ${tFmt.format(de.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: LinearProgressIndicator(),
      );
    }
    if (_entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No timeline entries yet.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final e = _entries[i];
        final title = (e['title'] ?? '') as String;
        final desc = (e['description'] ?? '') as String?;
        final linked = (e['linkedOuting'] ?? {}) as Map<String, dynamic>?;
        final range = _fmtRange(e['dateTimeStart'], e['dateTimeEnd']);

        return ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (range.isNotEmpty) Text(range),
              if (desc != null && desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(desc),
                ),
              if (linked != null && linked.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.link, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Outing: ${linked['title'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          onTap: () {
            final linkedId = linked?['id']?.toString();
            if (linkedId != null && linkedId.isNotEmpty) {
              Navigator.of(context).pushNamed('/outings/$linkedId');
            }
          },
        );
      },
    );
  }
}
