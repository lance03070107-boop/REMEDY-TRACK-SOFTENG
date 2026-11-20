import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/views/auth/verify_otp_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'VerifyOtpView renders 6-digit pin boxes and displays countdown timer',
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
          home: const VerifyOtpView(
            purpose: 'signup',
            email: 'patient@remedytrack.ph',
          ),
        ),
      ),
    );

    // Initial pump & settle
    await tester.pumpAndSettle();

    // Verify header title and instruction text
    expect(find.text('Verify Your Email'), findsOneWidget);
    expect(find.textContaining('patient@remedytrack.ph'), findsOneWidget);

    // Verify 6 input boxes exist (TextFields)
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(6));

    // Verify presence of verify action button
    expect(find.text('Verify Code'), findsOneWidget);

    // Verify presence of resend countdown or resend action
    expect(find.textContaining('Resend code in'), findsOneWidget);
  });

  testWidgets('VerifyOtpView allows entering digits into input boxes',
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
          home: const VerifyOtpView(
            purpose: 'signup',
            email: 'patient@remedytrack.ph',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), '1');
    await tester.enterText(textFields.at(1), '2');
    await tester.enterText(textFields.at(2), '3');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
