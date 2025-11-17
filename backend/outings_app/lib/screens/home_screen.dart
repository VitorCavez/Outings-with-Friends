// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// App services
import 'package:outings_app/services/socket_service.dart';
import 'package:outings_app/services/outbox_service.dart';
import 'package:outings_app/services/api_client.dart';

// Auth + config
import 'package:outings_app/features/auth/auth_provider.dart';
import 'package:outings_app/config/app_config.dart';

// Outings domain
import 'package:outings_app/features/outings/models/outing.dart';
import 'package:outings_app/features/outings/outings_repository.dart';

// 👤 Avatar menu
import 'package:outings_app/widgets/profile_menu_button.dart';

/// Build an ApiClient using the current (optional) auth token.
ApiClient _apiFromContext(BuildContext context) {
  String? token;
  try {
    final auth = context.read<AuthProvider>();
    final dyn = auth as dynamic;
    token = (dyn.authToken ?? dyn.token) as String?;
  } catch (_) {}
  return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
}

/// Creates a simple sample outing via the OutingsRepository.
Future<void> _createSampleOuting(BuildContext context) async {
  final repo = OutingsRepository(_apiFromContext(context));
  final draft = OutingDraft(
    title: 'Coffee & Walk',
    location: 'Downtown',
    startsAt: DateTime.now().add(const Duration(days: 1)),
    description: 'Quick sanity-check outing from Dev Panel',
  );
  try {
    await repo.createOuting(draft);
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Created sample outing')));
  } catch (e) {
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _online = true; // local reflection for the dev panel label

  Future<void> _queueChecklist() async {
    // Demo IDs — replace with real ones later
    const outingId = 'demo-outing';
    const itemId = 'bring-snacks';

    await OutboxService.instance.enqueueChecklistUpdate(
      outingId: outingId,
      itemId: itemId,
      checked: true,
      note: 'Queued from Home screen',
    );
  }

  Future<void> _queueOutingCreate() async {
    await OutboxService.instance.enqueueOutingCreate(
      title: 'Coffee @ Local Cafe (dev)',
      date: DateTime.now().add(const Duration(days: 2)),
      location: 'Dublin',
    );
  }

  Future<void> _queueOutingUpdate() async {
    // Use a known/real id once you have one
    const outingId = 'demo-outing';
    await OutboxService.instance.enqueueOutingUpdate(
      outingId: outingId,
      patch: {
        'title': 'UPDATED: Coffee turned Brunch',
        'notes': 'Patched via Outbox from Home Dev Panel',
      },
    );
  }

  void _goOffline() {
    OutboxService.instance.setOnline(false);
    setState(() => _online = false);
  }

  void _goOnline() {
    OutboxService.instance.setOnline(true);
    setState(() => _online = true);
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor.withOpacity(.15);

    return Scaffold(
      appBar: AppBar(
        leading:
            const ProfileMenuButton(), // 👈 avatar menu (Profile | Settings)
        title: const Text('Home'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: OutboxService.instance.pendingCount,
            builder: (_, count, __) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                side: BorderSide(color: divider, width: 1),
                label: Text(
                  '${_online ? 'Online' : 'Offline'} • Pending: $count',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----- Dev Toggle Panel -----
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: divider, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.science_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Dev Panel: Outbox Connectivity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _online
                              ? Colors.green.withOpacity(.12)
                              : Colors.amber.withOpacity(.18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: divider),
                        ),
                        child: Text(
                          _online ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: _online
                                ? Colors.green.shade800
                                : Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _online ? _goOffline : null,
                          icon: const Icon(Icons.wifi_off),
                          label: const Text('Go Offline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _online ? null : _goOnline,
                          icon: const Icon(Icons.wifi),
                          label: const Text('Go Online'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: OutboxService.instance.pendingCount,
                    builder: (_, count, __) => Text(
                      'Pending operations: $count',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ----- Existing demo actions -----
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: divider, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      final socketService = SocketService();
                      socketService.initSocket();
                      socketService.sendMessage(
                        text: "Hello from Flutter!",
                        senderId: "YOUR_USER_ID",
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Socket message sent')),
                      );
                    },
                    child: const Text('Send Socket Test Message'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _queueChecklist,
                    child: const Text(
                      'Queue Checklist Update (Offline-capable)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ----- Outing dev actions -----
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: divider, width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Outing Dev Actions',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _queueOutingCreate,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Queue Outing Create'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _queueOutingUpdate,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Queue Outing Update'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _createSampleOuting(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Sample Outing (API)'),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: OutboxService.instance.pendingCount,
                    builder: (_, count, __) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Outbox pending: $count'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
