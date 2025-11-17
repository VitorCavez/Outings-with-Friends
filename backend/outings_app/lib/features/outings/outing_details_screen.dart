// lib/features/outings/outing_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

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
import 'models/outing.dart' show Outing;

// ✅ App config
import '../../config/app_config.dart';

// 🎨 Brand tokens
import '../../theme/app_theme.dart';

class _OutingVisibility {
  static const String PUBLIC = 'PUBLIC';
  static const String CONTACTS = 'CONTACTS';
  static const String INVITED = 'INVITED';
  static const String GROUPS = 'GROUPS';
}

class _ParticipantRole {
  static const String OWNER = 'OWNER';
  static const String PARTICIPANT = 'PARTICIPANT';
  static const String VIEWER = 'VIEWER';
}

class _Participant {
  final String id;
  final String outingId;
  final String userId;
  final String role;
  final int permissions;
  final String? fullName;
  final String? username;
  final String? photo;

  _Participant({
    required this.id,
    required this.outingId,
    required this.userId,
    required this.role,
    required this.permissions,
    this.fullName,
    this.username,
    this.photo,
  });

  factory _Participant.fromJson(Map<String, dynamic> j) {
    final user = (j['user'] ?? {}) as Map<String, dynamic>;
    return _Participant(
      id: j['id'] as String,
      outingId: j['outingId'] as String,
      userId: j['userId'] as String,
      role: (j['role'] ?? _ParticipantRole.PARTICIPANT) as String,
      permissions: (j['permissions'] ?? 0) as int,
      fullName: user['fullName'] as String?,
      username: user['username'] as String?,
      photo: user['profilePhotoUrl'] as String?,
    );
  }
}

class OutingDetailsScreen extends StatefulWidget {
  final String outingId;
  const OutingDetailsScreen({super.key, required this.outingId});

  @override
  State<OutingDetailsScreen> createState() => _OutingDetailsScreenState();
}

class _OutingDetailsScreenState extends State<OutingDetailsScreen> {
  late OutingsService _svc;
  Future<OutingDetails>? _detailsFuture;

  OutingDetails? _lastDetails;
  bool _canEdit = false;

  int _pbReloadNonce = 0;
  int _expReloadNonce = 0;

  late final ApiClient _api;
  late final OutingsRepository _repo;

  // ⭐ Favorites
  bool _favBusy = false;
  bool? _isFavorite;
  bool _changed = false;

  // Participants
  bool _loadingParticipants = true;
  String? _participantsError;
  List<_Participant> _participants = const [];

  // Scroll-to-section
  final _scrollController = ScrollController();
  final _imagesKey = GlobalKey();
  final _itineraryKey = GlobalKey();
  final _expensesKey = GlobalKey();
  final _participantsKey = GlobalKey();

  bool _reloadingImages = false;
  bool _reloadingItinerary = false;
  bool get _isLocalOnly => widget.outingId.startsWith('local-');

  @override
  void initState() {
    super.initState();

    _api = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      tokenProvider: () {
        final auth = Provider.of<AuthProvider?>(context, listen: false);
        try {
          final dyn = auth as dynamic;
          return (dyn.authToken ?? dyn.token) as String? ?? '';
        } catch (_) {
          return '';
        }
      },
    );
    _repo = OutingsRepository(_api);
    _svc = OutingsService(_api);

