import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/constants/app_constants.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/views/widgets/app_lock_overlay.dart';
import '../mocks/test_mock_repositories.dart';

class _TestAuthViewModel extends AuthViewModel {
  final bool _authenticated;

  _TestAuthViewModel({required bool authenticated})
      : _authenticated = authenticated,
        super(userRepository: MockUserRepository());

  @override
  bool get isAuthenticated => _authenticated;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLockOverlay Cold-Start Biometric Lock', () {
    testWidgets(
        'locks immediately on cold start when biometric lock is enabled and user is authenticated',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyBiometricEnabled: true,
      });

      final authVm = _TestAuthViewModel(authenticated: true);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVm,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AppLockOverlay(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('RemedyTrack Locked'), findsOneWidget);
    });

    testWidgets(
        'does NOT lock on cold start when biometric lock is disabled',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyBiometricEnabled: false,
      });

      final authVm = _TestAuthViewModel(authenticated: true);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVm,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AppLockOverlay(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('RemedyTrack Locked'), findsNothing);
      expect(find.text('Protected Dashboard'), findsOneWidget);
    });

    testWidgets(
        'does NOT lock on cold start when user is not authenticated',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyBiometricEnabled: true,
      });

      final authVm = _TestAuthViewModel(authenticated: false);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authVm,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AppLockOverlay(
              child: Scaffold(body: Text('Login Screen')),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('RemedyTrack Locked'), findsNothing);
      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
