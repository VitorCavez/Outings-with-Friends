// lib/features/outings/outings_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../config/app_config.dart';
import '../auth/auth_provider.dart';
import 'models/outing.dart';
import 'outings_repository.dart';
import 'outings_store.dart';

class OutingsListScreen extends StatelessWidget {
  const OutingsListScreen({super.key});

  ApiClient _buildApi(BuildContext context) {
    String? token;
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      token = (dyn.authToken ?? dyn.token ?? dyn.accessToken ?? dyn.jwt) as String?;
    } catch (_) {}
    return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final repo = OutingsRepository(_buildApi(context));
        final store = OutingsStore(repo);
        // initial load
        store.refresh();
        return store;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('My Outings')),
        body: Consumer<OutingsStore>(
          builder: (_, store, __) {
            if (store.loading && store.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (store.error != null && store.items.isEmpty) {
              return Center(child: Text('Error: ${store.error}'));
            }
            if (store.items.isEmpty) {
              return const Center(child: Text('No outings yet.'));
            }

            return RefreshIndicator(
              onRefresh: store.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemBuilder: (_, i) => _OutingTile(item: store.items[i]),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: store.items.length,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OutingTile extends StatelessWidget {
  const _OutingTile({required this.item});
  final Outing item;

  @override
  Widget build(BuildContext context) {
    final when = item.startsAt != null ? '${item.startsAt}' : 'TBD';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          // Navigate to details (allowed even if local-only, to show syncing banner there)
          context.go('/outings/${item.id}');
        },
        leading: const CircleAvatar(
          child: Icon(Icons.event),
        ),
        title: Row(
          children: [
            Expanded(child: Text(item.title)),
            if (item.isLocalOnly)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.sync, size: 16),
                  label: const Text('Syncing'),
                  side: BorderSide.none,
                ),
              ),
          ],
        ),
        subtitle: Text('${item.location ?? 'No location'} • $when'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
