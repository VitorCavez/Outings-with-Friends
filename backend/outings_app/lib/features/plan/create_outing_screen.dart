// lib/features/plan/create_outing_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Config + Auth
import '../../config/app_config.dart';
import '../auth/auth_provider.dart';

// Autocomplete (still used; just not required)
import '../../widgets/place_autocomplete_field.dart';
import '../../services/places_service.dart';

// 🔍 Same geocoding as Discover tab
import '../../services/geocoding_service.dart';

class CreateOutingScreen extends StatefulWidget {
  const CreateOutingScreen({super.key});

  @override
  State<CreateOutingScreen> createState() => _CreateOutingScreenState();
}

class _CreateOutingScreenState extends State<CreateOutingScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basic fields
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Location fields
  String? _locationName;
  double? _lat;
  double? _lng;

  // Manual coordinate fields (for copy/paste)
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  // Piggy Bank
  bool _piggyBankEnabled = true;
  final _piggyBankTargetEuroCtrl = TextEditingController(text: '50.00');

  // Outing Type
  static const Map<String, String> _typeLabels = {
    'food_and_drink': 'Food & drink',
    'outdoor': 'Outdoor',
    'concert': 'Concert',
    'sports': 'Sports',
    'movie': 'Movie',
    'other': 'Other',
  };

  final List<String> _types = _typeLabels.keys.toList();

  String _outingType = 'food_and_drink';

  // Dates
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 3));

  // Geocoding
  final _geo = GeocodingService();
  bool _findingCoords = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _piggyBankTargetEuroCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 2));
        }
      } else {
        _end = picked.isAfter(_start)
            ? picked
            : _start.add(const Duration(hours: 2));
      }
    });
  }

  int? _eurosToCents(String input) {
    final sanitized = input.replaceAll(',', '.').trim();
    final value = double.tryParse(sanitized);
    if (value == null) return null;
    return (value * 100).round();
  }

  String _readJwt(BuildContext context) {
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      return (dyn.authToken ?? dyn.token) as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  // 🔍 Use OpenCage-based GeocodingService to auto-fill coordinates
  Future<void> _findCoordsFromText() async {
    final parts = <String>[];

    // We only know _locationName when user selects from autocomplete.
    if (_locationName != null && _locationName!.trim().isNotEmpty) {
      parts.add(_locationName!.trim());
    }

    final addr = _addressCtrl.text.trim();
    if (addr.isNotEmpty) {
      parts.add(addr);
    }

    final query = parts.join(', ');

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a location name and/or address before searching.',
          ),
        ),
      );
      return;
    }

    setState(() => _findingCoords = true);
    try {
      final resp = await _geo.forward(address: query, limit: 1, language: 'en');

      if (!mounted) return;

      if (!resp.ok || resp.results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find that address. Try another.'),
          ),
        );
        return;
      }

      final best = resp.results.first;
      _lat = best.coordinates.lat;
      _lng = best.coordinates.lng;

      _latCtrl.text = _lat!.toStringAsFixed(6);
      _lngCtrl.text = _lng!.toStringAsFixed(6);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location found: ${best.formatted}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Geocoding error: $e')));
    } finally {
      if (mounted) {
        setState(() => _findingCoords = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // --- Resolve location name (never empty) ---
    String locationName = (_locationName ?? '').trim();
    if (locationName.isEmpty) {
      final addr = _addressCtrl.text.trim();
      if (addr.isNotEmpty) {
        locationName = addr;
      } else {
        locationName = 'Custom place';
      }
    }

    // --- Resolve coordinates ---
    // Priority: manual text fields → internal _lat/_lng from autocomplete/geocode
    double? lat = _latCtrl.text.trim().isNotEmpty
        ? double.tryParse(_latCtrl.text.trim())
        : _lat;
    double? lng = _lngCtrl.text.trim().isNotEmpty
        ? double.tryParse(_lngCtrl.text.trim())
        : _lng;

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please find the coordinates first (use "Find coordinates") or enter them manually.',
          ),
        ),
      );
      return;
    }

    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim().isEmpty
        ? null
        : _descriptionCtrl.text.trim();
    final address = _addressCtrl.text.trim().isEmpty
        ? null
        : _addressCtrl.text.trim();

    int? piggyBankTargetCents;
    if (_piggyBankEnabled) {
      piggyBankTargetCents = _eurosToCents(_piggyBankTargetEuroCtrl.text);
      if (piggyBankTargetCents == null || piggyBankTargetCents <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid Piggy Bank target (in euros).'),
          ),
        );
        return;
      }
    }

    final body = <String, dynamic>{
      "title": title,
      "description": description,
      "outingType": _outingType,
      "locationName": locationName,
      "latitude": lat,
      "longitude": lng,
      "address": address,
      "dateTimeStart": _start.toUtc().toIso8601String(),
      "dateTimeEnd": _end.toUtc().toIso8601String(),
      "budgetMin": null,
      "budgetMax": null,
      "piggyBankEnabled": _piggyBankEnabled,
      "piggyBankTargetCents": _piggyBankEnabled ? piggyBankTargetCents : null,
      "checklist": [],
    };

    final token = _readJwt(context);
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to be logged in to create an outing.'),
        ),
      );
      return;
    }

    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/outings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (resp.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Outing created!')));
        Navigator.of(context).pop(true);
      } else if (resp.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please log in again.')));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Create failed (${resp.statusCode}): ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Network error: $e')));
    }
  }

  String _readToken() => _readJwt(context);

  String _formatDT(DateTime dt) =>
      DateFormat('EEE, d MMM yyyy • HH:mm').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Outing')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Outing type
            DropdownButtonFormField<String>(
              initialValue: _outingType,
              items: _types
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(_typeLabels[code] ?? code),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _outingType = v ?? _outingType),
              decoration: const InputDecoration(
                labelText: 'Outing type',
                prefixIcon: Icon(Icons.category),
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              dropdownColor: Theme.of(context).colorScheme.surface,
            ),
            const SizedBox(height: 12),

            // Location (autocomplete - optional helper)
            PlaceAutocompleteField(
              labelText: 'Location name',
              token: _readToken(),
              onSelected: (PlaceSuggestion p) {
                setState(() {
                  _locationName = p.name;
                  _addressCtrl.text = p.address ?? _addressCtrl.text;
                  _lat = p.latitude;
                  _lng = p.longitude;
                  if (_lat != null) {
                    _latCtrl.text = _lat!.toStringAsFixed(6);
                  }
                  if (_lng != null) {
                    _lngCtrl.text = _lng!.toStringAsFixed(6);
                  }
                });
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.map),
              ),
            ),

            const SizedBox(height: 12),

            // Coordinates + "Find coordinates" helper
            Text('Coordinates', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      helperText: 'e.g. 53.3498',
                    ),
                    validator: (v) {
                      final txt = v?.trim() ?? '';
                      if (txt.isEmpty) return null; // can be auto-filled
                      final ok = double.tryParse(txt);
                      if (ok == null) {
                        return 'Enter a number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      helperText: 'e.g. -6.2603',
                    ),
                    validator: (v) {
                      final txt = v?.trim() ?? '';
                      if (txt.isEmpty) return null; // can be auto-filled
                      final ok = double.tryParse(txt);
                      if (ok == null) {
                        return 'Enter a number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _findingCoords ? null : _findCoordsFromText,
                icon: _findingCoords
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_findingCoords ? 'Searching…' : 'Find coordinates'),
              ),
            ),

            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            // Dates
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(Icons.schedule, color: cs.onSurfaceVariant),
                title: const Text('Start'),
                subtitle: Text(
                  _formatDT(_start),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () => _pickDateTime(isStart: true),
                  child: const Text('Change'),
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(Icons.schedule, color: cs.onSurfaceVariant),
                title: const Text('End'),
                subtitle: Text(
                  _formatDT(_end),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () => _pickDateTime(isStart: false),
                  child: const Text('Change'),
                ),
              ),
            ),
            const Divider(height: 24),

            // Piggy Bank
            SwitchListTile(
              value: _piggyBankEnabled,
              onChanged: (v) => setState(() => _piggyBankEnabled = v),
              title: const Text('Enable Piggy Bank'),
              subtitle: Text(
                'Friends can contribute to a shared target',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            if (_piggyBankEnabled) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _piggyBankTargetEuroCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Piggy Bank Target (€)',
                  prefixIcon: Icon(Icons.savings),
                ),
                validator: (v) {
                  if (!_piggyBankEnabled) return null;
                  final cents = _eurosToCents(v ?? '');
                  if (cents == null || cents <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              onPressed: _submit,
              label: const Text('Create Outing'),
            ),
          ],
        ),
      ),
    );
  }
}
