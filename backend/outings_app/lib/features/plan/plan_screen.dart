import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:outings_app/features/auth/auth_provider.dart';
import 'package:outings_app/config/app_config.dart';
import 'package:outings_app/services/api_client.dart';
import 'package:outings_app/features/outings/outing_share_service.dart';
import 'package:outings_app/features/contacts/widgets/contact_multi_select_dialog.dart';

// 👇 Friendly-name resolver
import 'package:outings_app/features/contacts/display_name.dart';

ApiClient _apiFromContext(BuildContext context) {
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenProvider: () {
      try {
        final auth = context.read<AuthProvider>();
        final dyn = auth as dynamic;
        final t = (dyn.authToken ?? dyn.token) as String?;
        return t ?? '';
      } catch (_) {
        return '';
      }
    },
  );
}

// Human-friendly visibility label
String _visLabel(String v) =>
    const {
      OutingVisibility.PUBLIC: 'Public',
      OutingVisibility.CONTACTS: 'Contacts',
      OutingVisibility.INVITED: 'Only Invited',
      OutingVisibility.GROUPS: 'Selected Groups',
    }[v] ??
    v;

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final OutingShareService _svc;

  // Data
  List<OutingLite> _mine = const [];
  List<OutingLite> _shared = const [];
  List<OutingInvite> _invites = const []; // incoming
  List<OutingInvite> _sent = const []; // sent by me (organizer)

  // Title cache (outingId -> title)
  final Map<String, String> _titleById = {};

  bool _loadingMine = true;
  bool _loadingShared = true;
  bool _loadingInvites = true;
  bool _loadingSent = true;

  String? _errorMine;
  String? _errorShared;
  String? _errorInvites;
  String? _errorSent;

  @override
  void initState() {
    super.initState();
    _svc = OutingShareService(_apiFromContext(context));
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadMine(),
      _loadShared(),
      _loadInvites(),
      _loadSent(),
    ]);
  }

  // --- helpers ---------------------------------------------------------------

  String _initialsFrom(String s) {
    final clean = s.trim();
    if (clean.isEmpty) return '🙂';
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return (words.first[0] + words.last[0]).toUpperCase();
    }
    return words.first[0].toUpperCase();
  }

  // Friendly-name helpers for invites/sent
  String _displayForInvitee(OutingInvite inv, DisplayNameResolver r) {
    if ((inv.inviteeUserId ?? '').isNotEmpty) {
      return r.forUserId(
        inv.inviteeUserId!,
        fallback: 'user:${inv.inviteeUserId}',
      );
    }
    return inv.inviteeContact ?? '—';
  }

  String _displayForInviter(OutingInvite inv, DisplayNameResolver r) {
    return r.forUserId(inv.inviterId, fallback: inv.inviterId);
  }

  String _initialsForUserOrContact({
    required DisplayNameResolver r,
    String? userId,
    String? contact,
  }) {
    if ((userId ?? '').isNotEmpty) return r.initialsFor(userId!);
    final s = (contact ?? '').trim();
    final letters = RegExp(
      r'[A-Za-z0-9]',
    ).allMatches(s).map((m) => m.group(0)!).toList();
    if (letters.isEmpty) return '🙂';
    final a = letters.first.toUpperCase();
    final b = letters.length > 1 ? letters[1].toUpperCase() : '';
    return (a + b);
  }

  Future<void> _ensureTitlesFor(Iterable<String> ids) async {
    for (final o in _mine) {
      _titleById[o.id] = o.title;
    }
    for (final o in _shared) {
      _titleById[o.id] = o.title;
    }

    final missing = ids
        .where((id) => (_titleById[id] == null || _titleById[id]!.isEmpty))
        .toSet();
    if (missing.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    try {
      final results = await Future.wait(missing.map(_svc.getOutingLiteById));
      for (final o in results) {
        _titleById[o.id] = o.title;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // --- loads ----------------------------------------------------------------

  Future<void> _loadMine() async {
    setState(() {
      _loadingMine = true;
      _errorMine = null;
    });
    try {
      final items = await _svc.listMyOutings();
      if (!mounted) return;
      setState(() {
        _mine = items;
        for (final o in items) {
          _titleById[o.id] = o.title;
        }
        _loadingMine = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMine = e.toString();
        _loadingMine = false;
      });
    }
  }

  Future<void> _loadShared() async {
    setState(() {
      _loadingShared = true;
      _errorShared = null;
    });
    try {
      final items = await _svc.listSharedWithMe();
      if (!mounted) return;
      setState(() {
        _shared = items;
        for (final o in items) {
          _titleById[o.id] = o.title;
        }
        _loadingShared = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorShared = e.toString();
        _loadingShared = false;
      });
    }
  }

  Future<void> _loadInvites() async {
    setState(() {
      _loadingInvites = true;
      _errorInvites = null;
    });
    try {
      final items = await _svc.listMyInvites(); // PENDING by default
      if (!mounted) return;
      setState(() {
        _invites = items;
        _loadingInvites = false;
      });
      for (final i in items) {
        if (i.outingTitle != null && i.outingTitle!.isNotEmpty) {
          _titleById[i.outingId] = i.outingTitle!;
        }
      }
      await _ensureTitlesFor(items.map((i) => i.outingId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorInvites = e.toString();
        _loadingInvites = false;
      });
    }
  }

  Future<void> _loadSent() async {
    setState(() {
      _loadingSent = true;
      _errorSent = null;
    });
    try {
      final items = await _svc.listSentInvites();
      if (!mounted) return;
      setState(() {
        _sent = items;
        _loadingSent = false;
      });
      for (final i in items) {
        if (i.outingTitle != null && i.outingTitle!.isNotEmpty) {
          _titleById[i.outingId] = i.outingTitle!;
        }
      }
      await _ensureTitlesFor(items.map((i) => i.outingId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorSent = e.toString();
        _loadingSent = false;
      });
    }
  }

  // -------- Actions: Publish + Invite + Accept/Decline --------

  Future<void> _openPublishSheet(OutingLite o) async {
    String visibility = o.visibility;
    bool allowEdits = o.allowParticipantEdits;
    bool showOrganizer = o.showOrganizer ?? true;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            const navBuffer = kBottomNavigationBarHeight + 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset + navBuffer),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Publish Outing',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                                await _svc.publishOuting(
                                  outingId: o.id,
                                  visibility: visibility,
                                  allowParticipantEdits: allowEdits,
                                  showOrganizer: showOrganizer,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Outing published'),
                                    ),
                                  );
                                }
                                if (mounted) Navigator.of(ctx).maybePop();
                                await _loadMine();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Publish failed: $e')),
                                );
                              }
                            },
                            child: const Text('Publish'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _joinUrl(String code) {
    final base = AppConfig.apiBaseUrl;
    final root = base
        .replaceFirst(RegExp(r'/api/?$'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return '$root/join/$code';
  }

  Future<void> _openInviteDialog(OutingLite o) async {
    await showDialog(
      context: context,
      builder: (_) => ContactMultiSelectDialog(svc: _svc, outingId: o.id),
    );
    await _loadSent();
  }

  Future<void> _acceptInvite(OutingInvite inv) async {
    try {
      await _svc.acceptInvite(inv.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted')));
      await _loadInvites();
      await _loadShared();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _declineInvite(OutingInvite inv) async {
    try {
      await _svc.declineInvite(inv.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite declined')));
      await _loadInvites();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan'),
          actions: [
            IconButton(
              tooltip: 'Create Outing',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final created = await context.push<bool>('/plan/create');
                if (created == true) await _loadMine();
              },
            ),
            IconButton(
              tooltip: 'My Outings',
              icon: const Icon(Icons.list_alt),
              onPressed: () => context.go('/my-outings'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Outings'),
              Tab(text: 'Shared with Me'),
              Tab(text: 'Invites'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMine(),
            _buildShared(),
            _buildInvites(),
            _buildSent(),
          ],
        ),
      ),
    );
  }

  Widget _buildMine() {
    if (_loadingMine) return const Center(child: CircularProgressIndicator());
    if (_errorMine != null) {
      return _ErrorState(message: _errorMine!, onRetry: _loadMine);
    }
    if (_mine.isEmpty) {
      return _Empty(
        text: 'No outings yet. Create one to get started.',
        actionText: 'Create Outing',
        onAction: () async {
          final created = await context.push<bool>('/plan/create');
          if (created == true) await _loadMine();
        },
      );
    }

    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        itemCount: _mine.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = _mine[i];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              onTap: () async {
                final changed = await context.push<bool>(
                  '/plan/outings/${o.id}',
                );
                if (changed == true) {
                  await _loadMine();
                }
              },
              title: Text(o.title),
              subtitle: Text(
                [
                  if (o.dateTimeStart != null)
                    MaterialLocalizations.of(
                      context,
                    ).formatShortDate(o.dateTimeStart!),
                  o.isPublished ? 'Published' : 'Draft',
                  _visLabel(o.visibility),
                ].join(' • '),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'publish') _openPublishSheet(o);
                  if (v == 'invite') _openInviteDialog(o);
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'publish',
                    child: Text('Publish / Settings'),
                  ),
                  PopupMenuItem(value: 'invite', child: Text('Invite people')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShared() {
    if (_loadingShared) return const Center(child: CircularProgressIndicator());
    if (_errorShared != null) {
      return _ErrorState(message: _errorShared!, onRetry: _loadShared);
    }
    if (_shared.isEmpty)
      return const _Empty(text: 'Nothing shared with you yet.');

    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadShared,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        itemCount: _shared.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final o = _shared[i];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              onTap: () async {
                final changed = await context.push<bool>(
                  '/plan/outings/${o.id}',
                );
                if (changed == true) {
                  await _loadShared();
                }
              },
              title: Text(o.title),
              subtitle: Text(
                [
                  if (o.dateTimeStart != null)
                    MaterialLocalizations.of(
                      context,
                    ).formatShortDate(o.dateTimeStart!),
                  _visLabel(o.visibility),
                  o.isPublished ? 'Published' : 'Draft',
                ].join(' • '),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInvites() {
    final resolver = DisplayNameResolver.of(context);

    if (_loadingInvites)
      return const Center(child: CircularProgressIndicator());
    if (_errorInvites != null) {
      return _ErrorState(message: _errorInvites!, onRetry: _loadInvites);
    }
    if (_invites.isEmpty) return const _Empty(text: 'No pending invites.');

    return RefreshIndicator(
      onRefresh: _loadInvites,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        itemCount: _invites.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final inv = _invites[i];
          final title =
              _titleById[inv.outingId] ?? inv.outingTitle ?? inv.outingId;

          final fromName = _displayForInviter(inv, resolver);
          final initials = _initialsForUserOrContact(
            r: resolver,
            userId: inv.inviterId,
          );

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: CircleAvatar(child: Text(initials)),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('From: $fromName • ${inv.status}'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _declineInvite(inv),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: () => _acceptInvite(inv),
                    child: const Text('Accept'),
                  ),
                ],
              ),
              onTap: () async {
                final changed = await context.push<bool>(
                  '/plan/outings/${inv.outingId}',
                );
                if (changed == true) {
                  // Invitations can be invalidated by deletes; safest is to refresh all
                  await _refreshAll();
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSent() {
    final resolver = DisplayNameResolver.of(context);

    if (_loadingSent) return const Center(child: CircularProgressIndicator());
    if (_errorSent != null) {
      return _ErrorState(message: _errorSent!, onRetry: _loadSent);
    }
    if (_sent.isEmpty) return const _Empty(text: 'No sent invites yet.');

    return RefreshIndicator(
      onRefresh: _loadSent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        itemCount: _sent.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final inv = _sent[i];
          final toName = _displayForInvitee(inv, resolver);
          final initials = _initialsForUserOrContact(
            r: resolver,
            userId: inv.inviteeUserId,
            contact: inv.inviteeContact,
          );
          final joinUrl = _joinUrl(inv.code);
          final title =
              _titleById[inv.outingId] ?? inv.outingTitle ?? inv.outingId;

          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: CircleAvatar(child: Text(initials)),
              title: Text('To: $toName'),
              subtitle: Text('$title • ${inv.status}'),
              trailing: IconButton(
                tooltip: 'Copy join link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: joinUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Join link copied')),
                  );
                },
                icon: const Icon(Icons.link),
              ),
              onTap: () async {
                final changed = await context.push<bool>(
                  '/plan/outings/${inv.outingId}',
                );
                if (changed == true) {
                  await _loadSent();
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  const _Empty({required this.text, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: const TextStyle(color: Colors.black54)),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = <String, String>{
      OutingVisibility.PUBLIC: 'Public',
      OutingVisibility.CONTACTS: 'Contacts',
      OutingVisibility.INVITED: 'Only Invited',
      OutingVisibility.GROUPS: 'Selected Groups',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: opts.entries.map((e) {
        return RadioListTile<String>(
          value: e.key,
          groupValue: value,
          title: Text(e.value),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      }).toList(),
    );
  }
}
