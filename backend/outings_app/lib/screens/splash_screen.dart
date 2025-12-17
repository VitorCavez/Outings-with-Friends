// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Auth state
import 'package:outings_app/features/auth/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _maybeNavigate(AuthProvider auth) {
    if (!mounted || _navigated) return;
    if (!auth.isInitialized) return; // still reading SharedPreferences

    _navigated = true;

    // Decide target: logged-in users go straight into the app, others to login.
    final target = auth.isLoggedIn ? '/home' : '/login';
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitialized && !_navigated) {
          // Schedule navigation after this frame to avoid calling go() in build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _maybeNavigate(auth);
          });
        }

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
      },
    );
  }
}
