// lib/config/app_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, debugPrint;

class AppConfig {
  // ── Build-time env (set with --dart-define=KEY=value) ────────────────────────

  /// Full base URL to your API *host* (NO trailing slash, NO `/api`).
  /// Example: https://api.example.com
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Public share domain used in deep links: https://<domain>/plan/outings/:id
  static const String _envShareBaseUrl = String.fromEnvironment(
    'SHARE_BASE_URL',
  );

  /// Optional: OpenCage geocoding API key (kept for your project)
  static const String _envOpenCageApiKey = String.fromEnvironment(
    'OPENCAGE_API_KEY',
  );

  /// Toggle FCM push (kept off by default until ready).
  static const bool pushEnabled = bool.fromEnvironment(
    'PUSH_ENABLED',
    defaultValue: false,
  );

  /// If you truly must ship with a non-prod API (localhost/http),
  /// set this to true: --dart-define=ALLOW_INSECURE_API_IN_RELEASE=true
  static const bool _allowInsecureApiInRelease = bool.fromEnvironment(
    'ALLOW_INSECURE_API_IN_RELEASE',
    defaultValue: false,
  );

  // ── URL helpers ─────────────────────────────────────────────────────────────

  /// Returns a sanitized host base URL (no trailing slash, no `/api`).
  static String get _hostBase {
    final isAndroid = !kIsWeb && Platform.isAndroid;

    if (_envApiBaseUrl.isNotEmpty) {
      var v = _envApiBaseUrl.trim();

      // Drop trailing slashes.
      v = v.replaceAll(RegExp(r'/+$'), '');

      // Strip accidental `/api` suffix (clients add /api themselves).
      v = v.replaceFirst(RegExp(r'/api/?$'), '');

      // If someone gave the Android emulator IP but we're NOT on Android, rewrite to loopback
      if (!isAndroid && v.contains('10.0.2.2')) {
        v = v.replaceAll('10.0.2.2', '127.0.0.1');
      }

      return v;
    }

    // If nothing was provided:
    if (kReleaseMode) {
      // In release, require an explicit host.
      throw StateError(
        'API_BASE_URL is not set for release builds. '
        'Pass --dart-define=API_BASE_URL=https://outings-with-friends-api.onrender.com',
      );
    }

    // Sensible dev defaults
    if (kIsWeb) return 'http://127.0.0.1:3000';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
  }

  /// Host base (no `/api`).
  static String get apiBaseUrl => _hostBase;

  /// Socket.IO origin (no `/api`).
  static String get socketBaseUrl => _hostBase;

  /// Helper to prefix `/api` exactly once when building paths.
  /// Usage: final url = '${AppConfig.apiBaseUrl}${AppConfig.api('/contacts')}';
  static String api(String path) {
    final clean = path.startsWith('/') ? path : '/$path';
    return clean.startsWith('/api/') ? clean : '/api$clean';
  }

  // ── Misc config ─────────────────────────────────────────────────────────────

  static Map<String, String> get defaultHeaders => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static String get openCageApiKey => _envOpenCageApiKey.isNotEmpty
      ? _envOpenCageApiKey
      : 'a45f3a3cc22f4991852a5064e1703fd9';

  /// Where shared links should point (web deep-link domain).
  static String get shareBaseUrl => _envShareBaseUrl.isNotEmpty
      ? _envShareBaseUrl
      : 'https://outings-with-friends.web.app';

  // ── Guards / Diagnostics ────────────────────────────────────────────────────

  static bool _looksLocalHost(String host) {
    final h = host.toLowerCase();
    return h.contains('127.0.0.1') ||
        h.contains('localhost') ||
        h.contains('10.0.2.2') ||
        RegExp(r'^http://\d+\.\d+\.\d+\.\d+').hasMatch(h);
  }

  static bool _looksRender(String host) {
    return host.toLowerCase().contains('onrender.com');
  }

  static bool _looksInsecure(String host) {
    // Allow http during debug/dev, but flag it as insecure in release.
    return host.toLowerCase().startsWith('http://');
  }

  /// Call this once at startup to validate the host and print diagnostics.
  static void sanityCheck() {
    final host = apiBaseUrl;

    // Always print what we resolved to (helps with support logs).
    debugPrint('🌐 API host: $host');

    // Only truly unsafe things should block release builds.
    final isReallyBad = _looksLocalHost(host) || _looksInsecure(host);

    if (!kReleaseMode) {
      if (_looksLocalHost(host)) {
        debugPrint('⚠️  Using a local API host (ok for development).');
      }
      if (_looksRender(host)) {
        debugPrint(
          'ℹ️  API host is on Render (paid plan recommended to avoid cold starts).',
        );
      }
      if (_looksInsecure(host)) {
        debugPrint('⚠️  API is over http://. Use https:// for production.');
      }
      return;
    }

    if (isReallyBad && !_allowInsecureApiInRelease) {
      throw StateError(
        'Invalid API_BASE_URL for release: "$host". '
        'Use a public https host (not localhost/10.0.2.2 or http://). '
        'If you intentionally accept this, pass '
        '--dart-define=ALLOW_INSECURE_API_IN_RELEASE=true (NOT RECOMMENDED).',
      );
    }

    // Render hosts are allowed in release — we only warn above.
  }
}
