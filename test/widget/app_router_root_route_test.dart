import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/core/router/app_router.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/onboarding/onboarding_view.dart';
import 'package:remedy_track/views/splash/splash_view.dart';

class _TestAuthViewModel extends AuthViewModel {
  bool stubIsInitializing;
  bool stubIsAuthenticated;
  bool stubIsEmailOtpVerified;

  _TestAuthViewModel({
    this.stubIsInitializing = false,
    this.stubIsAuthenticated = false,
    this.stubIsEmailOtpVerified = true,
  }) : super(userRepository: MockUserRepository());

  @override
  bool get isInitializing => stubIsInitializing;

  @override
  bool get isProfileLoading => false;

  @override
  bool get isAuthenticated => stubIsAuthenticated;

  @override
  bool get isEmailOtpVerified => stubIsEmailOtpVerified;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppRouter Web Root Route & Theme Error Fallback Tests', () {
    late SettingsViewModel settingsVm;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppRouter.resetRouter();
      settingsVm = SettingsViewModel();
    });

    tearDown(() {
      AppRouter.resetRouter();
    });

    testWidgets(
      'navigating to web root "/" renders SplashView even while auth isInitializing',
      (tester) async {
        final authVm = _TestAuthViewModel(stubIsInitializing: true);
        final router = AppRouter.getRouter(authVm);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
              ChangeNotifierProvider<SettingsViewModel>.value(
                  value: settingsVm),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: router,
            ),
          ),
        );

        router.go('/');
        await tester.pump();

        expect(find.byType(SplashView), findsOneWidget);
        expect(find.text('Page Not Found'), findsNothing);

        // Let splash settle once initialization finishes.
        authVm.stubIsInitializing = false;
        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingView), findsOneWidget);
      },
    );

    testWidgets(
      'unknown routes render theme scaffoldBackgroundColor instead of dark #1E1E2E box',
      (tester) async {
        final authVm = _TestAuthViewModel(
          stubIsInitializing: false,
          stubIsAuthenticated: true,
          stubIsEmailOtpVerified: true,
        );
        final router = AppRouter.getRouter(authVm);
        final lightTheme = AppTheme.light();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
              ChangeNotifierProvider<SettingsViewModel>.value(
                  value: settingsVm),
            ],
            child: MaterialApp.router(
              theme: lightTheme,
              routerConfig: router,
            ),
          ),
        );

        // Flush splash delay before navigating to unknown route.
        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pumpAndSettle();

        router.go('/unmatched-web-route');
        await tester.pumpAndSettle();

        expect(find.text('Page Not Found'), findsOneWidget);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(
            scaffold.backgroundColor, equals(lightTheme.scaffoldBackgroundColor));
        expect(scaffold.backgroundColor, isNot(equals(const Color(0xFF1E1E2E))));
      },
    );
  });
}
