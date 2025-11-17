// lib/widgets/place_autocomplete_field.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/places_service.dart';

class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    super.key,
    required this.labelText,
    required this.onSelected,
    this.initialText,
    this.token,
  });

  final String labelText;
  final String? initialText;
  final String? token;
  final void Function(PlaceSuggestion place) onSelected;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _results = [];
  bool _loading = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) _ctrl.text = widget.initialText!;
    _ctrl.addListener(_onChanged);
    _focus.addListener(() {
      setState(() => _open = _focus.hasFocus && _results.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = _ctrl.text.trim();
      if (q.isEmpty) {
        setState(() {
          _results = [];
          _open = false;
        });
        return;
      }
      setState(() => _loading = true);
      final rows = await PlacesService.search(q, token: widget.token);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _loading = false;
        _open = _focus.hasFocus && _results.isNotEmpty;
      });
    });
  }

  void _select(PlaceSuggestion p) {
    _ctrl.text = p.name;
    setState(() {
      _results = [];
      _open = false;
    });
    widget.onSelected(p);
  }

  Future<void> _addCustomPlace() async {
    // Minimal custom-place dialog that leverages address lookup to get coords.
    final formKey = GlobalKey<FormState>();
    String name = _ctrl.text.trim();
    String address = '';
    double? lat;
    double? lng;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add custom place'),
        content: StatefulBuilder(
          builder: (ctx, setInner) => Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (v) => name = v,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                    ),
                    onChanged: (v) => address = v,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        lat != null && lng != null
                            ? 'Chosen: ${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
                            : 'No coordinates chosen yet',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.search),
                        onPressed: () async {
                          if (address.trim().isEmpty) return;
                          final res = await PlacesService.search(
                            address,
                            token: widget.token,
                          );
                          if (res.isNotEmpty) {
                            final first = res.first;
                            lat = first.latitude;
                            lng = first.longitude;
                            if (name.trim().isEmpty) name = first.name;
                            setInner(() {});
                          } else {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not find that address. Try another.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        label: const Text('Find by address'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (lat == null || lng == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please choose coordinates via "Find by address" before saving.',
                    ),
                  ),
                );
                return;
              }
              final token = widget.token ?? '';
              final saved = await PlacesService.saveCustom(
                name: name,
                address: address.isEmpty ? null : address,
                latitude: lat!,
                longitude: lng!,
                token: token,
              );
              if (saved != null && context.mounted) {
                Navigator.of(ctx).pop();
                _select(saved);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _open ? _results : const <PlaceSuggestion>[];
    return Column(
      children: [
        TextFormField(
          controller: _ctrl,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixIcon: const Icon(Icons.place),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.add_location_alt_outlined),
                    tooltip: 'Add custom place',
                    onPressed: _addCustomPlace,
                  ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        if (list.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return ListTile(
                    leading: const Icon(Icons.add_location_alt),
                    title: const Text('Add custom place…'),
                    onTap: _addCustomPlace,
                  );
                }
                final p = list[i - 1];
                return ListTile(
                  leading: Icon(
                    p.source == 'saved' ? Icons.bookmark : Icons.public,
                  ),
                  title: Text(p.name),
                  subtitle: p.address != null ? Text(p.address!) : null,
                  onTap: () => _select(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
