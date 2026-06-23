import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/auth/services/auth_service.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _authService = AuthService();
  final _storage = const FlutterSecureStorage();

  static const _infoSeenCountKey = 'info_seen_count';
  static const _maxInfoViews = 2;

  @override
  void initState() {
    super.initState();
    _decideStartRoute();
  }

  Future<void> _decideStartRoute() async {
    final isLoggedIn = await _authService.tryRestoreSession();

    if (!mounted) return;

    if (isLoggedIn) {
      context.go('/locations');
      return;
    }

    final rawCount = await _storage.read(key: _infoSeenCountKey);
    final seenCount = int.tryParse(rawCount ?? '0') ?? 0;

    if (!mounted) return;

    if (seenCount < _maxInfoViews) {
      context.go('/info');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
