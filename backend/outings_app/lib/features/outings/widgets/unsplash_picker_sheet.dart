// lib/features/outings/widgets/unsplash_picker_sheet.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../services/api_client.dart';
import '../../../services/unsplash_service.dart';

class UnsplashPickerSheet extends StatefulWidget {
  const UnsplashPickerSheet({
    super.key,
    required this.api,
    required this.onPicked, // returns selected image URL
  });

  final ApiClient api;
  final void Function(String imageUrl) onPicked;

  @override
  State<UnsplashPickerSheet> createState() => _UnsplashPickerSheetState();
}

class _UnsplashPickerSheetState extends State<UnsplashPickerSheet> {
  final _ctrl = TextEditingController(text: 'city skyline');
  late final UnsplashService _svc;
  bool _loading = false;
  List<UnsplashPhoto> _results = [];

  @override
  void initState() {
    super.initState();
    _svc = UnsplashService(widget.api);
    _search();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await _svc.search(q);
      if (!mounted) return;
      setState(() => _results = res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.colorScheme.onSurfaceVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Search Unsplash (e.g., sunset beach)',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (_results.isEmpty && !_loading)
              Text(
                'No results yet. Try another search.',
                style: TextStyle(color: subtle),
              ),
            if (_results.isNotEmpty)
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (ctx, i) {
                    final p = _results[i];
                    return GestureDetector(
                      onTap: () {
                        widget.onPicked(p.fullUrl);
                        Navigator.of(context).pop(); // close sheet
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: p.thumbUrl,
                          fit: BoxFit.cover,
                          placeholder: (c, _) => Container(
                            color: theme.colorScheme.surfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
