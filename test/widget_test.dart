import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mocks/test_mock_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'rt_onboarding_complete': true});
  });

  testWidgets(
      'RemedyTrackApp initializes and mounts splash screen without errors',
      (WidgetTester tester) async {
    final mocks = MockRepositories.instance;
    await tester.pumpWidget(RemedyTrackApp(
      medicationRepository: mocks.medicationRepository,
      intakeRepository: mocks.intakeRepository,
      inventoryRepository: mocks.inventoryRepository,
      userRepository: mocks.userRepository,
      caregiverRepository: mocks.caregiverRepository,
    ));

    // Advance through initial animation frames
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RemedyTrackApp), findsOneWidget);
    expect(find.text('RemedyTrack'), findsOneWidget);

    // Complete splash transition timer and settle all pending frames
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
