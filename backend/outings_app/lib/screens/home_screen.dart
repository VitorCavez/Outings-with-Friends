// lib/screens/home_screen.dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

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

/// Lightweight UI model for Home summaries.
/// (We can later populate this from the real API.)
class HomeOutingSummary {
  final String id;
  final String title;
  final DateTime? startsAt;
  final String? subtitle;
  final String visibilityLabel; // e.g. "Public", "Only invited"
  final String? extra; // e.g. "3 people • Piggy Bank"

  const HomeOutingSummary({
    required this.id,
    required this.title,
    this.startsAt,
    this.subtitle,
    this.visibilityLabel = '',
    this.extra,
  });
}

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
/// (Used only in the dev panel.)
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
  bool _online = true; // local reflection for the status chip

  // These will later be populated from the real API / Plan tab.
  List<HomeOutingSummary> _upcoming = const [];
  List<HomeOutingSummary> _invites = const [];

  @override
  void initState() {
    super.initState();
    _refreshHomeData(); // placeholder for future wiring
  }

  // ---- Dev-only helpers (leave behaviour as-is, just moved below) ----
  Future<void> _queueChecklist() async {
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

  // ---- Home data + formatting ----
  Future<void> _refreshHomeData() async {
    // For now this just simulates a refresh so that the pull-to-refresh works.
    // Later we can fetch upcoming outings & invites and populate _upcoming/_invites.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    setState(() {
      // Keep them empty for now – UI shows friendly empty states.
      _upcoming = const [];
      _invites = const [];
    });
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return 'Date to be decided';
    return DateFormat('EEE, d MMM • HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final divider = theme.dividerColor.withOpacity(.15);

    return Scaffold(
      appBar: AppBar(
        leading: const ProfileMenuButton(), // avatar menu (Profile | Settings)
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
      body: RefreshIndicator(
        onRefresh: _refreshHomeData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----- Greeting / hero header -----
            _buildHeader(cs),

            const SizedBox(height: 16),

            // ----- Quick actions row -----
            _buildQuickActionsRow(cs),

            const SizedBox(height: 16),

            // ----- Coming up card -----
            _buildComingUpCard(cs),

            const SizedBox(height: 16),

            // ----- Invites card -----
            _buildInvitesCard(cs),

            const SizedBox(height: 24),

            // ----- Small sync status footer -----
            _buildSyncFooter(cs),

            // ----- Dev panels (debug builds only) -----
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              _buildDevPanels(cs, divider),
            ],
          ],
        ),
      ),
    );
  }

  // ---- UI sections ---------------------------------------------------

  Widget _buildHeader(ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.primaryContainer,
              child: Icon(
                Icons.calendar_today_rounded,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plan it once.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'See what’s coming up and start your next outing.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.go('/plan'),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Plan outing'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go('/discover'),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('Discover nearby'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go('/plan?tab=invites'),
            icon: const Icon(Icons.mail_outline),
            label: const Text('My invites'),
          ),
        ),
      ],
    );
  }

  Widget _buildComingUpCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coming up',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (_upcoming.isEmpty)
              Text(
                'No outings planned yet. Tap “Plan outing” to create your first one.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              )
            else
              Column(
                children: _upcoming.map((o) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event, color: cs.primary),
                    title: Text(
                      o.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_fmtDateTime(o.startsAt)}'
                      '${o.visibilityLabel.isNotEmpty ? ' • ${o.visibilityLabel}' : ''}'
                      '${o.extra != null && o.extra!.isNotEmpty ? ' • ${o.extra}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    onTap: () => context.push('/outings/${o.id}'),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitesCard(ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invites & requests',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            if (_invites.isEmpty)
              Text(
                'No pending invites. You’re all caught up ✅',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              )
            else
              Column(
                children: _invites.map((o) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.mark_email_unread, color: cs.secondary),
                    title: Text(
                      o.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _fmtDateTime(o.startsAt),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    trailing: TextButton(
                      onPressed: () => context.push('/outings/${o.id}'),
                      child: const Text('View'),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncFooter(ColorScheme cs) {
    return ValueListenableBuilder<int>(
      valueListenable: OutboxService.instance.pendingCount,
      builder: (_, count, __) {
        final isSynced = _online && count == 0;
        final text = !_online
            ? 'Offline — changes will sync when you’re online.'
            : (isSynced
                  ? 'Online • All changes synced.'
                  : 'Online • $count change(s) waiting to sync.');
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        );
      },
    );
  }

  // ---- Dev panels (debug builds only) -------------------------------
  Widget _buildDevPanels(ColorScheme cs, Color divider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Outbox connectivity card
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

        // Quick Actions
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
                  child: const Text('Queue Checklist Update (Offline-capable)'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Outing Dev Actions
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
    );
  }
}
