// lib/features/plan/create_outing_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Config + Auth
import '../../config/app_config.dart';
import '../auth/auth_provider.dart';

// Autocomplete
import '../../widgets/place_autocomplete_field.dart';
import '../../services/places_service.dart';

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

  // Filled by the place autocomplete
  String? _locationName;
  double? _lat;
  double? _lng;

  // Piggy Bank
  bool _piggyBankEnabled = true;
  final _piggyBankTargetEuroCtrl = TextEditingController(text: '50.00');

  // Outing Type
  final List<String> _types = const [
    'food_and_drink',
    'outdoor',
    'concert',
    'sports',
    'movie',
    'other',
  ];
  String _outingType = 'food_and_drink';

  // Dates
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 3));

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
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
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 2));
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_locationName == null || _lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a location from the list or add a custom place.',
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
      "locationName": _locationName,
      "latitude": _lat,
      "longitude": _lng,
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
              initialValue:
                  _outingType, // <- use initialValue (value is deprecated here)
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
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

            // Location (autocomplete)
            PlaceAutocompleteField(
              labelText: 'Location name',
              token: _readToken(),
              onSelected: (PlaceSuggestion p) {
                setState(() {
                  _locationName = p.name;
                  _addressCtrl.text = p.address ?? _addressCtrl.text;
                  _lat = p.latitude;
                  _lng = p.longitude;
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
                  if (cents == null || cents <= 0)
                    return 'Enter a valid amount';
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
