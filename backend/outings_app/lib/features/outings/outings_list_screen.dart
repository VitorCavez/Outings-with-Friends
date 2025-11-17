import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';
import '../../config/app_config.dart';
import '../auth/auth_provider.dart';
import 'models/outing.dart';
import 'outings_repository.dart';
import 'outings_store.dart';
import '../../theme/app_theme.dart'; // for BrandColors extension

class OutingsListScreen extends StatelessWidget {
  const OutingsListScreen({super.key});

  ApiClient _buildApi(BuildContext context) {
    String? token;
    try {
      final auth = context.read<AuthProvider>();
      final dyn = auth as dynamic;
      token = (dyn.authToken ?? dyn.token) as String?;
    } catch (_) {}
    return ApiClient(baseUrl: AppConfig.apiBaseUrl, authToken: token);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Error: ${store.error}',
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              );
            }

            if (store.items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 140),
                  Icon(Icons.event_busy, size: 56, color: cs.outline),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No outings yet.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }

            return RefreshIndicator(
              onRefresh: store.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemBuilder: (_, i) => _OutingTile(item: store.items[i]),
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: cs.outlineVariant),
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

  String _formatWhen(DateTime? dt) {
    if (dt == null) return 'TBD';
    final local = dt.toLocal();
    final d = DateFormat('EEE, d MMM • HH:mm').format(local);
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = Theme.of(context).extension<BrandColors>();
    final when = _formatWhen(item.startsAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surface,
      surfaceTintColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () async {
          final changed = await context.push<bool>('/outings/${item.id}');
          if (changed == true) {
            // 🔄 refresh backing store when returning (e.g., after delete/edit)
            final store = context.read<OutingsStore>();
            await store.refresh();
          }
        },
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.event, color: cs.onPrimaryContainer),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isLocalOnly)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.sync,
                    size: 16,
                    color: cs.onSecondaryContainer,
                  ),
                  label: const Text('Syncing'),
                  side: BorderSide.none,
                  backgroundColor: (brand != null)
                      ? (brand.info.withOpacity(0.12))
                      : cs.secondaryContainer,
                  labelStyle: TextStyle(
                    color: (brand != null)
                        ? brand.info
                        : cs.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${item.location ?? 'No location'} • $when',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.outline),
      ),
    );
  }
}
