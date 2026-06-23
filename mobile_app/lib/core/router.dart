import 'package:mobile_app/features/account/account_state.dart';
import 'package:mobile_app/features/account/screens/account_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_sent_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_info_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_screen.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:mobile_app/features/queue/screens/queue_status_screen.dart';
import 'package:mobile_app/features/sequence/screens/sequence_history_screen.dart';
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
    // Info pages routing
    GoRoute(path: '/', builder: (context, state) => const InfoScreen()),

    // Login routing
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    // Password reset routing
    GoRoute(
      path: '/password-reset',
      builder: (_, _) => const PasswordResetScreen(),
    ),
    GoRoute(
      path: '/password-reset/sent',
      builder: (_, _) => const PasswordResetSentScreen(),
    ),

    // Sign-up routing
    ShellRoute(
      builder: (context, state, child) {
        return ChangeNotifierProvider(
          create: (context) => SignupFormState(),
          child: child,
        );
      },
      routes: [
        GoRoute(path: '/signup', builder: (_, _) => const SignupStep1Screen()),
        GoRoute(
          path: '/signup/password',
          builder: (_, _) => const SignupStep2Screen(),
        ),
        GoRoute(
          path: '/signup/vehicle',
          builder: (_, _) => const SignupStep3Screen(),
        ),
        GoRoute(
          path: '/signup/vehicle/add',
          builder: (_, _) => const VehicleAddScreen(),
        ),
      ],
    ),

    // Authenticated routing inside app:
    ShellRoute(
      builder: (context, state, child) {
        return ChangeNotifierProvider(
          create: (_) => AccountState(),
          child: child,
        );
      },
      routes: [
        // Locations routing
        GoRoute(
          path: '/locations',
          builder: (_, _) => const LocationSelectionScreen(),
        ),
        GoRoute(
          path: '/locations/info',
          builder: (_, _) => const LocationSelectionInfoScreen(),
        ),

        // Account routing
        GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),

        // Sequence history routing
        GoRoute(
          path: '/numbers',
          builder: (_, _) => const SequenceHistoryScreen(),
        ),

        // Queue routing
        // /queue is the tab destination - redirects to active entry if in queue,
        // otherwise falls back to LocationSelectionScreen (no active queue).
        GoRoute(
          path: '/queue',
          redirect: (context, state) {
            final queueState = context.read<QueueState>();
            if (queueState.isInQueue) {
              return '/queue/${queueState.activeEntryUuid}';
            }
            return null; // render fallback builder below
          },
          builder: (_, _) => const LocationSelectionScreen(),
        ),
        GoRoute(
          path: '/queue/:entryUuid',
          builder: (_, state) =>
              QueueStatusScreen(entryUuid: state.pathParameters['entryUuid']!),
        ),
      ],
    ),
  ],
);
