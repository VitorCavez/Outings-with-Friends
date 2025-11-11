// lib/features/plan/create_outing_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// IMPORTANT: Set your backend URL here.
/// - On Android emulator use http://10.0.2.2:4000
/// - On iOS simulator or real device on same Wi-Fi, use your machine's IP, e.g., http://192.168.1.23:4000
const String kBaseUrl = 'http://10.0.2.2:4000';

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
  final _createdByIdCtrl = TextEditingController();
  final _locationNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController(text: '53.3498');   // Dublin default
  final _lngCtrl = TextEditingController(text: '-6.2603');

  // Piggy Bank
  bool _piggyBankEnabled = true;
  final _piggyBankTargetEuroCtrl = TextEditingController(text: '50.00');

  // Outing Type
  final List<String> _types = [
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
    _createdByIdCtrl.dispose();
    _locationNameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _piggyBankTargetEuroCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({
    required bool isStart,
  }) async {
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

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 2));
        }
      } else {
        _end = picked.isAfter(_start) ? picked : _start.add(const Duration(hours: 2));
      }
    });
  }

  int? _eurosToCents(String input) {
    final sanitized = input.replaceAll(',', '.').trim();
    final value = double.tryParse(sanitized);
    if (value == null) return null;
    return (value * 100).round();
    // Note: server stores cents as int; this avoids float rounding issues.
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final createdById = _createdByIdCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim();
    final locationName = _locationNameCtrl.text.trim();
    final address = _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Latitude and longitude must be numbers.')),
      );
      return;
    }

    int? piggyBankTargetCents;
    if (_piggyBankEnabled) {
      piggyBankTargetCents = _eurosToCents(_piggyBankTargetEuroCtrl.text);
      if (piggyBankTargetCents == null || piggyBankTargetCents <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid Piggy Bank target (in euros).')),
        );
        return;
      }
    }

    final body = {
      "title": title,
      "description": description,
      "outingType": _outingType,
      "createdById": createdById,
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
      "checklist": []
    };

    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/api/outings'),
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode(body),
      );

      if (resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outing created!')),
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final msg = 'Create failed (${resp.statusCode}): ${resp.body}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Outing')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Created By (temporary until auth is wired)
            TextFormField(
              controller: _createdByIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Created By (User ID)',
                hintText: 'Paste a valid User.id',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _outingType,
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _outingType = v ?? _outingType),
              decoration: const InputDecoration(
                labelText: 'Outing type',
                prefixIcon: Icon(Icons.category),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _locationNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Location name',
                prefixIcon: Icon(Icons.place),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    validator: (v) => (double.tryParse(v ?? '') == null) ? 'Number' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    validator: (v) => (double.tryParse(v ?? '') == null) ? 'Number' : null,
                  ),
                ),
              ],
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
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Start'),
              subtitle: Text(_start.toLocal().toString()),
              trailing: TextButton(
                onPressed: () => _pickDateTime(isStart: true),
                child: const Text('Change'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('End'),
              subtitle: Text(_end.toLocal().toString()),
              trailing: TextButton(
                onPressed: () => _pickDateTime(isStart: false),
                child: const Text('Change'),
              ),
            ),
            const Divider(height: 24),

            // Piggy Bank
            SwitchListTile(
              value: _piggyBankEnabled,
              onChanged: (v) => setState(() => _piggyBankEnabled = v),
              title: const Text('Enable Piggy Bank'),
              subtitle: const Text('Friends can contribute to a shared target'),
            ),
            if (_piggyBankEnabled) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _piggyBankTargetEuroCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Piggy Bank Target (€)',
                  prefixIcon: Icon(Icons.savings),
                ),
                validator: (v) {
                  if (!_piggyBankEnabled) return null;
                  final cents = _eurosToCents(v ?? '');
                  if (cents == null || cents <= 0) return 'Enter a valid amount';
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
