// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Read current auth state safely (works with your dynamic fields pattern)
import 'package:outings_app/features/auth/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..forward();

  @override
  void initState() {
    super.initState();
    // Kick off the auth check on the next microtask so build() can run first
    Future.microtask(_routeFromAuth);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _routeFromAuth() async {
    // Optional: ensure the splash is visible briefly for UX
    const minSplash = Duration(milliseconds: 600);
    final started = DateTime.now();

    final isLoggedIn = _isLoggedInFromContext();

    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    if (!mounted) return;
    context.go(isLoggedIn ? '/home' : '/login');
  }

  bool _isLoggedInFromContext() {
    try {
      final auth = context.read<AuthProvider?>();
      final dyn = auth as dynamic;

      final uid = dyn?.currentUserId;
      final token =
          (dyn?.authToken ?? dyn?.token ?? dyn?.accessToken ?? dyn?.jwt)
              as String?;
      final hasUid = uid != null && uid.toString().isNotEmpty;
      final hasToken = (token ?? '').isNotEmpty;

      return hasUid || hasToken;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: FadeTransition(
          opacity: _fadeCtrl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Simple brand mark
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.people_alt_rounded,
                  color: cs.onPrimaryContainer,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Outings with Friends',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
