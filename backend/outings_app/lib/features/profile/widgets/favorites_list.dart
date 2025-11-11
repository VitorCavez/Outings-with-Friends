// lib/features/profile/widgets/favorites_list.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/profile_service.dart';

class FavoritesList extends StatefulWidget {
  const FavoritesList({
    super.key,
    required this.profileService,
  });

  final ProfileService profileService;

  @override
  State<FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<FavoritesList> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.profileService.listMyFavorites();
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load favorites: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic iso) {
    final dt = (iso is DateTime) ? iso : DateTime.tryParse('$iso');
    if (dt == null) return '';
    return DateFormat('MMM d, yyyy').format(dt.toLocal());
    }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: LinearProgressIndicator(),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No favorites yet. Tap ⭐ on an outing to add one.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (ctx, i) {
        final f = _items[i];
        final favCreated = f['createdAt'];
        final o = (f['outing'] ?? {}) as Map<String, dynamic>;
        final id = (o['id'] ?? '').toString();
        final title = (o['title'] ?? '') as String;
        final loc = (o['locationName'] ?? '') as String?;
        final start = o['dateTimeStart'];

        return ListTile(
          leading: const Icon(Icons.star, color: Colors.amber),
          title: Text(title),
          subtitle: Text([
            if (loc != null && loc.isNotEmpty) loc,
            if (start != null) _fmt(start),
          ].where((e) => e != null && e.isNotEmpty).join(' • ')),
          trailing: Text(_fmt(favCreated)),
          onTap: id.isEmpty ? null : () => Navigator.of(context).pushNamed('/outings/$id'),
        );
      },
    );
  }
}
