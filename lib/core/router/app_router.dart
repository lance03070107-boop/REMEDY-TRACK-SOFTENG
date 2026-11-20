import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_logger.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../../views/splash/splash_view.dart';
import '../../views/alarm/alarm_ringing_screen.dart';
import '../../views/onboarding/onboarding_view.dart';
import '../../views/auth/login_view.dart';
import '../../views/auth/register_view.dart';
import '../../views/auth/verify_otp_view.dart';
import '../../views/auth/forgot_password_view.dart';
import '../../views/home/dashboard_view.dart';
import '../../views/medications/medication_list_view.dart';
import '../../views/medications/add_edit_medication_view.dart';
import '../../views/schedule/schedule_view.dart';
import '../../views/reports/insights_view.dart';
import '../../views/profile/caregiver_view.dart';
import '../../views/settings/settings_view.dart';
import '../../views/settings/global_alarm_sound_manager_view.dart';
import '../../views/settings/default_alarm_tone_view.dart';
import '../../views/settings/reliability_check_view.dart';
import '../../views/inventory/inventory_manager_view.dart';
import '../../views/widgets/main_navigation_shell.dart';

/// Centralized go_router configuration for RemedyTrack.
/// Implements session guards and redirect rules driven by AuthViewModel.
class AppRouter {
  const AppRouter._();

  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>();

  static GoRouter? _routerInstance;

  /// Callback invoked when [AlarmRingingScreen] is dismissed so queued simultaneous
  /// medication alarms can be presented sequentially without overriding each other.
  static VoidCallback? onAlarmScreenDismissed;

  /// Returns whether the full-screen alarm ringing screen is currently presenting.
  static bool get isAlarmRingingActive {
    if (_routerInstance == null) return false;
    try {
      final path =
          _routerInstance!.routerDelegate.currentConfiguration.uri.path;
      return path.startsWith('/alarm-ring');
    } catch (e, s) {
      AppLogger.w('Failed to read router alarm path: $e',
          tag: 'AppRouter', error: e, stackTrace: s);
      return false;
    }
  }

