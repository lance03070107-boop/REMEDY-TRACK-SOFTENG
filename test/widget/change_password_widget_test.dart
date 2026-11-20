import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/errors/app_exception.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/core/utils/result.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/settings/change_password_dialog.dart';
import 'package:remedy_track/views/settings/settings_view.dart';
import '../mocks/test_mock_repositories.dart';

class _StubAuthViewModel extends AuthViewModel {
  bool stubHasPasswordProvider;
  bool stubIsChangingPassword = false;
  Future<Result<void>> Function(String current, String next)? onChangePassword;

  _StubAuthViewModel({this.stubHasPasswordProvider = true})
      : super(userRepository: MockUserRepository());

  @override
  bool get hasPasswordProvider => stubHasPasswordProvider;

  @override
  bool get isPasswordLinked => stubHasPasswordProvider;

  @override
  bool get isChangingPassword => stubIsChangingPassword;

  @override
  String get currentUserEmail => 'patient@example.com';

  @override
  String get currentUserDisplayName => 'Patient One';

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    stubIsChangingPassword = true;
    notifyListeners();
    try {
      if (onChangePassword != null) {
        return await onChangePassword!(currentPassword, newPassword);
      }
      return const Success(null);
    } finally {
      stubIsChangingPassword = false;
      notifyListeners();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildHarness({
    required AuthViewModel authVm,
    required Widget child,
  }) {
    final settingsVm = SettingsViewModel();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('ChangePasswordDialog widget tests', () {
    testWidgets('shows inline validation errors for empty and mismatched fields',
        (tester) async {
      final authVm = _StubAuthViewModel();

      await tester.pumpWidget(
        buildHarness(
          authVm: authVm,
          child: const ChangePasswordDialog(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Update Password with empty fields
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your current password.'), findsOneWidget);
      expect(find.text('Please enter a new password.'), findsOneWidget);
      expect(find.text('Please confirm your new password.'), findsOneWidget);

      // Enter mismatched confirm password
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OldPass123');
      await tester.enterText(fields.at(1), 'NewPass456');
      await tester.enterText(fields.at(2), 'Different789');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('disables button and shows spinner while submitting, then closes on success',
        (tester) async {
      final completer = Completer<Result<void>>();
      final authVm = _StubAuthViewModel()
        ..onChangePassword = (_, __) => completer.future;

      bool? dialogResult;
      await tester.pumpWidget(
        buildHarness(
          authVm: authVm,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                dialogResult = await ChangePasswordDialog.show(ctx);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'OldPass123');
      await tester.enterText(fields.at(1), 'NewPass456');
      await tester.enterText(fields.at(2), 'NewPass456');

      await tester.tap(find.text('Update Password'));
      await tester.pump();

      // Spinner shown and submit button disabled
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final submitButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(submitButton.onPressed, isNull);

      completer.complete(const Success(null));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(find.byType(ChangePasswordDialog), findsNothing);
    });

    testWidgets('displays inline error message on incorrect current password',
        (tester) async {
      final authVm = _StubAuthViewModel()
        ..onChangePassword = (_, __) async => const Failure(
              AuthException('Current password is incorrect.'),
            );

      await tester.pumpWidget(
        buildHarness(
          authVm: authVm,
          child: const ChangePasswordDialog(),
        ),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'WrongPass1');
      await tester.enterText(fields.at(1), 'NewPass456');
      await tester.enterText(fields.at(2), 'NewPass456');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();

      expect(find.text('Current password is incorrect.'), findsOneWidget);
    });
  });

  group('SettingsView Change Password tile visibility', () {
    testWidgets('shows Change Password tile for password accounts',
        (tester) async {
      final authVm = _StubAuthViewModel(stubHasPasswordProvider: true);

      await tester.pumpWidget(
        buildHarness(authVm: authVm, child: const SettingsView()),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Change Password'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Set a Password'), findsNothing);
    });

    testWidgets('shows Set a Password tile for Google/Apple-only accounts',
        (tester) async {
      final authVm = _StubAuthViewModel(stubHasPasswordProvider: false);

      await tester.pumpWidget(
        buildHarness(authVm: authVm, child: const SettingsView()),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Set a Password'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Set a Password'), findsOneWidget);
      expect(find.text('Change Password'), findsNothing);
    });
  });
}
