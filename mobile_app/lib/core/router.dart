import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/account/account_state.dart';
import 'package:mobile_app/features/account/screens/account_screen.dart';
import 'package:mobile_app/features/auth/login/screens/login_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_sent_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step1_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step2_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step3_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/vehicle_add_screen.dart';
import 'package:mobile_app/features/auth/signup/signup_form_state.dart';
import 'package:mobile_app/features/info/screens/info_screen.dart';
import 'package:mobile_app/features/info/screens/startup_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_info_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_screen.dart';
import 'package:mobile_app/features/privacy/privacy_gate_state.dart';
import 'package:mobile_app/features/privacy/screens/privacy_policy_preview_screen.dart';
import 'package:mobile_app/features/privacy/screens/privacy_policy_screen.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:mobile_app/features/queue/screens/queue_status_screen.dart';
import 'package:mobile_app/features/sequence/screens/sequence_history_screen.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: privacyGateState,
  redirect: (context, state) {
    final privacy = privacyGateState;
    final location = state.uri.toString();
    final path = state.uri.path;

    final publicPaths = <String>{
      '/',
      '/info',
      '/login',
      '/password-reset',
      '/password-reset/sent',
      '/signup',
      '/signup/password',
      '/signup/vehicle',
      '/signup/vehicle/add',
      '/privacy',
      '/privacy-preview',
    };

    final isPublicPath = publicPaths.contains(path);
    final isPrivacyPath = path == '/privacy';

    // Let public onboarding/auth screens work without privacy acceptance.
    // Exception: if the user tries to leave privacy while required, protected routes below will redirect back.
    if (path == '/' ||
        path == '/info' ||
        path == '/login' ||
        path == '/password-reset' ||
        path == '/password-reset/sent' ||
        path.startsWith('/signup')) {
      return null;
    }

    // Privacy screen itself is allowed, otherwise user could never accept.
    if (isPrivacyPath) {
      return null;
    }

    // For protected app screens, check privacy status.
    if (!isPublicPath) {
      if (privacy.status == PrivacyGateStatus.unknown) {
        privacy.check();
        return null;
      }

      if (privacy.status == PrivacyGateStatus.checking) {
        return null;
      }

      if (privacy.status == PrivacyGateStatus.required) {
        final next = Uri.encodeComponent(location);
        return '/privacy?next=$next';
      }

      if (privacy.status == PrivacyGateStatus.error) {
        final next = Uri.encodeComponent(location);
        return '/privacy?next=$next';
      }
    }

    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StartupScreen()),

    GoRoute(path: '/info', builder: (context, state) => const InfoScreen()),

    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    GoRoute(
      path: '/password-reset',
      builder: (_, _) => const PasswordResetScreen(),
    ),
    GoRoute(
      path: '/password-reset/sent',
      builder: (_, _) => const PasswordResetSentScreen(),
    ),

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
        GoRoute(
          path: '/privacy-preview',
          builder: (_, _) => const PrivacyPolicyPreviewScreen(),
        ),
      ],
    ),

    GoRoute(
      path: '/privacy',
      builder: (context, state) {
        final next = state.uri.queryParameters['next'];
        return PrivacyPolicyScreen(next: next);
      },
    ),

    ShellRoute(
      builder: (context, state, child) {
        return ChangeNotifierProvider(
          create: (_) => AccountState(),
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/locations',
          builder: (_, _) => const LocationSelectionScreen(),
        ),
        GoRoute(
          path: '/locations/info',
          builder: (_, _) => const LocationSelectionInfoScreen(),
        ),
        GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
        GoRoute(
          path: '/numbers',
          builder: (_, _) => const SequenceHistoryScreen(),
        ),
        GoRoute(
          path: '/queue',
          redirect: (context, state) {
            final queueState = context.read<QueueState>();
            if (queueState.isInQueue) {
              return '/queue/${queueState.activeEntryUuid}';
            }
            return null;
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
