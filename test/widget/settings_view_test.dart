import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import '../mocks/test_mock_repositories.dart';
import 'package:remedy_track/viewmodels/auth_viewmodel.dart';
import 'package:remedy_track/viewmodels/settings_viewmodel.dart';
import 'package:remedy_track/views/settings/default_alarm_tone_view.dart';
import 'package:remedy_track/views/settings/global_alarm_sound_manager_view.dart';
import 'package:remedy_track/views/settings/settings_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsView Widget & Production Hardening Tests', () {
    late MockUserRepository mockUserRepo;
    late AuthViewModel authVm;
    late SettingsViewModel settingsVm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockUserRepo = MockUserRepository();
      authVm = AuthViewModel(userRepository: mockUserRepo);
      settingsVm = SettingsViewModel();
    });

    Widget createTestApp({Widget home = const SettingsView()}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: authVm),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: home,
        ),
      );
    }

    testWidgets(
        'renders reorganized Settings sections and excludes removed options',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Settings & Privacy'), findsOneWidget);
      expect(find.text('Caregiver & Family Sharing'), findsOneWidget);
      expect(find.text('System Default'), findsWidgets);
      expect(find.text('Medication Alarm Sounds'), findsOneWidget);
      expect(find.text('Default Snooze Duration'), findsOneWidget);
      expect(find.text('Senior High-Contrast Mode'), findsOneWidget);
      expect(find.text('Biometric App Lock'), findsOneWidget);
      expect(
          find.text('RemedyTrack v1.0.0 (Production Build)'), findsOneWidget);

      expect(
          find.text('Check device permissions for reliable alarm delivery'),
          findsOneWidget);

      // Verify mandatory removed items are absent
      expect(find.text('Export Clinical Data'), findsNothing);
      expect(find.text('Caregiver Mode'), findsNothing);
      expect(find.text('Dependents'), findsNothing);
      expect(find.textContaining('test alarm delivery'), findsNothing);
    });

    testWidgets(
        'navigates through GlobalAlarmSoundManagerView to DefaultAlarmToneView and saves selected tone',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestApp(home: const GlobalAlarmSoundManagerView()),
      );
      await tester.pumpAndSettle();

      // Screen 1: Global Alarm Sound Manager
      expect(find.text('Global Alarm Sound Manager'), findsOneWidget);
      expect(find.text('Default Alarm Tone'), findsOneWidget);

      // Screen 2: Default Alarm Tone selection
      await tester.pumpWidget(
        createTestApp(home: const DefaultAlarmToneView()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Classic Medical Alarm'), findsOneWidget);
      expect(find.text('Gentle Chime'), findsOneWidget);

      await tester.tap(find.text('Gentle Chime'));
      await tester.pumpAndSettle();

      expect(settingsVm.alarmSound, 'remedy_alarm_gentle');
    });

    testWidgets('production footer does not leak developer or evaluation mode',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final footerFinder = find.text('RemedyTrack v1.0.0 (Production Build)');
      expect(footerFinder, findsOneWidget);

      // Multiple taps
      for (int i = 0; i < 7; i++) {
        await tester.tap(footerFinder);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // No developer options or evaluation mode should appear
      expect(find.text('Developer & Capstone Tools'), findsNothing);
      expect(find.text('ISO/IEC 25010 Evaluation Mode'), findsNothing);
      expect(find.text('Evaluation Mode'), findsNothing);
    });
  });
}
