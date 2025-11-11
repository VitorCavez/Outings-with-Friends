// lib/deeplink/deeplink_handler.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';

/// DeepLinkHandler using `app_links`.
/// Handles links like:
/// - https://yourdomain.tld/outings/<id>
/// - myapp://outings/<id>
class DeepLinkHandler {
  StreamSubscription<Uri>? _sub;
  AppLinks? _appLinks;

  Future<void> start(BuildContext context) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    _appLinks ??= AppLinks();

    // Handle initial link (cold start via link)
    try {
      final initialUri = await _appLinks!.getInitialLink();
      if (initialUri != null) {
        _routeIncomingUri(context, initialUri);
      }
    } catch (_) {
      // ignore errors reading initial link
    }

    // Handle subsequent links while app is running
    _sub?.cancel();
    _sub = _appLinks!.uriLinkStream.listen(
      (uri) {
        if (uri != null) _routeIncomingUri(context, uri);
      },
      onError: (_) {
        // ignore stream errors
      },
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _routeIncomingUri(BuildContext context, Uri uri) {
    // e.g. https://yourdomain/outings/123  OR  myapp://outings/123
    final path = uri.path; // e.g. /outings/123

    if (path.startsWith('/outings/')) {
      final id = path.split('/').last;
      // Route into the app (adjust if your GoRouter layout changes)
      context.go('/outings/$id');
      return;
    }

    // Add more patterns here as needed (e.g., /messages/chat/:peerId)
  }
}