    if (!_isLocalOnly) {
      _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
      _loadFavoriteStatus();
      _loadParticipants();
    } else {
      _detailsFuture = null;
      _isFavorite = false;
    }
  }

  @override
  void didUpdateWidget(covariant OutingDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outingId != widget.outingId) {
      if (_isLocalOnly) return;
      setState(() {
        _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
        _isFavorite = null;
      });
      _loadFavoriteStatus();
      _loadParticipants();
    }
  }

  void _recomputeCanEdit() {
    final details = _lastDetails;
    if (details == null) {
      if (_canEdit != false) setState(() => _canEdit = false);
      return;
    }
    final currentUserId = context.read<AuthProvider?>()?.currentUserId;
    final isOwner =
        (currentUserId != null && details.createdById == currentUserId);
    final allowEdits = details.allowParticipantEdits ?? false;
    final isParticipant = _participants.any((p) => p.userId == currentUserId);
    final next = isOwner || (allowEdits && isParticipant);
    if (next != _canEdit) setState(() => _canEdit = next);
  }

  // -----------------------------
  // Participants
  // -----------------------------
  Future<void> _loadParticipants() async {
    setState(() {
      _loadingParticipants = true;
      _participantsError = null;
    });
    try {
      final r = await _api.get('/api/outings/${widget.outingId}/participants');
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body);
      final list =
          (j is Map<String, dynamic>
                  ? (j['data'] ?? j['participants'] ?? [])
                  : j)
              as List;
      final items = list
          .cast<Map<String, dynamic>>()
          .map((e) => _Participant.fromJson(e))
          .toList();
      setState(() {
        _participants = items;
        _loadingParticipants = false;
      });
      _recomputeCanEdit();
    } catch (e) {
      setState(() {
        _participantsError = e.toString();
        _loadingParticipants = false;
      });
      _recomputeCanEdit();
    }
  }

  // -----------------------------
  // Share helpers (short copy + guard)
  // -----------------------------
  String _buildOutingShareUrl(OutingDetails d) {
    final id = d.id.toString();
    return '${AppConfig.shareBaseUrl}/plan/outings/$id';
  }

  Future<void> _shareOutingShort(OutingDetails d) async {
    final url = _buildOutingShareUrl(d);
    await Share.share(url, subject: d.title);
  }

  Future<void> _copyOutingLink(OutingDetails d) async {
    final url = _buildOutingShareUrl(d);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _maybeGuardShare(
    OutingDetails d, {
    required Future<void> Function() onProceed,
  }) async {
    final visibility = (d.visibility ?? _OutingVisibility.INVITED).toString();
    final isPublic = visibility == _OutingVisibility.PUBLIC;

    if (isPublic) {
      await onProceed();
      return;
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  const Text(
                    'This link isn’t public',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                visibility == _OutingVisibility.INVITED
                    ? 'Only invited people can open this link.'
                    : 'This outing is not Public. Only people with access (contacts/groups/invited) can open it.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'invite'),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Invite people'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'continue'),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share anyway'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == 'invite') {
      await _openInviteDialog();
    } else if (result == 'continue') {
      await onProceed();
    }
  }

  // -----------------------------
  // Publish / Invite
  // -----------------------------
  Future<void> _openPublishSheet({
    required String currentVisibility,
    required bool currentAllowEdits,
    required bool currentShowOrganizer,
  }) async {
    final cs = Theme.of(context).colorScheme;

    String visibility = currentVisibility;
    bool allowEdits = currentAllowEdits;
    bool showOrganizer = currentShowOrganizer;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        const extraForFab = 72.0;
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        final safeBottom = MediaQuery.of(sheetContext).padding.bottom;

        return Padding(
          padding: EdgeInsets.only(
            bottom: bottomInset + safeBottom + extraForFab,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Publish / Visibility',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _VisibilityPicker(
                        value: visibility,
                        onChanged: (v) => setSheet(() => visibility = v),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Allow participant edits'),
                        value: allowEdits,
                        onChanged: (v) => setSheet(() => allowEdits = v),
                      ),
                      SwitchListTile(
                        title: const Text('Show organizer in listing'),
                        value: showOrganizer,
                        onChanged: (v) => setSheet(() => showOrganizer = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).maybePop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                try {
                                  final resp = await _api.patchJson(
                                    '/api/outings/${widget.outingId}/publish',
                                    {
                                      'visibility': visibility,
                                      'allowParticipantEdits': allowEdits,
                                      'showOrganizer': showOrganizer,
                                    },
                                  );
                                  if (resp.statusCode == 200) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Outing published/updated',
                                          ),
                                        ),
                                      );
                                    }
                                    if (mounted) Navigator.of(ctx).maybePop();
                                    setState(() {
                                      _changed = true; // mark parent refresh
                                      _detailsFuture = _svc.fetchOutingDetails(
                                        widget.outingId,
                                      );
                                    });
                                  } else {
                                    throw Exception(
                                      'HTTP ${resp.statusCode}: ${resp.body}',
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Publish failed: $e'),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openInviteDialog() async {
    final cs = Theme.of(context).colorScheme;
    final ctl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invite people'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter emails or phone numbers (comma-separated).',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              decoration: const InputDecoration(
                hintText: 'friend@example.com, +3538XXXXXXX',
              ),
              minLines: 1,
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = ctl.text.trim();
              if (raw.isEmpty) {
                Navigator.of(context).maybePop();
                return;
              }
              final contacts = raw
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              try {
                final resp = await _api.postJson(
                  '/api/outings/${widget.outingId}/invites',
                  {'contacts': contacts, 'role': _ParticipantRole.PARTICIPANT},
                );
                if (resp.statusCode == 201 || resp.statusCode == 200) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invites sent')),
                    );
                  }
                  setState(() => _changed = true); // reflect on parent tabs
                  if (mounted) Navigator.of(context).maybePop();
                } else {
                  throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Invite failed: $e')));
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // Delete (robust + returns true to parent)
  // -----------------------------
  Future<void> _confirmAndDeleteOuting(OutingDetails d) async {
    if (_isLocalOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This draft will be deleted once it syncs.'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete outing?'),
        content: const Text(
          'This will permanently remove the outing, its images, itinerary, and expenses. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final resp = await _api.delete('/api/outings/${widget.outingId}');
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Outing deleted')));
        Navigator.of(context).pop<bool>(true); // ✅ tell parent to refresh
      } else if (resp.statusCode == 403) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the organizer can delete this outing.'),
          ),
        );
      } else if (resp.statusCode == 404) {
        if (!mounted) return;
        // Already gone → behave as success and refresh parent
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outing not found (already deleted).')),
        );
        Navigator.of(context).pop<bool>(true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete error: $e')));
    }
  }

  // -----------------------------
  // ⭐ Favorites
  // -----------------------------
  Future<void> _loadFavoriteStatus() async {
    final auth = context.read<AuthProvider?>();
    final tokenHeader = _api.buildHeaders()['Authorization'];
    if (auth?.currentUserId == null || tokenHeader == null) {
      setState(() => _isFavorite = false);
      return;
    }
    try {
      final r = await _api.get('/api/users/me/favorites');
      if (r.statusCode == 200) {
        final map = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (map['data'] as List).cast<Map<String, dynamic>>();
        final has = items.any((it) {
          final favOutingId = it['outingId']?.toString();
          final outing = (it['outing'] ?? {}) as Map<String, dynamic>;
          return favOutingId == widget.outingId ||
              outing['id']?.toString() == widget.outingId;
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
    if (_favBusy || _isLocalOnly) return;
    final auth = context.read<AuthProvider?>();
    final tokenHeader = _api.buildHeaders()['Authorization'];
    if (auth?.currentUserId == null || tokenHeader == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to favorite outings.')),
      );
      return;
    }

    setState(() => _favBusy = true);
    try {
      late http.Response resp;
      if (_isFavorite == true) {
        resp = await _api.delete('/api/outings/${widget.outingId}/favorite');
      } else {
        resp = await _api.post('/api/outings/${widget.outingId}/favorite');
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        setState(() {
          _isFavorite = !(_isFavorite ?? false);
          _changed = true; // ← notify parent to refresh lists after pop
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFavorite == true
                  ? 'Added to favorites'
                  : 'Removed from favorites',
            ),
          ),
        );
      } else if (resp.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to favorite outings.')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Favorite action failed (${resp.statusCode})'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Favorite error: $e')));
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _EditOutingDialog(titleCtrl: titleCtrl, notesCtrl: notesCtrl),
    );

    if (confirmed != true) return;

    final patch = <String, dynamic>{
      'title': titleCtrl.text.trim(),
      'description': notesCtrl.text.trim().isEmpty
          ? null
          : notesCtrl.text.trim(),
    };

    try {
      await _repo.updateOuting(widget.outingId, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved. If offline, it’s queued and will sync automatically.',
          ),
        ),
      );
      setState(() {
        _changed = true; // parent should refresh
        _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  // -----------------------------
  // Helpers & niceties
  // -----------------------------
  Future<void> _pullToRefresh() async {
    if (_isLocalOnly) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This outing will appear once it’s synced.'),
          ),
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
    final f1 = _detailsFuture!;
    await Future.wait([f1, _loadFavoriteStatus(), _loadParticipants()]);
  }

  void _maybeAbsorbDetailsForPermissions(OutingDetails d) {
    final shouldUpdate =
        _lastDetails == null ||
        _lastDetails!.createdById != d.createdById ||
        _lastDetails!.allowParticipantEdits != d.allowParticipantEdits ||
        _lastDetails!.id != d.id;
    if (shouldUpdate) {
      _lastDetails = d;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeCanEdit());
    }
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

  Widget _skeletonLine({
    double height = 12,
    double width = double.infinity,
    double radius = 8,
  }) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: .25),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _ContributeDialog(amountCtrl: amountCtrl, noteCtrl: noteCtrl),
    );

    if (confirmed != true) return;

    final cents = _eurosToCents(amountCtrl.text)!;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    try {
      final r = await _api.postJson(
        '/api/outings/${widget.outingId}/piggybank/contributions',
        {
          'userId': currentUserId,
          'amountCents': cents,
          if (note != null) 'note': note,
        },
      );
      if (r.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Contribution added!')));
        setState(() => _pbReloadNonce++);
      } else if (r.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to contribute.')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to contribute: ${r.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to contribute: $e')));
    }
  }

  Widget _buildPiggyBankCard(OutingDetails d) {
    final cs = Theme.of(context).colorScheme;

    if (!d.piggyBankEnabled ||
        d.piggyBankTargetCents == null ||
        d.piggyBankTargetCents == 0) {
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
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                  Text(
                    'Piggy Bank',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
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
            child: DefaultTextStyle.merge(
              style: TextStyle(color: cs.onSurface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Piggy Bank',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
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
                  const Text(
                    'Recent contributions',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (pb.contributions.isEmpty)
                    const Text('No contributions yet.')
                  else
                    Column(
                      children: pb.contributions.take(5).map((c) {
                        final cents =
                            c.amountCents ??
                            ((c.amount != null)
                                ? (c.amount! * 100).round()
                                : 0);
                        final euros = (cents / 100.0).toStringAsFixed(2);
                        final when =
                            c.createdAt
                                ?.toLocal()
                                .toString()
                                .split('.')
                                .first ??
                            '';
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _AddExpenseDialog(
        amountCtrl: amountCtrl,
        descCtrl: descCtrl,
        categoryCtrl: categoryCtrl,
      ),
    );

    if (confirmed != true) return;

    final cents = _eurosToCents(amountCtrl.text)!;
    final desc = descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();
    final cat = categoryCtrl.text.trim().isEmpty
        ? null
        : categoryCtrl.text.trim();

    try {
      final r = await _api
          .postJson('/api/outings/${widget.outingId}/expenses', {
            'payerId': currentUserId,
            'amountCents': cents,
            if (desc != null) 'description': desc,
            if (cat != null) 'category': cat,
          });
      if (r.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense added!')));
        setState(() => _expReloadNonce++);
      } else if (r.statusCode == 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to add expenses.')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add expense: ${r.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add expense: $e')));
    }
  }

  Widget _buildExpensesCard() {
    final cs = Theme.of(context).colorScheme;

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
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                  Text(
                    'Expenses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
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
            child: DefaultTextStyle.merge(
              style: TextStyle(color: cs.onSurface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expenses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total: €${summary.totalEuro}',
                          style: TextStyle(fontSize: 16, color: cs.onSurface),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Per person: €${summary.perPersonEuro}',
                          style: TextStyle(fontSize: 16, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Balances',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (summary.balances.isEmpty)
                    const Text('No participants yet.')
                  else
                    Column(
                      children: summary.balances.map((b) {
                        final you = context
                            .read<AuthProvider?>()
                            ?.currentUserId;
                        final isYou = (you != null && b.userId == you);
                        final label = isYou ? 'You' : b.userId;
                        final sign = b.balanceCents == 0
                            ? ''
                            : (b.balanceCents > 0 ? ' (credit)' : ' (owes)');
                        final balanceEuro = b.balanceEuro;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.account_circle_outlined),
                          title: Text(label),
                          trailing: Text('€$balanceEuro$sign'),
                          subtitle: Text(
                            'Paid: €${b.paidEuro} • Owes: €${b.owesEuro}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Recent expenses',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (summary.expenses.isEmpty)
                    const Text('No expenses yet.')
                  else
                    Column(
                      children: summary.expenses.reversed.take(5).map((e) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            '€${e.amountEuro} — ${e.description ?? 'Expense'}',
                          ),
                          subtitle: Text(
                            '${e.category ?? 'general'} • ${e.createdAt?.toLocal().toString().split('.').first ?? ''}',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
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
          ),
        );
      },
    );
  }

  // -----------------------------
  // Participants card
  // -----------------------------
  Widget _buildParticipantsCard({
    required String createdById,
    required bool allowEdits,
  }) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingParticipants) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              _skeletonLine(width: 140),
            ],
          ),
        ),
      );
    }
    if (_participantsError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Participants',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text('Failed to load: $_participantsError'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadParticipants,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_participants.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Participants',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('No participants yet.'),
            ],
          ),
        ),
      );
    }

    final me = context.read<AuthProvider?>()?.currentUserId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: cs.onSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Participants',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (allowEdits)
                    const Chip(label: Text('Participant edits on')),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                children: _participants.map((p) {
                  final isOwner = p.userId == createdById;
                  final isMe = p.userId == me;
                  final title = p.fullName ?? p.username ?? p.userId;
                  final role = isOwner ? _ParticipantRole.OWNER : p.role;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: (p.photo != null && p.photo!.isNotEmpty)
                          ? NetworkImage(p.photo!)
                          : null,
                      child: (p.photo == null || p.photo!.isEmpty)
                          ? const Icon(Icons.person_outline)
                          : null,
                    ),
                    title: Text(isMe ? '$title (You)' : title),
                    subtitle: Text(
                      role,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _loadParticipants,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------
  // Local-only body (themed)
  // -----------------------------
  Widget _buildLocalOnlyBody() {
    final cs = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<BrandColors>()!;

    return DefaultTextStyle.merge(
      style: TextStyle(color: cs.onSurface),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: brand.warning.withValues(alpha: .55)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sync, color: brand.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This outing was created while offline and will sync when you’re back online. '
                    'Some actions are temporarily disabled.',
                    style: TextStyle(color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Theme.of(context).dividerColor.withValues(alpha: .15),
                child: Icon(Icons.photo, size: 48, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Draft outing',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const Chip(label: Text('Syncing')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.place, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Location TBD',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'We’ll load full details once the server confirms this outing. You can safely leave this page.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            children: [
              Chip(
                avatar: Icon(Icons.image, size: 16),
                label: Text('Images (disabled)'),
              ),
              Chip(
                avatar: Icon(Icons.timeline, size: 16),
                label: Text('Itinerary (disabled)'),
              ),
              Chip(
                avatar: Icon(Icons.savings, size: 16),
                label: Text('Piggy Bank (disabled)'),
              ),
              Chip(
                avatar: Icon(Icons.receipt_long, size: 16),
                label: Text('Expenses (disabled)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // Scaffold
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final currentUserId = context.read<AuthProvider?>()?.currentUserId;
    final isOwnerNow =
        (_lastDetails != null &&
        currentUserId != null &&
        _lastDetails!.createdById == currentUserId);

    if (!_isLocalOnly && _detailsFuture == null) {
      _detailsFuture = _svc.fetchOutingDetails(widget.outingId);
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop<bool>(_changed),
        ),
        title: const Text('Outing details'),
        actions: [
          // Delete
          IconButton(
            tooltip: _isLocalOnly
                ? 'Delete (disabled while syncing)'
                : (isOwnerNow ? 'Delete outing' : 'Delete (owner only)'),
            onPressed: (!_isLocalOnly && isOwnerNow && _lastDetails != null)
                ? () => _confirmAndDeleteOuting(_lastDetails!)
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
          // Edit
          IconButton(
            tooltip: _isLocalOnly
                ? 'Edit (disabled while syncing)'
                : (_canEdit ? 'Edit' : 'Edit (not allowed)'),
            onPressed: _isLocalOnly || !_canEdit
                ? null
                : () async {
                    final details = _lastDetails ?? await _detailsFuture;
                    if (!mounted || details == null) return;
                    await _showEditDialog(details);
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          // Share (short)
          IconButton(
            tooltip: _isLocalOnly ? 'Share (disabled while syncing)' : 'Share',
            onPressed: _isLocalOnly
                ? null
                : () async {
                    final details = _lastDetails ?? await _detailsFuture;
                    if (!mounted || details == null) return;
                    await _maybeGuardShare(
                      details,
                      onProceed: () => _shareOutingShort(details),
                    );
                  },
            icon: const Icon(Icons.ios_share),
          ),
          // Copy link
          IconButton(
            tooltip: _isLocalOnly
                ? 'Copy link (disabled while syncing)'
                : 'Copy link',
            onPressed: _isLocalOnly
                ? null
                : () async {
                    final details = _lastDetails ?? await _detailsFuture;
                    if (!mounted || details == null) return;
                    await _maybeGuardShare(
                      details,
                      onProceed: () => _copyOutingLink(details),
                    );
                  },
            icon: const Icon(Icons.link),
          ),
          // Favorite
          IconButton(
            tooltip: _isLocalOnly
                ? 'Favorite (disabled while syncing)'
                : (_isFavorite == true ? 'Unfavorite' : 'Favorite'),
            onPressed: (_isFavorite == null || _favBusy || _isLocalOnly)
                ? null
                : _toggleFavorite,
            icon: _isLocalOnly
                ? const Icon(Icons.star_border)
                : (_favBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isFavorite == true ? Icons.star : Icons.star_border,
                          color: _isFavorite == true ? cs.tertiary : null,
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
                key: ValueKey('details-${widget.outingId}'),
                future: _detailsFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: .25),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _skeletonLine(width: 200, height: 18),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.place,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
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
                            Icon(
                              Icons.error_outline,
                              size: 36,
                              color: cs.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              snap.error?.toString() ??
                                  'Failed to load outing.',
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(
                                  () => _detailsFuture = _svc
                                      .fetchOutingDetails(widget.outingId),
                                );
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final d = snap.data!;
                  _maybeAbsorbDetailsForPermissions(d);

                  final me = context.read<AuthProvider?>()?.currentUserId;
                  final isOwner = (me != null && d.createdById == me);
                  final visibilityStr =
                      (d.visibility ?? _OutingVisibility.INVITED).toString();
                  final allowEdits = d.allowParticipantEdits ?? false;
                  final showOrganizer = d.showOrganizer ?? true;

                  return DefaultTextStyle.merge(
                    style: TextStyle(color: cs.onSurface),
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (d.imageUrl != null)
                          Hero(
                            tag: 'outing:${widget.outingId}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                d.imageUrl!,
                                height: 200,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                d.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Chip(label: Text(d.type)),
                          ],
                        ),
                        if (d.subtitle != null)
                          Text(
                            d.subtitle!,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        if ((d.organizerHidden ?? false) == true) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.privacy_tip_outlined,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Organizer hidden by privacy settings.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.place,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${d.lat.toStringAsFixed(5)}, ${d.lng.toStringAsFixed(5)}',
                              style: TextStyle(color: cs.onSurface),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (d.description != null) Text(d.description!),
                        const SizedBox(height: 16),
                        if (d.address != null)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(d.address!)),
                            ],
                          ),
                        if (d.startsAt != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.event, color: cs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(d.startsAt!.toLocal().toString()),
                            ],
                          ),
                        ],

                        if (isOwner) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.public),
                                label: const Text('Publish / Settings'),
                                onPressed: () => _openPublishSheet(
                                  currentVisibility: visibilityStr,
                                  currentAllowEdits: allowEdits,
                                  currentShowOrganizer: showOrganizer,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Invite people'),
                                onPressed: _openInviteDialog,
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('Participants'),
                              onPressed: () =>
                                  _scrollToSection(_participantsKey),
                            ),
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

                        const SizedBox(height: 16),
                        Container(
                          key: _participantsKey,
                          padding: const EdgeInsets.only(top: 2),
                          child: _buildParticipantsCard(
                            createdById: d.createdById,
                            allowEdits: allowEdits,
                          ),
                        ),

                        const SizedBox(height: 16),
                        Container(
                          key: _imagesKey,
                          padding: const EdgeInsets.only(top: 2),
                          child: const Text(
                            'Images',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _reloadingImages
                                  ? null
                                  : () {
                                      setState(() => _reloadingImages = true);
                                      Future.delayed(
                                        const Duration(milliseconds: 50),
                                        () {
                                          if (mounted) {
                                            setState(
                                              () => _reloadingImages = false,
                                            );
                                          }
                                        },
                                      );
                                    },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh images'),
                            ),
                          ],
                        ),
                        OutingImageUploader(
                          key: ValueKey(
                            'images-${widget.outingId}-${_reloadingImages ? 'r' : 'n'}',
                          ),
                          outingId: widget.outingId,
                          api: _api,
                        ),

                        const SizedBox(height: 16),
                        Container(
                          key: _itineraryKey,
                          padding: const EdgeInsets.only(top: 2),
                          child: const Text(
                            'Itinerary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _reloadingItinerary
                                  ? null
                                  : () {
                                      setState(
                                        () => _reloadingItinerary = true,
                                      );
                                      Future.delayed(
                                        const Duration(milliseconds: 50),
                                        () {
                                          if (mounted) {
                                            setState(
                                              () => _reloadingItinerary = false,
                                            );
                                          }
                                        },
                                      );
                                    },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh itinerary'),
                            ),
                          ],
                        ),
                        ItineraryTimeline(
                          key: ValueKey(
                            'itin-${widget.outingId}-${_reloadingItinerary ? 'r' : 'n'}',
                          ),
                          outingId: widget.outingId,
                          api: _api,
                        ),

                        const SizedBox(height: 16),
                        _buildPiggyBankCard(d),

                        const SizedBox(height: 16),
                        Container(
                          key: _expensesKey,
                          padding: const EdgeInsets.only(top: 2),
                          child: _buildExpensesCard(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );

    // Wrap with WillPopScope to return the "changed" flag to parents
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop<bool>(_changed);
        return false;
      },
      child: scaffold,
    );
  }
}

// -----------------------------
// Dialogs (now accept controllers from caller)
// -----------------------------
class _EditOutingDialog extends StatelessWidget {
  const _EditOutingDialog({required this.titleCtrl, required this.notesCtrl});
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    return AlertDialog(
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
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ContributeDialog extends StatelessWidget {
  const _ContributeDialog({required this.amountCtrl, required this.noteCtrl});
  final TextEditingController amountCtrl;
  final TextEditingController noteCtrl;

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    int? _eurosToCents(String input) {
      final sanitized = input.replaceAll(',', '.').trim();
      final value = double.tryParse(sanitized);
      if (value == null) return null;
      return (value * 100).round();
    }

    return AlertDialog(
      title: const Text('Contribute to Piggy Bank'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('Contribute'),
        ),
      ],
    );
  }
}

class _AddExpenseDialog extends StatelessWidget {
  const _AddExpenseDialog({
    required this.amountCtrl,
    required this.descCtrl,
    required this.categoryCtrl,
  });

  final TextEditingController amountCtrl;
  final TextEditingController descCtrl;
  final TextEditingController categoryCtrl;

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    int? _eurosToCents(String input) {
      final sanitized = input.replaceAll(',', '.').trim();
      final value = double.tryParse(sanitized);
      if (value == null) return null;
      return (value * 100).round();
    }

    return AlertDialog(
      title: const Text('Add expense'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = <String, String>{
      _OutingVisibility.PUBLIC: 'Public',
      _OutingVisibility.CONTACTS: 'Contacts',
      _OutingVisibility.INVITED: 'Only invited',
      _OutingVisibility.GROUPS: 'Groups',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: _OutingVisibility.PUBLIC,
                label: Text(labels[_OutingVisibility.PUBLIC]!),
                icon: const Icon(Icons.public),
              ),
              ButtonSegment(
                value: _OutingVisibility.CONTACTS,
                label: Text(labels[_OutingVisibility.CONTACTS]!),
                icon: const Icon(Icons.people_alt_outlined),
              ),
              ButtonSegment(
                value: _OutingVisibility.INVITED,
                label: Text(labels[_OutingVisibility.INVITED]!),
                icon: const Icon(Icons.mail_outline),
              ),
              ButtonSegment(
                value: _OutingVisibility.GROUPS,
                label: Text(labels[_OutingVisibility.GROUPS]!),
                icon: const Icon(Icons.group_work_outlined),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          switch (value) {
            _OutingVisibility.PUBLIC => 'Anyone can find and view.',
            _OutingVisibility.CONTACTS => 'Visible to your contacts.',
            _OutingVisibility.INVITED => 'Only invited people can view.',
            _OutingVisibility.GROUPS => 'Visible to selected groups.',
            _ => '',
          },
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
