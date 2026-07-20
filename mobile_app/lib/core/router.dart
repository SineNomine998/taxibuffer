import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_app/features/account/account_state.dart';
import 'package:mobile_app/features/account/screens/account_screen.dart';
import 'package:mobile_app/features/activity/screens/activity_screen.dart';
import 'package:mobile_app/features/auth/auth_gate_state.dart';
import 'package:mobile_app/features/auth/login/screens/login_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_screen.dart';
import 'package:mobile_app/features/auth/password_reset/screens/password_reset_sent_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step1_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step2_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/signup_step3_screen.dart';
import 'package:mobile_app/features/auth/signup/screens/vehicle_add_screen.dart';
import 'package:mobile_app/features/auth/signup/signup_form_state.dart';
import 'package:mobile_app/features/compliance/terms_of_use/screens/terms_of_use_preview_screen.dart';
import 'package:mobile_app/features/compliance/terms_of_use/screens/terms_of_use_screen.dart';
import 'package:mobile_app/features/compliance/terms_of_use/terms_gate_state.dart';
import 'package:mobile_app/features/info/screens/info_screen.dart';
import 'package:mobile_app/features/info/screens/startup_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_info_screen.dart';
import 'package:mobile_app/features/location/screens/location_selection_screen.dart';
import 'package:mobile_app/features/compliance/privacy/privacy_gate_state.dart';
import 'package:mobile_app/features/compliance/privacy/screens/privacy_policy_preview_screen.dart';
import 'package:mobile_app/features/compliance/privacy/screens/privacy_policy_screen.dart';
import 'package:mobile_app/features/queue/queue_state.dart';
import 'package:mobile_app/features/queue/screens/queue_status_screen.dart';
import 'package:mobile_app/features/sequence/screens/sequence_history_screen.dart';
import 'package:mobile_app/features/settings/screens/settings_screen.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: Listenable.merge([
    authGateState,
    privacyGateState,
    termsGateState,
  ]),
  redirect: (context, state) {
    final auth = authGateState;
    final privacy = privacyGateState;
    final terms = termsGateState;

    final location = state.uri.toString();
    final path = state.uri.path;

    final authFreePaths = <String>{
      '/',
      '/info',
      '/login',
      '/password-reset',
      '/password-reset/sent',
      '/signup',
      '/signup/password',
      '/signup/vehicle',
      '/signup/vehicle/add',
      '/privacy-preview',
      '/terms-preview',
    };

    final compliancePaths = <String>{'/privacy', '/terms'};

    final isAuthFreePath =
        authFreePaths.contains(path) || path.startsWith('/signup');
    final isCompliancePath = compliancePaths.contains(path);

    if (auth.status == AuthGateStatus.unknown) {
      auth.check();
      return null;
    }

    if (auth.status == AuthGateStatus.checking) {
      return null;
    }

    if (auth.status == AuthGateStatus.unauthenticated) {
      if (isAuthFreePath) return null;

      final next = Uri.encodeComponent(location);
      return '/login?next=$next';
    }

    // TODO: Let LoginScreen decide where to go after login
    // // User is authenticated. Do not let authenticated users sit on login/signup.
    // if (auth.status == AuthGateStatus.authenticated) {
    //   final onAuthScreen = path == '/login' || path.startsWith('/signup');

    //   if (onAuthScreen &&
    //       privacy.status == PrivacyGateStatus.accepted &&
    //       terms.status == TermsGateStatus.accepted) {
    //     return '/locations';
    //   }
    // }

    // Allow privacy/terms screens so user can accept.
    if (isCompliancePath) {
      return null;
    }

    // Public non-auth app screens can continue.
    if (isAuthFreePath) {
      return null;
    }

    if (privacy.status == PrivacyGateStatus.unknown) {
      privacy.check();
      return null;
    }

    if (privacy.status == PrivacyGateStatus.checking) {
      return null;
    }

    if (privacy.status == PrivacyGateStatus.required ||
        privacy.status == PrivacyGateStatus.error) {
      final next = Uri.encodeComponent(location);
      return '/privacy?next=$next';
    }

    if (terms.status == TermsGateStatus.unknown) {
      terms.check();
      return null;
    }

    if (terms.status == TermsGateStatus.checking) {
      return null;
    }

    if (terms.status == TermsGateStatus.required ||
        terms.status == TermsGateStatus.error) {
      final next = Uri.encodeComponent(location);
      return '/terms?next=$next';
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
        GoRoute(
          path: '/terms-preview',
          builder: (_, _) => const TermsOfUsePreviewScreen(),
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

    GoRoute(
      path: '/terms',
      builder: (context, state) {
        final next = state.uri.queryParameters['next'];
        return TermsOfUseScreen(next: next);
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
          path: '/account/settings',
          builder: (_, _) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/settings/activity',
          builder: (_, _) => const ActivityScreen(),
        ),
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
