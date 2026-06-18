import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/auth/login/screens/login_screen.dart';
import 'package:mobile_app/features/info/screens/info_screen.dart';
import '../features/auth/signup/signup_form_state.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step1_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step2_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step3_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/vehicle_add_screen.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const InfoScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    ShellRoute(
      builder:(context, state, child) {
        return ChangeNotifierProvider(
          create: (context) => SignupFormState(),
          child: child,
        );
      },
      routes: [
        GoRoute(path: '/signup', builder: (_, _) => const SignupStep1Screen()),
        GoRoute(path: '/signup/password', builder: (_, _) => const SignupStep2Screen()),
        GoRoute(path: '/signup/vehicle', builder: (_, _) => const SignupStep3Screen()),
        GoRoute(path: '/signup/vehicle/add', builder: (_, _) => const VehicleAddScreen()),
      ],
    ),
  ],
);
