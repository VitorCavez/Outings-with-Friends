// lib/features/outings/outing_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/auth_provider.dart';
import '../../services/outings_service.dart';
import '../../models/outing_details_model.dart';
import '../../models/piggy_bank_models.dart';
import '../../models/expense_models.dart';

// Phase 6 widgets + API client
import '../../services/api_client.dart';
import 'widgets/outing_image_uploader.dart';
import 'widgets/itinerary_timeline.dart';

// ✅ Repo for offline-first edit via Outbox
import 'outings_repository.dart';
import 'models/outing.dart' show Outing; // optional: if you want to use Outing locally

class OutingDetailsScreen extends StatefulWidget {
  final String outingId;
  const OutingDetailsScreen({super.key, required this.outingId});

  @override
  State<OutingDetailsScreen> createState() => _OutingDetailsScreenState();
}

class _OutingDetailsScreenState extends State<OutingDetailsScreen> {
  final _svc = OutingsService();
  Future<OutingDetails>? _detailsFuture;

  // Independent reload nonces
  int _pbReloadNonce = 0;
  int _expReloadNonce = 0;

  // Central API client (Unsplash/images/itinerary/profile/favorites)
  late final ApiClient _api;

  // 👉 Repository (for fetch-by-id and offline-first update)
  late final OutingsRepository _repo;

  // ⭐ Favorites
  bool _favBusy = false;
  bool? _isFavorite; // null = unknown / loading

  // Niceties: scroll-to-section
  final _scrollController = ScrollController();
  final _imagesKey = GlobalKey();
  final _itineraryKey = GlobalKey();
  final _expensesKey = GlobalKey();

  // Niceties: small local busy flags for section reloads (UI only)
  bool _reloadingImages = false;
  bool _reloadingItinerary = false;
  bool get _isLocalOnly => widget.outingId.startsWith('local-');

  @override
  void initState() {
    super.initState();

    // Build ApiClient from environment or fallback; try to read token
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:4000',
    );
    final auth = context.read<AuthProvider?>();
    String? token;
    try {
      // ignore: avoid_dynamic_calls
      token = (auth as dynamic)?.authToken as String?;
    } catch (_) {}

    _api = ApiClient(baseUrl: baseUrl, authToken: token);
    _repo = OutingsRepository(_api);

