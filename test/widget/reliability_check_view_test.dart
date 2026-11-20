import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/views/settings/reliability_check_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const alarmWindowChannel = MethodChannel('com.remedytrack.app/alarm_window');

  group('ReliabilityCheckView Public Release Verification', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permChannel, (call) async {
        if (call.method == 'checkPermissionStatus') {
          return 1; // granted
        }
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(alarmWindowChannel, (call) async {
        if (call.method == 'canUseFullScreenIntent' ||
            call.method == 'canDrawOverlays') {
          return true;
        }
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(alarmWindowChannel, null);
    });

    testWidgets(
        'renders permission audit cards and excludes removed Test Alarm feature',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const ReliabilityCheckView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reminder Reliability & Diagnostics'), findsOneWidget);
      expect(find.text('Background Alarm Pop-up (Appear on Top)'),
          findsOneWidget);
      expect(find.text('Exact Alarm Scheduling'), findsOneWidget);
      expect(find.text('Notification Alert Permission'), findsOneWidget);
      expect(find.text('Battery Optimization Exemption'), findsOneWidget);
      expect(find.text('Lock-Screen Alarm Pop-up (Alarm Clock Mode)'),
          findsOneWidget);

      // Verify the public-release removed Test Alarm UI is completely absent
      expect(find.text('Test Alarm Sound'), findsNothing);
      expect(find.text('Test Alarm in 10 Seconds'), findsNothing);
      expect(find.textContaining('10 seconds from now'), findsNothing);
    });
  });
}
