// lib/screens/messages/contacts_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/contacts_provider.dart';

class ContactsListScreen extends StatefulWidget {
  const ContactsListScreen({super.key});

  @override
  State<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends State<ContactsListScreen> {
  final _phoneCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactsProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddDialog() async {
    _phoneCtrl.clear();
    _labelCtrl.clear();
    final prov = context.read<ContactsProvider>();

    await showDialog(
      context: context,
      builder: (ctx) {
        final formKey = GlobalKey<FormState>();

        return AlertDialog(
          title: const Text('Add contact by phone'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: 'e.g. 087 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final phone = _phoneCtrl.text.trim();
                final label = _labelCtrl.text.trim().isEmpty
                    ? null
                    : _labelCtrl.text.trim();

                // This returns true/false (provider sets prov.error on failure).
                final ok = await prov.addByPhone(phone, label: label);

                if (!context.mounted) return;

                if (ok) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact added')),
                  );
                } else {
                  final msg = prov.error ?? 'Failed to add contact';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRemove(String userId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('This will remove “$name” from your contacts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<ContactsProvider>().remove(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Removed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ContactsProvider>();
    final dividerColor = Theme.of(context).dividerColor.withOpacity(.20);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prov.loading) const LinearProgressIndicator(),
        if (prov.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Error: ${prov.error}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (!prov.loading && prov.contacts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 32, 12, 8),
            child: Row(
              children: const [
                Icon(Icons.person_search_outlined, size: 20),
                SizedBox(width: 8),
                Text('No contacts yet'),
              ],
            ),
          ),
      ],
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: prov.refresh,
        child: prov.contacts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [header],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: prov.contacts.length + 1, // + header
                separatorBuilder: (_, i) => i == 0
                    ? const SizedBox.shrink()
                    : Divider(color: dividerColor, height: 1),
                itemBuilder: (ctx, index) {
                  if (index == 0) return header;

                  final c = prov.contacts[index - 1];
                  final u = c['user'] as Map<String, dynamic>? ?? {};
                  final userId = (u['id'] ?? '') as String;
                  final fullName = (u['fullName'] ?? 'Unknown') as String;
                  final photo = (u['profilePhotoUrl'] ?? '') as String;
                  final label = (c['label'] ?? '') as String;

                  String initialsFrom(String name) {
                    final parts = name.trim().split(RegExp(r'\s+'));
                    if (parts.isEmpty || parts.first.isEmpty) return '?';
                    if (parts.length >= 2) {
                      return (parts.first[0] + parts.last[0]).toUpperCase();
                    }
                    return parts.first[0].toUpperCase();
                  }

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: (photo.isNotEmpty)
                          ? NetworkImage(photo)
                          : null,
                      child: (photo.isEmpty)
                          ? Text(initialsFrom(fullName))
                          : null,
                    ),
                    title: Text(fullName),
                    subtitle: label.isNotEmpty ? Text(label) : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Start DM',
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () {
                            if (userId.isEmpty) return;
                            context.go('/messages/chat/$userId');
                          },
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmRemove(userId, fullName),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (userId.isEmpty) return;
                      context.go('/messages/chat/$userId');
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
    );
  }
}
