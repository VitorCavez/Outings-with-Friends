// lib/features/settings/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../config/app_config.dart';
import '../../features/auth/auth_provider.dart';
import '../../services/push_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '…';

  // ---- Discover keys (match discover_screen.dart) ----
  static const _kViewKey = 'discover.view';
  static const _kCenterLatKey = 'discover.centerLat';
  static const _kCenterLngKey = 'discover.centerLng';
  static const _kZoomKey = 'discover.zoom';
  static const _kRadiusKmKey = 'discover.radiusKm';
  static const _kTypesCsvKey = 'discover.typesCsv';
  static const _kCacheFeatured = 'discover.cache.featured';
  static const _kCacheSuggested = 'discover.cache.suggested';
  static const _kCacheTs = 'discover.cache.ts';

  // ---- Push keys ----
  static const _kPushOptIn = 'push.optIn';

  bool _pushOptIn = false;
  bool _pushLoading = false;
  String _pushStatus = '…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadPushPrefsAndStatus();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'Unknown');
    }
  }

  // ---------- Push helpers ----------
  Future<void> _loadPushPrefsAndStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final optIn = prefs.getBool(_kPushOptIn) ?? false;

    // Read current OS permission status for display
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final statusLabel = switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => 'Authorized',
      AuthorizationStatus.provisional => 'Provisional',
      AuthorizationStatus.denied => 'Denied',
      AuthorizationStatus.notDetermined => 'Not determined',
      _ => settings.authorizationStatus.toString(),
    };

    if (!mounted) return;
    setState(() {
      _pushOptIn = optIn;
      _pushStatus = statusLabel;
    });
  }

  String? _currentUserId() {
    final auth = context.read<AuthProvider?>();
    return auth?.currentUserId;
  }

  Future<void> _setPushOptIn(bool value) async {
    if (!mounted) return;
    setState(() => _pushLoading = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPushOptIn, value);

    try {
      if (value) {
        // Ask with a lightweight rationale
        final allowed = await PushService.I.ensurePermission(
          context: context,
          showRationale: (ctx) async {
            return await showDialog<bool>(
                  context: ctx,
                  builder: (_) => AlertDialog(
                    title: const Text('Enable notifications?'),
                    content: const Text(
                      'We’ll notify you about invites, replies, and reminders—no spam.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Not now'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
        );

        if (allowed) {
          // Make sure foreground handlers are in place (idempotent)
          await PushService.I.initForegroundHandlers();

          final uid = _currentUserId();
          if (uid != null) {
            await PushService.I.syncToken(uid);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifications enabled')),
            );
          }
        } else {
          // User declined → flip switch back off and persist
          await prefs.setBool(_kPushOptIn, false);
          if (mounted) {
            setState(() => _pushOptIn = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Permission denied')));
          }
        }
      } else {
        // Opting out: delete token locally + unregister server-side
        final uid = _currentUserId();

        try {
          final token = await FirebaseMessaging.instance.getToken();
          // Best-effort server cleanup
          if (uid != null) {
            await PushService.unregisterToken(userId: uid);
          }
          // Remove local token so we stop receiving until re-enabled
          if (token != null) {
            await FirebaseMessaging.instance.deleteToken();
          }
        } catch (_) {
          // Non-fatal
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications disabled')),
          );
        }
      }
    } finally {
      // Refresh visible permission label
      await _loadPushPrefsAndStatus();
      if (mounted) setState(() => _pushLoading = false);
    }
  }

  // ---------- Discover actions ----------
  Future<void> _resetDiscoverFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRadiusKmKey);
    await prefs.remove(_kTypesCsvKey);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Discover filters reset')));
  }

  Future<void> _clearDiscoverCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCacheFeatured);
    await prefs.remove(_kCacheSuggested);
    await prefs.remove(_kCacheTs);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Discover cache cleared')));
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'Outings',
      applicationVersion: _version == '…' ? null : _version,
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = const Divider(height: 1);
    final pushGloballyDisabled = !AppConfig.pushEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // --- Notifications ---
          const _SectionHeader(title: 'Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Push notifications'),
            subtitle: Text(
              pushGloballyDisabled
                  ? 'Disabled by app configuration'
                  : 'Status: $_pushStatus',
            ),
            value: _pushOptIn,
            onChanged: (pushGloballyDisabled || _pushLoading)
                ? null
                : (v) => _setPushOptIn(v),
          ),
          if (_pushLoading)
            const Padding(
              padding: EdgeInsets.only(left: 72, right: 16, bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          divider,

          // --- Discover ---
          const _SectionHeader(title: 'Discover'),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Reset filters'),
            subtitle: const Text('Radius and types'),
            onTap: _resetDiscoverFilters,
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear cached results'),
            subtitle: const Text('Featured and suggested lists'),
            onTap: _clearDiscoverCache,
          ),
          divider,

          // --- About ---
          const _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_version),
            onTap: _loadVersion,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open source licenses'),
            onTap: _showLicenses,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: labelStyle?.copyWith(letterSpacing: 0.8, color: Colors.black54),
      ),
    );
  }
}
