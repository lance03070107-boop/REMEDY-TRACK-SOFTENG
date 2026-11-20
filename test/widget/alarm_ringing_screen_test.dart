import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/services/alarm_scheduler.dart';
import 'package:remedy_track/services/notification_service.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import 'package:remedy_track/viewmodels/inventory_viewmodel.dart';
import 'package:remedy_track/viewmodels/medication_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/alarm/alarm_ringing_screen.dart';
import 'package:remedy_track/views/widgets/pill_avatar.dart';
import '../mocks/test_mock_repositories.dart';

class _AlarmTestAuthViewModel extends AuthViewModel {
  _AlarmTestAuthViewModel({required super.userRepository});

  @override
  bool get isAuthenticated => true;

  @override
  String get currentUserId => 'patient_alarm_test_01';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staticAudioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];
  const playersChannel = MethodChannel('xyz.luan/audioplayers');
  final registeredEventChannels = <MethodChannel>[];

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in staticAudioChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    }
    messenger.setMockMethodCallHandler(playersChannel, (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map?;
        final playerId = args?['playerId'] as String?;
        if (playerId != null) {
          final eventChannel =
              MethodChannel('xyz.luan/audioplayers/events/$playerId');
          registeredEventChannels.add(eventChannel);
          messenger.setMockMethodCallHandler(eventChannel, (c) async => null);
        }
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in staticAudioChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(playersChannel, null);
    for (final channel in registeredEventChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    registeredEventChannels.clear();
  });

  Widget buildAlarmHarness({
    required bool disableAnimations,
    double doseAmount = 2.0,
    String formName = 'capsule',
  }) {
    final mockInvRepo = MockInventoryRepository();
    final mockIntakeRepo = MockIntakeRepository(mockInvRepo);
    final mockMedRepo = MockMedicationRepository();
    final mockUserRepo = MockUserRepository();

    final authVm = _AlarmTestAuthViewModel(userRepository: mockUserRepo);
    final medVm = MedicationViewModel(
      medicationRepository: mockMedRepo,
      inventoryRepository: mockInvRepo,
    );
    final intakeVm = IntakeViewModel(intakeRepository: mockIntakeRepo);
    final invVm = InventoryViewModel(inventoryRepository: mockInvRepo);
    final settingsVm = SettingsViewModel();
    final notifService = NotificationService();
    final alarmScheduler = AlarmScheduler(notificationService: notifService);

    return MultiProvider(
      providers: [
        Provider<NotificationService>.value(value: notifService),
        Provider<AlarmScheduler>.value(value: alarmScheduler),
        ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
        ChangeNotifierProvider<MedicationViewModel>.value(value: medVm),
        ChangeNotifierProvider<IntakeViewModel>.value(value: intakeVm),
        ChangeNotifierProvider<InventoryViewModel>.value(value: invVm),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: AlarmRingingScreen(
          medicationId: 'med_amox_500',
          userId: 'patient_alarm_test_01',
          notificationId: 901,
          scheduledTime: DateTime(2026, 11, 13, 8, 0),
          medicationName: 'Amoxicillin',
          strength: '500mg',
          doseAmount: doseAmount,
          formName: formName,
          colorTag: 0xFF1E66F5,
          instructions: 'Take after meals with water',
        ),
      ),
    );
  }

  testWidgets(
      'AlarmRingingScreen renders redesigned single CTA, pluralized unit, quick snooze chips, and opens skip sheet',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildAlarmHarness(disableAnimations: true));
    await tester.pumpAndSettle();

    expect(find.text('Medication Reminder'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('2 capsules'), findsOneWidget);
    expect(find.byType(PillAvatar), findsOneWidget);
    final pillImg = tester.widget<Image>(
      find.descendant(
        of: find.byType(PillAvatar),
        matching: find.byType(Image),
      ),
    );
    expect(
      (pillImg.image as AssetImage).assetName,
      'assets/branding/med_forms/capsule.png',
    );
    final frameFinder =
        find.byKey(const ValueKey<String>('alarm_frame_sequence_icon'));
    expect(frameFinder, findsOneWidget);
    final frameImg = tester.widget<Image>(frameFinder);
    expect(
      (frameImg.image as AssetImage).assetName,
      'assets/branding/alarm_frames/alarm_frame_01.png',
    );
    expect(find.text('Take Dose Now'), findsOneWidget);
    expect(find.text('Or Slide Right to Confirm'), findsNothing);
    expect(find.text('TAKE MEDICINE NOW'), findsNothing);
    expect(find.text('+5m'), findsOneWidget);
    expect(find.text('+10m'), findsOneWidget);
    expect(find.text('+15m'), findsOneWidget);
    expect(find.text('Snooze (3 left)'), findsOneWidget);
    final skipFinder = find.text('Skip Dose');
    expect(skipFinder, findsOneWidget);
    final skipBtn =
        find.ancestor(of: skipFinder, matching: find.byType(OutlinedButton));
    expect(skipBtn, findsOneWidget);

    await tester.ensureVisible(skipBtn);
    await tester.pump();
    final rect = tester.getRect(skipBtn);
    expect(rect.bottom, lessThanOrEqualTo(932), reason: 'btn rect=$rect');
    await tester.tap(skipBtn);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Skip Amoxicillin?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm Skip'), findsOneWidget);
  });

  testWidgets(
      'AlarmRingingScreen animates cleanly when reduced motion is disabled and toggles Mute',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(buildAlarmHarness(
      disableAnimations: false,
      doseAmount: 1.0,
      formName: 'capsule',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('1 capsule'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);

    await tester.tap(find.text('Sound'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Muted'), findsOneWidget);
  });
}
