import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/core/theme/design_tokens.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/views/widgets/dose_card.dart';
import 'package:remedy_track/views/widgets/pill_avatar.dart';
import 'package:remedy_track/views/widgets/progress_ring.dart';
import 'package:remedy_track/views/widgets/status_chip.dart';

void main() {
  final testMedication = Medication(
    id: 'med_test_1',
    userId: 'user_1',
    name: 'Amlodipine Besylate',
    genericName: 'Amlodipine',
    strength: '5mg',
    form: MedicationForm.tablet,
    doseAmount: 1.0,
    instructions: 'Take with breakfast',
    colorTag: 0xFF1E66F5,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget createTestWrapper(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('PillAvatar Widget Tests', () {
    testWidgets('renders semantic label and icon for tablet form',
        (tester) async {
      await tester.pumpWidget(
        createTestWrapper(
          PillAvatar.fromMedication(
            medication: testMedication,
            size: 48,
          ),
        ),
      );

      expect(find.byType(PillAvatar), findsOneWidget);
      expect(find.bySemanticsLabel('tablet medication avatar'), findsOneWidget);
    });

    testWidgets('renders check badge overlay when taken', (tester) async {
      await tester.pumpWidget(
        createTestWrapper(
          PillAvatar.fromMedication(
            medication: testMedication,
            size: 60,
            isTaken: true,
            showBadge: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('uses custom asset icon for every MedicationForm in Inventory',
        (tester) async {
      for (final form in MedicationForm.values) {
        final med = Medication(
          id: 'med_${form.name}',
          userId: 'user_1',
          name: 'Test ${form.name}',
          strength: '10mg',
          form: form,
          doseAmount: 1.0,
          colorTag: 0xFF1E66F5,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        await tester.pumpWidget(
          createTestWrapper(
            PillAvatar.fromMedication(medication: med, size: 46),
          ),
        );
        await tester.pump();

        final imageWidget = tester.widget<Image>(find.byType(Image));
        final assetImage = imageWidget.image as AssetImage;
        expect(
          assetImage.assetName,
          'assets/branding/med_forms/${form.name}.png',
        );
      }
    });
  });

  group('ProgressRing Widget Tests', () {
    testWidgets('renders percentage and count ratio', (tester) async {
      await tester.pumpWidget(
        createTestWrapper(
          const ProgressRing(
            progress: 0.75,
            takenCount: 3,
            totalCount: 4,
            size: 120,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('75%'), findsOneWidget);
      expect(find.text('3 of 4'), findsOneWidget);
    });
  });

  group('StatusChip Widget Tests', () {
    testWidgets('renders icon and text for Taken and Snoozed states',
        (tester) async {
      await tester.pumpWidget(
        createTestWrapper(
          const Column(
            children: [
              StatusChip(status: DoseStatus.taken),
              StatusChip(status: DoseStatus.snoozed),
            ],
          ),
        ),
      );

      expect(find.text('Taken'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Snoozed'), findsOneWidget);
      expect(find.byIcon(Icons.snooze_rounded), findsOneWidget);
    });
  });

  group('DoseCard Accessibility & Action Tests', () {
    testWidgets(
        'renders medication details and enforces 48dp min touch targets',
        (tester) async {
      bool took = false;
      bool snoozed = false;
      bool skipped = false;

      await tester.pumpWidget(
        createTestWrapper(
          DoseCard(
            medication: testMedication,
            scheduledTime: DateTime(2026, 10, 16, 8, 0),
            status: DoseStatus.pending,
            onTake: () => took = true,
            onSnooze: () => snoozed = true,
            onSkip: () => skipped = true,
            showActions: true,
          ),
        ),
      );

      // Verify Medication information
      expect(find.text('Amlodipine Besylate'), findsOneWidget);
      expect(find.text('1 tablet • 5mg'), findsOneWidget);

      // Verify Take button touch target height >= 48dp
      final takeButtonFinder = find.widgetWithText(FilledButton, 'Take Dose');
      expect(takeButtonFinder, findsOneWidget);
      final takeSize = tester.getSize(takeButtonFinder);
      expect(
          takeSize.height, greaterThanOrEqualTo(DesignTokens.minTouchTarget));

      // Tap Take button
      await tester.tap(takeButtonFinder);
      expect(took, isTrue);

      // Tap Snooze button
      final snoozeFinder = find.widgetWithText(OutlinedButton, '10m');
      expect(snoozeFinder, findsOneWidget);
      final snoozeSize = tester.getSize(snoozeFinder);
      expect(
          snoozeSize.height, greaterThanOrEqualTo(DesignTokens.minTouchTarget));
      await tester.tap(snoozeFinder);
      expect(snoozed, isTrue);

      // Tap Skip button
      final skipFinder = find.widgetWithText(TextButton, 'Skip');
      expect(skipFinder, findsOneWidget);
      final skipSize = tester.getSize(skipFinder);
      expect(
          skipSize.height, greaterThanOrEqualTo(DesignTokens.minTouchTarget));
      await tester.tap(skipFinder);
      expect(skipped, isTrue);
    });

    testWidgets(
        'renders on narrow 320dp screen with 1.3x text scale without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: createTestWrapper(
            DoseCard(
              medication: testMedication,
              scheduledTime: DateTime(2026, 10, 16, 8, 0),
              status: DoseStatus.pending,
              onTake: () {},
              onSnooze: () {},
              onSkip: () {},
              showActions: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Amlodipine Besylate'), findsOneWidget);
      expect(find.text('1 tablet • 5mg'), findsOneWidget);
    });
  });
}
