import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/views/auth/reauth_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'ReauthDialog renders security challenge and allows password entry',
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
          home: const Scaffold(
            body: ReauthDialog(
              title: 'Confirm Account Erasure',
              reason: 'Re-authenticate to permanently erase your records.',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and security reason
    expect(find.text('Confirm Account Erasure'), findsOneWidget);
    expect(find.text('Re-authenticate to permanently erase your records.'),
        findsOneWidget);

    // Verify presence of confirm and cancel buttons
    expect(find.text('Confirm & Authorize'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Verify presence of password input by default
    expect(find.text('Current Account Password'), findsOneWidget);
  });
}