    // If it's a local-only placeholder, don't hit the network yet.
    if (!_isLocalOnly) {
      _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
      _loadFavoriteStatus();
    } else {
      _detailsFuture = null;
      _isFavorite = false; // disabled anyway
    }
  }

  // -----------------------------
  // ⭐ Favorites
  // -----------------------------
  Future<void> _loadFavoriteStatus() async {
    final auth = context.read<AuthProvider?>();
    final token = _api.authToken;
    if (auth?.currentUserId == null || token == null || token.isEmpty) {
      setState(() => _isFavorite = false);
      return;
    }
    try {
      final r = await _api.get('/api/users/me/favorites');
      if (r.statusCode == 200) {
        final map = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (map['data'] as List).cast<Map<String, dynamic>>();
        final has = items.any((it) {
          final outingId = it['outingId']?.toString();
          final outing = (it['outing'] ?? {}) as Map<String, dynamic>;
          return outingId == widget.outingId || outing['id']?.toString() == widget.outingId;
        });
        if (mounted) setState(() => _isFavorite = has);
      } else {
        if (mounted) setState(() => _isFavorite = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favBusy || _isLocalOnly) return; // disabled for local-only
    final auth = context.read<AuthProvider?>();
    if (auth?.currentUserId == null || _api.authToken == null || _api.authToken!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to favorite outings.')),
      );
      return;
    }

    setState(() => _favBusy = true);
    try {
      final uri = Uri.parse('${_api.baseUrl}/api/outings/${widget.outingId}/favorite');
      final headers = <String, String>{'Authorization': 'Bearer ${_api.authToken}'};

      late http.Response resp;
      if (_isFavorite == true) {
        resp = await http.delete(uri, headers: headers);
      } else {
        resp = await http.post(uri, headers: headers);
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        setState(() => _isFavorite = !(_isFavorite ?? false));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFavorite == true ? 'Added to favorites' : 'Removed from favorites')),
        );
      } else if (resp.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to favorite outings.')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Favorite action failed (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Favorite error: $e')),
      );
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  // -----------------------------
  // Edit (offline-first via Outbox-backed repo)
  // -----------------------------
  Future<void> _showEditDialog(OutingDetails d) async {
    final titleCtrl = TextEditingController(text: d.title);
    final notesCtrl = TextEditingController(text: d.description ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit outing'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes / Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final patch = <String, dynamic>{
      'title': titleCtrl.text.trim(),
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    };

    try {
      await _repo.updateOuting(widget.outingId, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved. If offline, it’s queued and will sync automatically.'),
        ),
      );
      // Refresh details (best-effort)
      setState(() => _detailsFuture = _svc.fetchOutingDetails(widget.outingId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  // -----------------------------
  // Helpers & niceties
  // -----------------------------
  Future<void> _pullToRefresh() async {
    if (_isLocalOnly) {
      // There is nothing to fetch yet — the server ID doesn't exist.
      // Show a small toast and bail out.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This outing will appear once it’s synced.')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }

    setState(() {
      _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
      _pbReloadNonce++;
      _expReloadNonce++;
    });
    await Future.wait([
      _detailsFuture!,
      _loadFavoriteStatus(),
    ]);
  }

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  Widget _skeletonLine({double height = 12, double width = double.infinity, double radius = 8}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(.25),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  int? _eurosToCents(String input) {
    final sanitized = input.replaceAll(',', '.').trim();
    final value = double.tryParse(sanitized);
    if (value == null) return null;
    return (value * 100).round();
  }

  // -----------------------------
  // Piggy Bank
  // -----------------------------
  Future<void> _showContributeDialog(OutingDetails d) async {
    final auth = context.read<AuthProvider?>();
    final currentUserId = auth?.currentUserId;
    if (currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to contribute.')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contribute to Piggy Bank'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (€)',
                  prefixIcon: Icon(Icons.euro),
                ),
                validator: (v) {
                  final cents = _eurosToCents(v ?? '');
                  if (cents == null || cents <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.note_add_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Contribute'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final cents = _eurosToCents(amountCtrl.text)!;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    try {
      await _svc.addContribution(
        outingId: widget.outingId,
        userId: currentUserId,
        amountCents: cents,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contribution added!')),
      );
      setState(() => _pbReloadNonce++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to contribute: $e')),
      );
    }
  }

  Widget _buildPiggyBankCard(OutingDetails d) {
    if (!d.piggyBankEnabled || d.piggyBankTargetCents == null || d.piggyBankTargetCents == 0) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<PiggyBankSummary>(
      key: ValueKey('pb-${widget.outingId}-$_pbReloadNonce'),
      future: _svc.getPiggyBankSummary(widget.outingId),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  _skeletonLine(width: 120),
                  const SizedBox(width: 8),
                  _skeletonLine(width: 60),
                ],
              ),
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Piggy Bank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Failed to load: ${snap.error}'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _pbReloadNonce++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final pb = snap.data!;
        final pct = pb.progressPct.clamp(0, 100);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Piggy Bank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (pct / 100.0).clamp(0.0, 1.0),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$pct%'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('€${pb.raisedEuro} raised of €${pb.targetEuro}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.savings_outlined),
                      onPressed: () => _showContributeDialog(d),
                      label: const Text('Contribute'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _pbReloadNonce++),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Recent contributions', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (pb.contributions.isEmpty)
                  const Text('No contributions yet.')
                else
                  Column(
                    children: pb.contributions.take(5).map((c) {
                      final cents = c.amountCents ?? ((c.amount != null) ? (c.amount! * 100).round() : 0);
                      final euros = (cents / 100.0).toStringAsFixed(2);
                      final when = c.createdAt?.toLocal().toString().split('.').first ?? '';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.account_circle),
                        title: Text('€$euros'),
                        subtitle: Text(c.note ?? when),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------------
  // Expenses
  // -----------------------------
  Future<void> _showAddExpenseDialog() async {
    final auth = context.read<AuthProvider?>();
    final currentUserId = auth?.currentUserId;
    if (currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to add expenses.')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add expense'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (€)',
                  prefixIcon: Icon(Icons.euro_symbol),
                ),
                validator: (v) {
                  final cents = _eurosToCents(v ?? '');
                  if (cents == null || cents <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final cents = _eurosToCents(amountCtrl.text)!;
    final desc = descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();
    final cat = categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim();

    try {
      await _svc.addExpense(
        outingId: widget.outingId,
        payerId: currentUserId,
        amountCents: cents,
        description: desc,
        category: cat,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added!')),
      );
      setState(() => _expReloadNonce++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add expense: $e')),
      );
    }
  }

  Widget _buildExpensesCard() {
    return FutureBuilder<ExpenseSummary>(
      key: ValueKey('exp-${widget.outingId}-$_expReloadNonce'),
      future: _svc.getExpenseSummary(widget.outingId),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _skeletonLine()),
                ],
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Failed to load: ${snap.error}'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _expReloadNonce++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final summary = snap.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Total: €${summary.totalEuro}', style: const TextStyle(fontSize: 16))),
                    Expanded(child: Text('Per person: €${summary.perPersonEuro}', style: const TextStyle(fontSize: 16))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Balances', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (summary.balances.isEmpty)
                  const Text('No participants yet.')
                else
                  Column(
                    children: summary.balances.map((b) {
                      final you = context.read<AuthProvider?>()?.currentUserId;
                      final isYou = (you != null && b.userId == you);
                      final label = isYou ? 'You' : b.userId;
                      final sign = b.balanceCents == 0 ? '' : (b.balanceCents > 0 ? ' (credit)' : ' (owes)');
                      final balanceEuro = b.balanceEuro;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.account_circle_outlined),
                        title: Text(label),
                        trailing: Text('€$balanceEuro$sign'),
                        subtitle: Text('Paid: €${b.paidEuro} • Owes: €${b.owesEuro}'),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                const Text('Recent expenses', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (summary.expenses.isEmpty)
                  const Text('No expenses yet.')
                else
                  Column(
                    children: summary.expenses.reversed.take(5).map((e) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text('€${e.amountEuro} — ${e.description ?? 'Expense'}'),
                        subtitle: Text('${e.category ?? 'general'} • ${e.createdAt?.toLocal().toString().split('.').first ?? ''}'),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _showAddExpenseDialog,
                      icon: const Icon(Icons.add_card),
                      label: const Text('Add expense'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => setState(() => _expReloadNonce++),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------------
  // Local-only body
  // -----------------------------
  Widget _buildLocalOnlyBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sync, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This outing was created while offline and will sync when you’re back online. '
                  'Some actions are temporarily disabled.',
                  style: TextStyle(color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Lightweight header
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Theme.of(context).dividerColor.withOpacity(.15),
              child: const Center(
                child: Icon(Icons.photo, size: 48, color: Colors.black26),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: Text(
                'Draft outing',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Chip(label: Text('Syncing')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: const [
            Icon(Icons.place, size: 18, color: Colors.black45),
            SizedBox(width: 6),
            Text('Location TBD', style: TextStyle(color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 16),

        // Guidance
        Text(
          'We’ll load full details once the server confirms this outing. '
          'You can safely leave this page.',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),

        // Disabled actions preview
        Wrap(
          spacing: 8,
          children: const [
            Chip(avatar: Icon(Icons.image, size: 16), label: Text('Images (disabled)')),
            Chip(avatar: Icon(Icons.timeline, size: 16), label: Text('Itinerary (disabled)')),
            Chip(avatar: Icon(Icons.savings, size: 16), label: Text('Piggy Bank (disabled)')),
            Chip(avatar: Icon(Icons.receipt_long, size: 16), label: Text('Expenses (disabled)')),
          ],
        ),
      ],
    );
  }

  // -----------------------------
  // Scaffold
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outing details'),
        actions: [
          // Edit (disabled for local-only)
          IconButton(
            tooltip: _isLocalOnly ? 'Edit (disabled while syncing)' : 'Edit',
            onPressed: _isLocalOnly
                ? null
                : () async {
                    final details = await _detailsFuture;
                    if (!mounted) return;
                    if (details == null) return;
                    await _showEditDialog(details);
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          // Share (disabled for local-only)
          IconButton(
            tooltip: _isLocalOnly ? 'Share (disabled while syncing)' : 'Share',
            onPressed: _isLocalOnly
                ? null
                : () {
                    // Hook up with share_plus later if desired
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share coming soon')),
                    );
                  },
            icon: const Icon(Icons.ios_share),
          ),
          // ⭐ Favorite toggle (disabled for local-only)
          IconButton(
            tooltip: _isLocalOnly
                ? 'Favorite (disabled while syncing)'
                : (_isFavorite == true ? 'Unfavorite' : 'Favorite'),
            onPressed: (_isFavorite == null || _favBusy || _isLocalOnly) ? null : _toggleFavorite,
            icon: _isLocalOnly
                ? const Icon(Icons.star_border)
                : (_favBusy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _isFavorite == true ? Icons.star : Icons.star_border,
                        color: _isFavorite == true ? Colors.amber : null,
                      )),
          ),
        ],
      ),
      body: _isLocalOnly
          ? RefreshIndicator(
              onRefresh: _pullToRefresh,
              child: _buildLocalOnlyBody(),
            )
          : RefreshIndicator(
              onRefresh: _pullToRefresh,
              child: FutureBuilder<OutingDetails>(
                future: _detailsFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    // Header skeleton
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(color: Theme.of(context).dividerColor.withOpacity(.25)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _skeletonLine(width: 200, height: 18),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.place, size: 18, color: Colors.black26),
                            const SizedBox(width: 6),
                            _skeletonLine(width: 160, height: 12),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _skeletonLine(height: 12),
                        const SizedBox(height: 6),
                        _skeletonLine(width: 220, height: 12),
                      ],
                    );
                  }
                  if (snap.hasError || !snap.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
                            const SizedBox(height: 12),
                            Text(snap.error?.toString() ?? 'Failed to load outing.'),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _detailsFuture = _svc.fetchOutingDetails(widget.outingId)),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  final d = snap.data!;
                  return ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Header image with a Hero (nicety)
                      if (d.imageUrl != null)
                        Hero(
                          tag: 'outing:${widget.outingId}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(d.imageUrl!, height: 200, fit: BoxFit.cover),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.title,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Chip(label: Text(d.type)),
                        ],
                      ),
                      if (d.subtitle != null) Text(d.subtitle!, style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.place, size: 18), const SizedBox(width: 6),
                        Text('${d.lat.toStringAsFixed(5)}, ${d.lng.toStringAsFixed(5)}'),
                      ]),
                      const SizedBox(height: 16),
                      if (d.description != null) Text(d.description!),
                      const SizedBox(height: 16),
                      if (d.address != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined),
                            const SizedBox(width: 6),
                            Expanded(child: Text(d.address!)),
                          ],
                        ),
                      if (d.startsAt != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.event),
                            const SizedBox(width: 6),
                            Text(d.startsAt!.toLocal().toString()),
                          ],
                        ),
                      ],

                      // Quick section chips (nicety)
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Images'),
                            onPressed: () => _scrollToSection(_imagesKey),
                          ),
                          ActionChip(
                            label: const Text('Itinerary'),
                            onPressed: () => _scrollToSection(_itineraryKey),
                          ),
                          ActionChip(
                            label: const Text('Expenses'),
                            onPressed: () => _scrollToSection(_expensesKey),
                          ),
                        ],
                      ),

                      // Images
                      const SizedBox(height: 16),
                      Container(
                        key: _imagesKey,
                        padding: const EdgeInsets.only(top: 2),
                        child: const Text('Images', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _reloadingImages
                                ? null
                                : () {
                                    // trigger refresh inside the widget by toggling the key
                                    setState(() => _reloadingImages = true);
                                    // a small delay to allow internal fetchImages to run from new instance
                                    Future.delayed(const Duration(milliseconds: 50), () {
                                      if (mounted) setState(() => _reloadingImages = false);
                                    });
                                  },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh images'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutingImageUploader(
                        key: ValueKey('images-${widget.outingId}-${_reloadingImages ? 'r' : 'n'}'),
                        outingId: widget.outingId,
                        api: _api,
                      ),

                      // Itinerary
                      const SizedBox(height: 16),
                      Container(
                        key: _itineraryKey,
                        padding: const EdgeInsets.only(top: 2),
                        child: const Text('Itinerary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _reloadingItinerary
                                ? null
                                : () {
                                    setState(() => _reloadingItinerary = true);
                                    Future.delayed(const Duration(milliseconds: 50), () {
                                      if (mounted) setState(() => _reloadingItinerary = false);
                                    });
                                  },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh itinerary'),
                          ),
                        ],
                      ),
                      ItineraryTimeline(
                        key: ValueKey('itin-${widget.outingId}-${_reloadingItinerary ? 'r' : 'n'}'),
                        outingId: widget.outingId,
                        api: _api,
                      ),

                      // Piggy Bank
                      const SizedBox(height: 16),
                      _buildPiggyBankCard(d),

                      // Expenses
                      const SizedBox(height: 16),
                      Container(
                        key: _expensesKey,
                        padding: const EdgeInsets.only(top: 2),
                        child: _buildExpensesCard(),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}
