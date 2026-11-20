import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/views/auth/forgot_password_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'ForgotPasswordView renders form, validates email, and shows success view on submit',
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
          home: const ForgotPasswordView(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and button are rendered
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);

    // Enter invalid email and tap submit
    final emailField = find.byType(TextField);
    await tester.enterText(emailField, 'not-an-email');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);

    // Enter valid email and tap submit
    await tester.enterText(emailField, 'clara@remedytrack.ph');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    // Expect privacy-preserving success screen
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.textContaining('clara@remedytrack.ph'), findsOneWidget);
    expect(find.text('Return to Sign In'), findsOneWidget);
  });
}
