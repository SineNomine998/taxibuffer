import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/auth/screens/login_screen.dart';
import 'package:mobile_app/features/info/screens/info_screen.dart';

final GoRouter router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const InfoScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  ],
);
