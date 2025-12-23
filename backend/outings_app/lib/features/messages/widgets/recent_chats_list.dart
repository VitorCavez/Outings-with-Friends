// lib/features/messages/widgets/recent_chats_list.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:outings_app/features/messages/messages_repository.dart';
import 'package:outings_app/features/contacts/display_name.dart';

import 'package:provider/provider.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../services/api_client.dart';
import '../../../config/app_config.dart';
import '../../../services/messages_service.dart';

// Brand tokens (ThemeExtension)
import 'package:outings_app/theme/app_theme.dart';

/// Shows both DM and Group recent threads.
///
/// Data source priority:
///  1) Live from /api/messages/recent (auth via JWT; no userId param)
///  2) Fallback to local unified cache (MessagesRepository.recentThreads)
class RecentChatsList extends StatefulWidget {
  const RecentChatsList({super.key});

  @override
  State<RecentChatsList> createState() => _RecentChatsListState();
}

class _RecentChatsListState extends State<RecentChatsList> {
  late final MessagesRepository _repo = MessagesRepository();
  List<Map<String, dynamic>> _threads = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Re-fetch when the repo cache changes (e.g., after sending/receiving a message)
    _repo.revision.addListener(_onRepoRevision);
    _refresh();
  }

  void _onRepoRevision() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _repo.revision.removeListener(_onRepoRevision);
    super.dispose();
  }

  ApiClient _buildApiClient() {
    String? token;
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      token = (dyn.authToken ?? dyn.token) as String?;
    } catch (_) {}
    return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final svc = MessagesService(_buildApiClient());
      // Backend uses JWT via requireAuth
      final list = await svc.fetchRecent(limit: 40);

      // Ensure safe map shape + normalize fields
      final parsed = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(_normalizeThread)
          .toList();

      if (!mounted) return;
      setState(() {
        _threads = parsed;
        _loading = false;
      });
      return;
    } catch (e) {
      // Fallback to local unified cache so the page isn't empty offline
      final fallback = _buildUnifiedFallback(_repo);
      if (!mounted) return;
      setState(() {
        _threads = fallback;
        _loading = false;
        _error = e;
      });
    }
  }

  /// Normalize one thread into a consistent shape so the UI doesn’t
  /// depend on the exact backend JSON.
  ///
  /// Ensures:
  ///   kind: 'dm' | 'group'
  ///   peerId / groupId
  ///   title
  ///   lastText
  ///   lastAt
  Map<String, dynamic> _normalizeThread(Map<String, dynamic> t) {
    final out = Map<String, dynamic>.from(t);

    // ---- kind ----
    String kind = (t['kind'] ?? '').toString();
    if (kind.isEmpty) {
      // Heuristic: if there is any groupId, treat as group; otherwise DM
      final gId = t['groupId'] ?? t['group_id'];
      kind = (gId != null && gId.toString().isNotEmpty) ? 'group' : 'dm';
    }
    out['kind'] = kind;

    // ---- DM threads ----
    if (kind == 'dm') {
      final peer =
          (t['peer'] ??
                  t['user'] ??
                  t['otherUser'] ??
                  t['participant'] ??
                  t['member'])
              as Map<String, dynamic>?;

      String? peerId = t['peerId']?.toString();
      if (peer != null && peerId == null) {
        peerId = peer['id']?.toString();
      }
      out['peerId'] = peerId;

      final title = _firstNonEmpty([
        peer?['displayName'],
        peer?['fullName'],
        peer?['name'],
        peer?['username'],
        t['displayName'],
        t['title'],
      ]);

      if (title != null && title.trim().isNotEmpty) {
        out['title'] = title.trim();
      } else if (peerId != null) {
        out['title'] = peerId;
      }
    } else {
      // ---- Group threads ----
      final group =
          (t['group'] ?? t['room'] ?? t['chat']) as Map<String, dynamic>?;

      String? groupId = t['groupId']?.toString();
      if (group != null && groupId == null) {
        groupId = group['id']?.toString();
      }
      out['groupId'] = groupId;

      final title = _firstNonEmpty([
        group?['name'],
        group?['title'],
        group?['displayName'],
        t['title'],
      ]);

      if (title != null && title.trim().isNotEmpty) {
        out['title'] = title.trim();
      } else if (groupId != null) {
        out['title'] = 'Group $groupId';
      }
    }

    // ---- lastAt ----
    final rawLast =
        t['lastAt'] ?? t['last_at'] ?? t['updatedAt'] ?? t['createdAt'];
    out['lastAt'] = rawLast;

    // ---- lastText ----
    final lastMessage = t['lastMessage'];
    out['lastText'] =
        _firstNonEmpty([
          t['lastText'],
          t['lastMessageText'],
          lastMessage is Map<String, dynamic> ? lastMessage['text'] : null,
        ]) ??
        '';

    return out;
  }

  /// Build a unified (DM + Group) fallback from the local cache.
  List<Map<String, dynamic>> _buildUnifiedFallback(MessagesRepository repo) {
    final recents = repo.recentThreads(); // DM + Group, newest first
    return recents.map((t) {
      final last = t.last;
      if (t.kind == 'dm') {
        return {
          'kind': 'dm',
          'peerId': t.peerId,
          'groupId': null,
          'title': t.peerId, // pretty name resolved in build()
          'avatarUrl': null,
          'lastText': last.text,
          'lastAt': last.createdAt.toIso8601String(),
        };
      } else {
        return {
          'kind': 'group',
          'peerId': null,
          'groupId': t.groupId,
          // We might not know the group name here; use groupId for now.
          'title': t.groupId,
          'avatarUrl': null,
          'lastText': last.text,
          'lastAt': last.createdAt.toIso8601String(),
        };
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final resolver = DisplayNameResolver.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_threads.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Recent chats',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: c.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Start a conversation from the Contacts tab,\n'
              'or pick one from your recent chats here.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    // Normalize lastAt to DateTime and sort newest first
    final rows =
        _threads.map((t) => Map<String, dynamic>.from(t)).map((t) {
          final raw = t['lastAt'];
          DateTime? lastAt;
          if (raw is String) {
            lastAt = DateTime.tryParse(raw);
          } else if (raw is int) {
            lastAt = DateTime.fromMillisecondsSinceEpoch(raw);
          } else if (raw is DateTime) {
            lastAt = raw;
          }
          return {...t, 'lastAt': lastAt ?? DateTime.now()};
        }).toList()..sort(
          (a, b) =>
              (b['lastAt'] as DateTime).compareTo(a['lastAt'] as DateTime),
        );

    return RefreshIndicator(
      onRefresh: _refresh,
      color: c.primary,
      backgroundColor: c.surface,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: c.outlineVariant),
        itemBuilder: (context, i) {
          final t = rows[i];
          final kind = (t['kind'] ?? '').toString(); // 'dm' | 'group'
          final groupId = t['groupId']?.toString();
          final peerId = t['peerId']?.toString();
          final lastAt = (t['lastAt'] as DateTime);

          // Title: for DMs prefer friendly display name
          String title;
          if (kind == 'dm' && peerId != null) {
            title = resolver.forUserId(
              peerId,
              fallback: t['title']?.toString() ?? peerId,
            );
          } else {
            title = t['title']?.toString() ?? groupId ?? 'Chat';
          }

          final initials = (kind == 'dm' && peerId != null)
              ? resolver.initialsFor(peerId)
              : _initialsFrom(title);

          final subtitle = _previewText(t['lastText']?.toString() ?? '');

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: c.secondaryContainer,
              foregroundColor: c.onSecondaryContainer,
              child: Text(initials),
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: c.onSurface),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            trailing: Text(
              _fmtTime(lastAt),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: c.onSurfaceVariant),
            ),
            onTap: () {
              if (kind == 'group' && groupId != null) {
                context.go('/messages/group/$groupId');
              } else if (kind == 'dm' && peerId != null) {
                context.go('/messages/chat/$peerId');
              }
            },
          );
        },
      ),
    );
  }

  static String _previewText(String text) {
    if (text.isEmpty) return '—';
    return text;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  static String _initialsFrom(String s) {
    final words = s
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '🙂';
    if (words.length == 1) {
      final w = words.first;
      return w.length >= 2 ? w.substring(0, 2).toUpperCase() : w.toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c == null) continue;
      final s = c.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
