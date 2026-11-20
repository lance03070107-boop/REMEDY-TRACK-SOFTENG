import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/caregiver_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/inventory_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import 'package:remedy_track/views/profile/caregiver_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/test_mock_repositories.dart';

class _CaregiverTestAuthViewModel extends AuthViewModel {
  _CaregiverTestAuthViewModel({required super.userRepository});

  @override
  bool get isAuthenticated => true;

  @override
  String get currentUserId => 'patient_caregiver_test_01';

  @override
  String get currentUserDisplayName => 'Alice Santos';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaregiverView Widget Tests', () {
    late MockUserRepository mockUserRepo;
    late MockCaregiverRepository mockCaregiverRepo;
    late _CaregiverTestAuthViewModel authVm;
    late CaregiverViewModel caregiverVm;
    late MedicationViewModel medVm;
    late IntakeViewModel intakeVm;
    late InventoryViewModel invVm;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockUserRepo = MockUserRepository();
      mockCaregiverRepo = MockCaregiverRepository();
      final mockInvRepo = MockInventoryRepository();
      authVm = _CaregiverTestAuthViewModel(userRepository: mockUserRepo);
      caregiverVm = CaregiverViewModel(
        caregiverRepository: mockCaregiverRepo,
        userRepository: mockUserRepo,
      );
      medVm = MedicationViewModel(
        medicationRepository: MockMedicationRepository(),
        inventoryRepository: mockInvRepo,
      );
      intakeVm = IntakeViewModel(
        intakeRepository: MockIntakeRepository(mockInvRepo),
      );
      invVm = InventoryViewModel(inventoryRepository: mockInvRepo);
    });

    Widget buildTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
          ChangeNotifierProvider<CaregiverViewModel>.value(value: caregiverVm),
          ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
          ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
          ChangeNotifierProvider<InventoryViewModel>.value(value: invVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CaregiverView(),
        ),
      );
    }

    testWidgets(
      'generates pairing code and shows confirmation SnackBar when tapped',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        final generateButton = find.text('Generate 24h Pairing Code');
        expect(generateButton, findsOneWidget);

        await tester.ensureVisible(generateButton);
        await tester.tap(generateButton);
        await tester.pumpAndSettle();

        final invite = caregiverVm.activeInvite;
        expect(invite, isNotNull);
        expect(invite!.code.length, 6);
        expect(find.text(invite.code), findsOneWidget);
        expect(
          find.text('Pairing code generated: ${invite.code}'),
          findsOneWidget,
        );

        String? copiedClipboardText;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedClipboardText =
                (call.arguments as Map?)?['text'] as String?;
          }
          return null;
        });
        addTearDown(
            () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

        final codeTile =
            find.byKey(const ValueKey<String>('caregiver_pairing_code_tile'));
        expect(codeTile, findsOneWidget);
        await tester.ensureVisible(codeTile);
        await tester.tap(find.text(invite.code));
        await tester.pumpAndSettle();

        expect(copiedClipboardText, invite.code);
        expect(find.text('Pairing code copied to clipboard!'), findsOneWidget);
      },
    );

    testWidgets(
      'shows red error SnackBar and dismissible inline banner when code generation fails',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        mockCaregiverRepo.shouldFailInviteGeneration = true;

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        final generateButton = find.text('Generate 24h Pairing Code');
        expect(generateButton, findsOneWidget);

        await tester.ensureVisible(generateButton);
        await tester.tap(generateButton);
        await tester.pumpAndSettle();

        expect(caregiverVm.activeInvite, isNull);
        expect(caregiverVm.errorMessage, 'Mock invite generation failed');
        expect(find.text('Mock invite generation failed'), findsAtLeastNWidgets(2));
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  });
}
