// lib/features/profile/pages/profile_page.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/user_profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../auth/auth_provider.dart';
import '../widgets/badge_chip.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.userId, required this.api});
  final String userId;
  final ApiClient api;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late ProfileService _svc;

  bool _loadingHeader = false;
  UserProfile? _profile;

  bool _loadingHistory = false;
  List<ProfileHistoryItem> _history = const [];

  bool _loadingFavorites = false;
  List<Map<String, dynamic>> _favorites = const [];

  bool _loadingTimeline = false;
  List<TimelineEntry> _timeline = const [];

  // History filter
  String _historyRole = 'all'; // all | host | guest

  final _dfDate = DateFormat('EEE, MMM d');
  final _dfTime = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _svc = ProfileService(widget.api);
    _loadAll();
  }

  /// 🔁 If GoRouter reuses this page but the userId (or ApiClient) changes,
  /// force a fresh load so we don't keep showing the previous user's data.
  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.api != widget.api) {
      _svc = ProfileService(widget.api);
      _profile = null;
      _history = const [];
      _favorites = const [];
      _timeline = const [];
      _loadAll();
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadHeader(),
      _loadHistory(),
      _loadFavorites(),
      _loadTimeline(),
    ]);
  }

  Future<void> _refreshAll() => _loadAll();

  Future<void> _loadHeader() async {
    setState(() => _loadingHeader = true);
    try {
      final p = await _svc.getPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() => _profile = p);
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      if (msg.contains('PROFILE_PRIVATE')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile is private')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingHeader = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final resp = await _svc.fetchHistory(
        widget.userId,
        role: _historyRole,
        limit: 50,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _history = resp.items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load history: $e')));
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _loadingFavorites = true);
    try {
      final items = await _svc.listMyFavorites();
      if (!mounted) return;
      setState(() => _favorites = items);
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      // If unauthorized, just show an empty favorites section without spamming errors.
      if (msg.contains('401')) {
        setState(() => _favorites = const []);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load favorites: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingFavorites = false);
    }
  }

  Future<void> _loadTimeline() async {
    setState(() => _loadingTimeline = true);
    try {
      final resp = await _svc.fetchTimeline(
        widget.userId,
        limit: 50,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _timeline = resp.items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load timeline: $e')));
    } finally {
      if (mounted) setState(() => _loadingTimeline = false);
    }
  }

  String _fmtRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return '';
    if (start != null && end != null) {
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      if (sameDay) {
        return '${_dfDate.format(start)} • ${_dfTime.format(start)}–${_dfTime.format(end)}';
      } else {
        return '${_dfDate.format(start)} ${_dfTime.format(start)} → ${_dfDate.format(end)} ${_dfTime.format(end)}';
      }
    }
    if (start != null) {
      return '${_dfDate.format(start)} • ${_dfTime.format(start)}';
    }
    return '${_dfDate.format(end!)} • ${_dfTime.format(end)}';
  }

  void _openOuting(String? id) {
    if (id == null || id.isEmpty) return;
    context.push('/outings/$id');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtle = cs.onSurfaceVariant;
    final p = _profile;

    final body = _loadingHeader
        ? const Center(child: CircularProgressIndicator())
        : p == null
        ? const Center(child: Text('No profile data'))
        : DefaultTextStyle.merge(
            // ✅ Force readable, high-contrast default text
            style: TextStyle(color: cs.onSurface),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: p.profilePhotoUrl != null
                            ? CachedNetworkImageProvider(p.profilePhotoUrl!)
                            : null,
                        child: p.profilePhotoUrl == null
                            ? const Icon(Icons.person, size: 36)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.fullName,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: cs.onSurface),
                            ),
                            if (p.username != null)
                              Text(
                                '@${p.username}',
                                style: TextStyle(color: subtle),
                              ),
                            if (p.homeLocation != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: subtle,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    p.homeLocation!,
                                    style: TextStyle(color: subtle),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            'Score',
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(color: subtle),
                          ),
                          Text(
                            '${p.outingScore}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: cs.onSurface),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (p.bio != null && p.bio!.isNotEmpty)
                    Text(p.bio!, style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 16),
                  if (p.badges.isNotEmpty) ...[
                    Text(
                      'Badges',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: p.badges
                          .map((b) => BadgeChip(text: b))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Outing History (+ filter)
                  _Section(
                    title: 'Outing History',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loadingHistory)
                          const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        const SizedBox(width: 8),
                        // Prevent overflow on narrow screens
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'all', label: Text('All')),
                              ButtonSegment(value: 'host', label: Text('Host')),
                              ButtonSegment(
                                value: 'guest',
                                label: Text('Guest'),
                              ),
                            ],
                            selected: {_historyRole},
                            onSelectionChanged: (s) async {
                              final next = s.first;
                              setState(() => _historyRole = next);
                              await _loadHistory();
                            },
                          ),
                        ),
                      ],
                    ),
                    child: _loadingHistory
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('Loading…'),
                          )
                        : _history.isEmpty
                        ? const Text('No past outings yet.')
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _history.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) {
                              final h = _history[i];
                              final role =
                                  h.role ??
                                  (h.createdById == widget.userId
                                      ? 'host'
                                      : 'guest');
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.event_available_outlined,
                                  color: subtle,
                                ),
                                title: Text(h.title),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _fmtRange(h.dateTimeStart, h.dateTimeEnd),
                                      style: TextStyle(color: subtle),
                                    ),
                                    if (h.locationName != null)
                                      Text(
                                        h.locationName!,
                                        style: TextStyle(color: subtle),
                                      ),
                                    if (h.rsvpStatus != null)
                                      Text(
                                        'RSVP: ${h.rsvpStatus}',
                                        style: TextStyle(color: subtle),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openOuting(h.id),
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                minLeadingWidth: 20,
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Favorites
                  _Section(
                    title: 'Favorites',
                    trailing: _loadingFavorites
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    child: _loadingFavorites
                        ? const Text('Loading…')
                        : _favorites.isEmpty
                        ? const Text('No favorites yet.')
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _favorites.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) {
                              final item = _favorites[i];
                              // structure: { id, userId, outingId, createdAt, outing: { id,title,locationName,dateTimeStart, coverImageUrl? } }
                              final o =
                                  (item['outing'] ?? {})
                                      as Map<String, dynamic>;
                              final outingId = (o['id'] ?? '') as String;
                              final title = (o['title'] ?? 'Outing') as String;
                              final loc = o['locationName'] as String?;
                              final dt = o['dateTimeStart'] != null
                                  ? DateTime.tryParse(
                                      o['dateTimeStart'].toString(),
                                    )
                                  : null;
                              final when = dt == null
                                  ? ''
                                  : _fmtRange(dt, null);
                              final cover = o['coverImageUrl'] as String?;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: cover == null
                                    ? const CircleAvatar(
                                        child: Icon(Icons.star),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: cover,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                title: Text(title),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (loc != null)
                                      Text(
                                        loc,
                                        style: TextStyle(color: subtle),
                                      ),
                                    if (when.isNotEmpty)
                                      Text(
                                        when,
                                        style: TextStyle(color: subtle),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openOuting(outingId),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Trip Timeline
                  _Section(
                    title: 'Trip Timeline',
                    trailing: _loadingTimeline
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    child: _loadingTimeline
                        ? const Text('Loading…')
                        : _timeline.isEmpty
                        ? const Text('No calendar entries yet.')
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _timeline.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 16),
                            itemBuilder: (ctx, i) {
                              final e = _timeline[i];
                              final linked = e.linkedOuting;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // timeline dot + line
                                  Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: cs.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      if (i != _timeline.length - 1)
                                        Container(
                                          width: 2,
                                          height: 40,
                                          color: Theme.of(context).dividerColor,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(color: cs.onSurface),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _fmtRange(
                                            e.dateTimeStart,
                                            e.dateTimeEnd,
                                          ),
                                          style: TextStyle(color: subtle),
                                        ),
                                        if (e.description != null &&
                                            e.description!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            e.description!,
                                            style: const TextStyle(height: 1.3),
                                          ),
                                        ],
                                        if (linked != null) ...[
                                          const SizedBox(height: 6),
                                          InkWell(
                                            onTap: () => _openOuting(linked.id),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.link,
                                                  size: 16,
                                                  color: subtle,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Linked outing: ${linked.title}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: subtle,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') {
                final auth = context.read<AuthProvider>();
                await auth.signOut(context);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Log out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refreshAll, child: body),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      surfaceTintColor: Colors
          .transparent, // ✅ prevent M3 tint from washing the card (helps readability)
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: DefaultTextStyle.merge(
          // ✅ ensure all inner text defaults to readable color
          style: TextStyle(color: cs.onSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