  /// Returns or creates the singleton GoRouter wired to AuthViewModel's lifecycle.
  static GoRouter getRouter(AuthViewModel authViewModel) {
    if (_routerInstance != null) {
      return _routerInstance!;
    }

    _routerInstance = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/splash',
      refreshListenable: authViewModel,
      redirect: (BuildContext context, GoRouterState state) {
        final bool isAuth = authViewModel.isAuthenticated;
        final String loc = state.uri.path;

        // Allow cold start splash (including web root '/'), onboarding, and waking alarm screen
        if (loc == '/' ||
            loc == '/splash' ||
            loc == '/onboarding' ||
            loc.startsWith('/alarm-ring')) {
          return null;
        }

        // Wait for auth initialization and profile loading before deciding on redirects
        if (authViewModel.isInitializing || authViewModel.isProfileLoading) {
          return null;
        }

        final bool isPublicAuthRoute =
            loc == '/login' || loc == '/register' || loc == '/forgot-password';

        // 1. Guard protected routes against unauthenticated users
        if (!isAuth) {
          if (!isPublicAuthRoute) {
            // Preserve the attempted destination in query params
            final String target = state.uri.toString();
            final String encoded = Uri.encodeComponent(target);
            return '/login?from=$encoded';
          }
          return null;
        }

        // 2. Authenticated user: check email OTP verification status
        final bool isVerified = authViewModel.isEmailOtpVerified;
        if (!isVerified) {
          // If unverified, only allow the OTP verification screen
          if (loc != '/verify-otp') {
            return '/verify-otp?purpose=signup';
          }
          return null;
        }

        // 3. Authenticated & verified user: cannot visit login, register, forgot-password, or signup OTP
        if (isPublicAuthRoute ||
            (loc == '/verify-otp' &&
                state.uri.queryParameters['purpose'] != 'reauth')) {
          final String? from = state.uri.queryParameters['from'];
          if (from != null && from.isNotEmpty) {
            final String decoded = Uri.decodeComponent(from);
            if (decoded.startsWith('/') &&
                decoded != '/login' &&
                decoded != '/register' &&
                decoded != '/forgot-password') {
              return decoded;
            }
          }
          return '/home';
        }

        return null;
      },
      errorBuilder: (context, state) {
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Page Not Found',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${state.error}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Return to Dashboard'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      routes: [
        GoRoute(
          path: '/',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const SplashView(),
        ),
        GoRoute(
          path: '/splash',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const SplashView(),
        ),
        GoRoute(
          path: '/onboarding',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const OnboardingView(),
        ),
        GoRoute(
          path: '/login',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const LoginView(),
        ),
        GoRoute(
          path: '/register',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const RegisterView(),
        ),
        GoRoute(
          path: '/verify-otp',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final purpose = state.uri.queryParameters['purpose'] ?? 'signup';
            final email = state.uri.queryParameters['email'];
            return VerifyOtpView(purpose: purpose, email: email);
          },
        ),
        GoRoute(
          path: '/forgot-password',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ForgotPasswordView(),
        ),
        GoRoute(
          path: '/alarm-ring',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final medId = state.uri.queryParameters['medId'] ?? '';
            final userId = state.uri.queryParameters['userId'] ?? '';
            final notifId =
                int.tryParse(state.uri.queryParameters['notifId'] ?? '0') ?? 0;
            final schedTimeStr = state.uri.queryParameters['schedTime'] ?? '';
            final schedTime = DateTime.tryParse(schedTimeStr) ?? DateTime.now();
            final medName =
                state.uri.queryParameters['medName'] ?? 'Medication';
            final strength = state.uri.queryParameters['strength'] ?? '';
            final doseAmount = double.tryParse(
                    state.uri.queryParameters['doseAmount'] ?? '1.0') ??
                1.0;
            final formName = state.uri.queryParameters['formName'] ?? 'tablet';
            final colorTag = int.tryParse(
                    state.uri.queryParameters['colorTag'] ?? '0xFF1E66F5') ??
                0xFF1E66F5;
            final instructions = state.uri.queryParameters['instructions'] ??
                'Take as prescribed with water.';
            final soundId = state.uri.queryParameters['soundId'];
            final customPath = state.uri.queryParameters['customPath'];
            final snoozeCount =
                int.tryParse(state.uri.queryParameters['snoozeCount'] ?? '0') ??
                    0;

            return AlarmRingingScreen(
              medicationId: medId,
              userId: userId,
              notificationId: notifId,
              scheduledTime: schedTime,
              medicationName: medName,
              strength: strength,
              doseAmount: doseAmount,
              formName: formName,
              colorTag: colorTag,
              instructions: instructions,
              soundId: soundId,
              customSoundPath: customPath,
              initialSnoozeCount: snoozeCount,
            );
          },
        ),
        GoRoute(
          path: '/alarm-ringing',
          parentNavigatorKey: rootNavigatorKey,
          redirect: (context, state) => '/alarm-ring?${state.uri.query}',
        ),
        GoRoute(
          path: '/today',
          parentNavigatorKey: rootNavigatorKey,
          redirect: (context, state) => '/home',
        ),
        // Adaptive Shell Route wrapping the 4 core tabs
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => MainNavigationShell(
            currentLocation: state.uri.toString(),
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const DashboardView(),
            ),
            GoRoute(
              path: '/today',
              redirect: (context, state) => '/home',
            ),
            GoRoute(
              path: '/medications',
              builder: (context, state) => const MedicationListView(),
            ),
            GoRoute(
              path: '/insights',
              builder: (context, state) {
                final tabParam = state.uri.queryParameters['tab'];
                final initialIndex = tabParam == 'history' ? 1 : 0;
                return InsightsView(initialTabIndex: initialIndex);
              },
            ),
            GoRoute(
              path: '/history',
              redirect: (context, state) => '/insights?tab=history',
            ),
            GoRoute(
              path: '/inventory',
              builder: (context, state) => const InventoryManagerView(),
            ),
            GoRoute(
              path: '/reports',
              redirect: (context, state) => '/insights',
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsView(),
            ),
          ],
        ),
        // Fullscreen routes on top of navigation shell
        GoRoute(
          path: '/medications/add',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const AddEditMedicationView(),
        ),
        GoRoute(
          path: '/medications/edit/:id',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            return AddEditMedicationView(medicationId: id);
          },
        ),
        GoRoute(
          path: '/schedule',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ScheduleView(),
        ),
        GoRoute(
          path: '/caregiver',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const CaregiverView(),
        ),
        GoRoute(
          path: '/settings/reliability',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ReliabilityCheckView(),
        ),
        GoRoute(
          path: '/settings/alarm-sounds',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const GlobalAlarmSoundManagerView(),
        ),
        GoRoute(
          path: '/settings/alarm-sounds/default-tone',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const DefaultAlarmToneView(),
        ),
        GoRoute(
          path: '/settings/evaluation',
          parentNavigatorKey: rootNavigatorKey,
          redirect: (context, state) => '/settings/reliability',
        ),
      ],
    );

    return _routerInstance!;
  }

  /// For testing or resets: allows clearing the singleton router instance
  @visibleForTesting
  static void resetRouter() {
    _routerInstance = null;
  }
}
