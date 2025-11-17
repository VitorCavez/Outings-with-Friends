// lib/features/contacts/widgets/contact_multi_select_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/outings/outing_share_service.dart';
import '../../../providers/contacts_provider.dart';
import '../display_name.dart';

class ContactMultiSelectDialog extends StatefulWidget {
  const ContactMultiSelectDialog({
    super.key,
    required this.svc,
    required this.outingId,
  });

  final OutingShareService svc;
  final String outingId;

  @override
  State<ContactMultiSelectDialog> createState() =>
      _ContactMultiSelectDialogState();
}

class _ContactMultiSelectDialogState extends State<ContactMultiSelectDialog> {
  final _search = TextEditingController();
  final _manual = TextEditingController();
  final Set<String> _selectedUserIds = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    // Kick a refresh if the list is empty or stale
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<ContactsProvider>();
      if (prov.contacts.isEmpty && !prov.loading) {
        setState(() => _loading = true);
        try {
          await prov.refresh();
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _manual.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> contacts) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return contacts;
    return contacts.where((c) {
      final user = (c['user'] ?? {}) as Map<String, dynamic>;
      final name = (user['fullName'] ?? user['username'] ?? '').toString();
      final phone = (user['phone'] ?? c['phone'] ?? '').toString();
      final email = (user['email'] ?? c['email'] ?? '').toString();
      return name.toLowerCase().contains(q) ||
          phone.toLowerCase().contains(q) ||
          email.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _send() async {
    if (_selectedUserIds.isEmpty && _manual.text.trim().isEmpty) {
      Navigator.of(context).maybePop(); // nothing chosen
      return;
    }

    final contacts = _manual.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    try {
      setState(() => _loading = true);
      await widget.svc.createInvites(
        outingId: widget.outingId,
        userIds: _selectedUserIds.isEmpty ? null : _selectedUserIds.toList(),
        contacts: contacts.isEmpty ? null : contacts,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invites sent')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send invites: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;

    final nameResolver = DisplayNameResolver.of(context);
    final prov = context.watch<ContactsProvider>();
    final items = _filtered(prov.contacts);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Invite people',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Search
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search contacts…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),

              // List
              Expanded(
                child: Stack(
                  children: [
                    if (_loading || prov.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (items.isEmpty)
                      Center(
                        child: Text(
                          prov.error != null
                              ? 'Failed to load contacts:\n${prov.error}'
                              : 'No contacts yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subtle),
                        ),
                      )
                    else
                      ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = items[i];
                          final user =
                              (c['user'] ?? {}) as Map<String, dynamic>;
                          final userId = (user['id'] ?? '').toString();
                          final name = nameResolver.forUserId(
                            userId,
                            fallback:
                                (user['fullName'] ?? user['username'] ?? userId)
                                    .toString(),
                          );
                          final initials = nameResolver.initialsFor(userId);

                          final checked = _selectedUserIds.contains(userId);
                          return ListTile(
                            leading: CircleAvatar(child: Text(initials)),
                            title: Text(name),
                            subtitle: _subtitleForUser(user, subtle),
                            trailing: Checkbox(
                              value: checked,
                              onChanged: (_) {
                                setState(() {
                                  if (checked) {
                                    _selectedUserIds.remove(userId);
                                  } else {
                                    _selectedUserIds.add(userId);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              setState(() {
                                if (checked) {
                                  _selectedUserIds.remove(userId);
                                } else {
                                  _selectedUserIds.add(userId);
                                }
                              });
                            },
                          );
                        },
                      ),

                    // pull-to-refresh affordance
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: 'Refresh contacts',
                        icon: const Icon(Icons.refresh),
                        onPressed: _loading
                            ? null
                            : () async {
                                setState(() => _loading = true);
                                try {
                                  await context
                                      .read<ContactsProvider>()
                                      .refresh();
                                } finally {
                                  if (mounted) {
                                    setState(() => _loading = false);
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Manual entry
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Or type emails/phones (comma-separated)',
                  style: TextStyle(fontSize: 12, color: subtle),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _manual,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'friend@example.com, +3538XXXXXXX',
                ),
              ),

              const SizedBox(height: 12),

              // Buttons
              Row(
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subtitleForUser(Map<String, dynamic> user, Color subtle) {
    final userName = (user['username'] ?? '').toString();
    final email = (user['email'] ?? '').toString();
    final phone = (user['phone'] ?? '').toString();
    final bits = [
      if (userName.isNotEmpty) '@$userName',
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Text(
      bits.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: subtle),
    );
  }
}
