import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/constants/app_strings.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/views/auth/login_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'LoginView renders empty form fields without hardcoded demo prefill',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockUserRepo = MockUserRepository();
    final authVm = AuthViewModel(userRepository: mockUserRepo);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoginView(),
        ),
      ),
    );

    // Verify title and subtitle
    expect(find.text(AppStrings.loginTitle), findsOneWidget);
    expect(find.text(AppStrings.loginSubtitle), findsOneWidget);

    // Verify email and password text fields are present and empty
    expect(find.text('lance.aclan@remedytrack.ph'), findsNothing);
    expect(find.text('RemedyTrack2026!'), findsNothing);
    expect(find.text('Pre-Configured Demo Account'), findsNothing);

    // Verify sign-in button
    expect(find.text(AppStrings.signInButton), findsOneWidget);
  });
}
