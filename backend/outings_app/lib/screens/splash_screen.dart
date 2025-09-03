import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    _simulateAuthCheck();
  }

  Future<void> _simulateAuthCheck() async {
    await Future.delayed(const Duration(seconds: 2));

    // Simulated auth check
    bool isLoggedIn = false; // Change this to true to test auto-login

    if (isLoggedIn) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Loading Outings with Friends...',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
