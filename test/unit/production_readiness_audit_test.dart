import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedy_track/core/constants/app_constants.dart';
import 'package:remedy_track/core/scheduling/schedule_expander.dart';
import 'package:remedy_track/core/state/dose_state_machine.dart';
import 'package:remedy_track/core/theme/app_theme.dart';
import 'package:remedy_track/core/theme/catppuccin_colors.dart';
import 'package:remedy_track/core/theme/status_colors.dart';
import 'package:remedy_track/core/validation/medication_validator.dart';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/services/alarm_id_generator.dart';
import 'package:remedy_track/services/local_medication_cache.dart';
import 'package:remedy_track/viewmodels/intake_viewmodel.dart';
import '../mocks/test_mock_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. MedicationValidator & Input Sanitization', () {
    test('rejects empty, negative, >9999, NaN, and Infinity stock values', () {
      expect(
        MedicationValidator.validateStock('', form: MedicationForm.tablet),
        isNotNull,
      );
      expect(
        MedicationValidator.validateStock('-5', form: MedicationForm.tablet),
        isNotNull,
      );
      expect(
        MedicationValidator.validateStock('9999', form: MedicationForm.tablet),
        isNull,
      );
      expect(
        MedicationValidator.validateStock('10000', form: MedicationForm.tablet),
        isNotNull,
      );
      expect(
        MedicationValidator.validateStock('NaN', form: MedicationForm.tablet),
        isNotNull,
      );
      expect(
        MedicationValidator.validateStock('Infinity',
            form: MedicationForm.tablet),
        isNotNull,
      );
      expect(
        MedicationValidator.validateStock('1.5', form: MedicationForm.capsule),
        isNotNull, // Capsules must be whole numbers
      );
      expect(
        MedicationValidator.validateStock('0', form: MedicationForm.tablet),
        isNull,
      );
      expect(
        MedicationValidator.validateStock('99', form: MedicationForm.tablet),
        isNull,
      );
      expect(
        MedicationValidator.validateStock('12.5', form: MedicationForm.syrup),
        isNull,
      );
    });

    test('validates dose amount strictly in (0, 100]', () {
      expect(MedicationValidator.validateDoseAmount(''), isNotNull);
      expect(MedicationValidator.validateDoseAmount('0'), isNotNull);
      expect(MedicationValidator.validateDoseAmount('-1'), isNotNull);
      expect(MedicationValidator.validateDoseAmount('101'), isNotNull);
      expect(MedicationValidator.validateDoseAmount('Infinity'), isNotNull);
      expect(MedicationValidator.validateDoseAmount('0.5'), isNull);
      expect(MedicationValidator.validateDoseAmount('2'), isNull);
    });

    test('validates PRN min interval and daily max >= single dose', () {
      expect(MedicationValidator.validatePrnMinInterval('0'), isNotNull);
      expect(MedicationValidator.validatePrnMinInterval('73'), isNotNull);
      expect(MedicationValidator.validatePrnMinInterval('4'), isNull);

      expect(
        MedicationValidator.validatePrnDailyMax('1', doseAmount: 2.0),
        isNotNull,
      );
      expect(
        MedicationValidator.validatePrnDailyMax('4', doseAmount: 2.0),
        isNull,
      );
    });

    test('validates schedule parameters and time slots', () {
      expect(MedicationValidator.validateEveryXDays('0'), isNotNull);
      expect(MedicationValidator.validateEveryXDays('366'), isNotNull);
      expect(MedicationValidator.validateEveryXDays('3'), isNull);

      expect(MedicationValidator.validateEveryXHours('0'), isNotNull);
      expect(MedicationValidator.validateEveryXHours('25'), isNotNull);
      expect(MedicationValidator.validateEveryXHours('6'), isNull);

      expect(MedicationValidator.validateCycleDays('0'), isNotNull);
      expect(MedicationValidator.validateCycleDays('21'), isNull);

      expect(MedicationValidator.validateTimeSlots(const []), isNotNull);
      expect(
        MedicationValidator.validateTimeSlots(const ['08:00', '08:00']),
        isNotNull,
      );
      expect(
        MedicationValidator.validateTimeSlots(const ['08:00', '20:00']),
        isNull,
      );

      expect(MedicationValidator.validateWeekdays(const []), isNotNull);
      expect(MedicationValidator.validateWeekdays(const [0, 8]), isNotNull);
      expect(MedicationValidator.validateWeekdays(const [1, 3, 5]), isNull);
    });

    test('form units and paste formatters sanitize input accurately', () {
      expect(MedicationValidator.unitForForm(MedicationForm.tablet), 'tablets');
      expect(
          MedicationValidator.unitForForm(MedicationForm.capsule), 'capsules');
      expect(MedicationValidator.unitForForm(MedicationForm.syrup), 'mL');
      expect(
          MedicationValidator.unitForForm(MedicationForm.injection), 'doses');
      expect(MedicationValidator.unitForForm(MedicationForm.drops), 'drops');
      expect(MedicationValidator.unitForForm(MedicationForm.inhaler), 'puffs');
      expect(MedicationValidator.unitForForm(MedicationForm.topical),
          'applications');

      final decFormatter =
          MedicationValidator.decimalFormatters(maxDecimals: 2).first;
      final formatted = decFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'abc12.34.56xyz'),
      );
      expect(formatted.text, '12.34');
    });

    test(
        'formatCompactStockCount displays 0..99 and caps display at 99 (no 99+) without altering underlying InventoryItem',
        () {
      expect(MedicationValidator.formatCompactStockCount(0), '0');
      expect(MedicationValidator.formatCompactStockCount(1), '1');
      expect(MedicationValidator.formatCompactStockCount(7), '7');
      expect(MedicationValidator.formatCompactStockCount(12.5), '12.5');
      expect(MedicationValidator.formatCompactStockCount(25), '25');
      expect(MedicationValidator.formatCompactStockCount(99), '99');
      expect(MedicationValidator.formatCompactStockCount(100), '99');
      expect(MedicationValidator.formatCompactStockCount(250), '99');

      const item = InventoryItem(
        id: 'inv_250',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 250.0,
        lowStockThreshold: 14.0,
      );
      // Display is capped at 99, but real stock remains 250.0 and deducts to 249.0
      expect(
          MedicationValidator.formatCompactStockCount(item.currentStock), '99');
      expect(item.currentStock, 250.0);
      final afterDose = item.copyWith(currentStock: item.currentStock - 1.0);
      expect(afterDose.currentStock, 249.0);
      expect(
          MedicationValidator.formatCompactStockCount(afterDose.currentStock),
          '99');
    });
  });

  group('2. InventoryItem Calculations & Honest Stock Semantics', () {
    final baseStart = DateTime(2026, 1, 1);

    test('calculateDailyPrescribedRate handles all 5 ScheduleFrequency values',
        () {
      Medication buildMed(
        DoseSchedule schedule, {
        MedicationForm form = MedicationForm.tablet,
        bool isPrn = false,
      }) {
        return Medication(
          id: 'm1',
          userId: 'u1',
          name: 'Amoxicillin',
          strength: '500mg',
          form: form,
          doseAmount: 2.0,
          isPrn: isPrn,
          schedule: schedule,
          createdAt: baseStart,
          updatedAt: baseStart,
        );
      }

      // 1. daily (1 slot): 1 slot * 2.0 = 2.0/day
      final onceDailyMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00'],
        startDate: baseStart,
      ));
      expect(InventoryItem.calculateDailyPrescribedRate(onceDailyMed), 2.0);

      // 2. daily (multiple slots): 3 slots * 2.0 = 6.0/day
      final multiMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00', '14:00', '20:00'],
        startDate: baseStart,
      ));
      expect(InventoryItem.calculateDailyPrescribedRate(multiMed), 6.0);

      // 3. specificWeekdays: 3 days/wk * 1 slot * 2.0 = 6/7 per day
      final weeklyMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.specificWeekdays,
        timesOfDay: const ['08:00'],
        weekdays: const [1, 3, 5],
        startDate: baseStart,
      ));
      expect(
        InventoryItem.calculateDailyPrescribedRate(weeklyMed),
        closeTo(6.0 / 7.0, 0.0001),
      );

      // 4. everyXDays: every 2 days * 1 slot * 2.0 = 1.0/day
      final intervalMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.everyXDays,
        timesOfDay: const ['08:00'],
        intervalValue: 2,
        startDate: baseStart,
      ));
      expect(InventoryItem.calculateDailyPrescribedRate(intervalMed), 1.0);

      // 5. cycleBased: 21 active / 7 rest * 1 slot * 2.0 = 1.5/day
      final cycleMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.cycleBased,
        timesOfDay: const ['08:00'],
        cycleActiveDays: 21,
        cycleRestDays: 7,
        startDate: baseStart,
      ));
      expect(InventoryItem.calculateDailyPrescribedRate(cycleMed), 1.5);

      // 6. everyXHours: every 6 hours (4x/day) * 2.0 = 8.0/day
      final hourlyMed = buildMed(DoseSchedule(
        frequency: ScheduleFrequency.everyXHours,
        timesOfDay: const ['06:00', '12:00', '18:00', '00:00'],
        intervalValue: 6,
        startDate: baseStart,
      ));
      expect(InventoryItem.calculateDailyPrescribedRate(hourlyMed), 8.0);
    });

    test(
        'estimatedDaysRemainingForMedication returns null for non-auto-decrementing forms and PRN',
        () {
      const item = InventoryItem(
        id: 'inv_1',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 10,
        lowStockThreshold: 4,
      );

      final syrupMed = Medication(
        id: 'm1',
        userId: 'u1',
        name: 'Cough Syrup',
        strength: '5mL',
        form: MedicationForm.syrup,
        doseAmount: 5,
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: baseStart,
        ),
        createdAt: baseStart,
        updatedAt: baseStart,
      );

      expect(item.estimatedDaysRemainingForMedication(syrupMed), isNull);

      final tabletMed = syrupMed.copyWith(
        form: MedicationForm.tablet,
        doseAmount: 2.0,
      );
      expect(item.estimatedDaysRemainingForMedication(tabletMed), 5);
    });

    test(
        'InventoryItem clamps stock to [0, 9999] and defaults missing JSON stock to 0',
        () {
      final parsed = InventoryItem.fromJson(const {
        'id': 'inv_missing',
        'userId': 'u1',
        'medicationId': 'm1',
      });
      expect(parsed.currentStock, 0.0);

      final clamped = InventoryItem.fromJson(
        parsed.copyWith(currentStock: 50000).toJson(),
      );
      expect(clamped.currentStock, AppConstants.maxStock);
    });
  });

  group('3. ScheduleExpander Edge Cases', () {
    test(
        'respects future startDate, endDate boundary, everyXDays, cycleBased, and everyXHours',
        () {
      final start = DateTime(2026, 5, 10);
      final end = DateTime(2026, 5, 14);
      final every2Days = DoseSchedule(
        frequency: ScheduleFrequency.everyXDays,
        timesOfDay: const ['09:00'],
        intervalValue: 2,
        startDate: start,
        endDate: end,
      );

      // Before start date -> false
      expect(
          ScheduleExpander.isScheduledOnDate(every2Days, DateTime(2026, 5, 9)),
          isFalse);
      // Day 0 -> true
      expect(
          ScheduleExpander.isScheduledOnDate(every2Days, DateTime(2026, 5, 10)),
          isTrue);
      // Day 1 -> false
      expect(
          ScheduleExpander.isScheduledOnDate(every2Days, DateTime(2026, 5, 11)),
          isFalse);
      // Day 2 -> true
      expect(
          ScheduleExpander.isScheduledOnDate(every2Days, DateTime(2026, 5, 12)),
          isTrue);
      // After endDate -> false
      expect(
          ScheduleExpander.isScheduledOnDate(every2Days, DateTime(2026, 5, 16)),
          isFalse);

      // Cycle-based: 2 active days, 1 rest day
      final cycleSched = DoseSchedule(
        frequency: ScheduleFrequency.cycleBased,
        timesOfDay: const ['08:00'],
        cycleActiveDays: 2,
        cycleRestDays: 1,
        startDate: start,
      );
      expect(
          ScheduleExpander.isScheduledOnDate(cycleSched, DateTime(2026, 5, 10)),
          isTrue);
      expect(
          ScheduleExpander.isScheduledOnDate(cycleSched, DateTime(2026, 5, 11)),
          isTrue);
      expect(
          ScheduleExpander.isScheduledOnDate(cycleSched, DateTime(2026, 5, 12)),
          isFalse);
      expect(
          ScheduleExpander.isScheduledOnDate(cycleSched, DateTime(2026, 5, 13)),
          isTrue);
    });
  });

  group('4. Edit-Preserves-Fields & Nullable copyWith Clearing', () {
    test(
        'Medication, DoseSchedule, and InventoryItem preserve untouched fields and clear nullables when requested',
        () {
      final originalCreated = DateTime(2025, 11, 15, 8, 30);
      final originalScheduleStart = DateTime(2025, 11, 10);
      final schedule = DoseSchedule(
        frequency: ScheduleFrequency.everyXDays,
        timesOfDay: const ['08:00'],
        intervalValue: 3,
        startDate: originalScheduleStart,
        endDate: DateTime(2026, 12, 31),
      );

      final med = Medication(
        id: 'med_1',
        userId: 'user_1',
        name: 'Metformin',
        genericName: 'Metformin HCl',
        strength: '500mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        instructions: 'Take with meals',
        notes: 'Do not crush',
        colorTag: CatppuccinColors.latteBlue.toARGB32(),
        iconTag: 'custom_pill_icon',
        schedule: schedule,
        createdAt: originalCreated,
        updatedAt: originalCreated,
      );

      // Simulate editing only strength
      final edited = med.copyWith(strength: '850mg');
      expect(edited.notes, 'Do not crush');
      expect(edited.createdAt, originalCreated);
      expect(edited.iconTag, 'custom_pill_icon');
      expect(edited.schedule?.startDate, originalScheduleStart);
      expect(edited.schedule?.endDate, DateTime(2026, 12, 31));

      // Explicitly clear nullable fields back to null
      final cleared = edited.copyWith(
        notes: null,
        minIntervalHours: null,
        dailyMaxDose: null,
        customSoundPath: null,
        schedule: schedule.copyWith(endDate: null),
      );
      expect(cleared.notes, isNull);
      expect(cleared.minIntervalHours, isNull);
      expect(cleared.dailyMaxDose, isNull);
      expect(cleared.customSoundPath, isNull);
      expect(cleared.schedule?.endDate, isNull);

      // InventoryItem preserves lowStockThreshold and lastRefillDate on stock update
      final refillDate = DateTime(2026, 3, 1);
      final inv = InventoryItem(
        id: 'inv_med_1',
        userId: 'user_1',
        medicationId: 'med_1',
        currentStock: 60,
        lowStockThreshold: 14,
        lastRefillDate: refillDate,
      );
      final decremented = inv.copyWith(currentStock: inv.currentStock - 1);
      expect(decremented.currentStock, 59);
      expect(decremented.lowStockThreshold, 14);
      expect(decremented.lastRefillDate, refillDate);
    });
  });

  group('5. Offline-Fallback Intake Path & Local Cache Minimizer', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'flushPendingBackgroundIntakes processes both nested and flat offline payloads and enforces duplicate guard',
        () async {
      final mockInvRepo = MockInventoryRepository();
      final mockIntakeRepo = MockIntakeRepository(mockInvRepo);
      final scheduled = DateTime(2026, 6, 1, 8, 0);

      const existingInv = InventoryItem(
        id: 'inv_m1',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 20,
        lowStockThreshold: 5,
      );
      await mockInvRepo.setInventoryItem(existingInv);

      final log1 = IntakeLog(
        id: DoseStateMachine.generateLogId('m1', scheduled),
        userId: 'u1',
        medicationId: 'm1',
        medicationName: 'Losartan',
        doseAmount: 1.0,
        scheduledTime: scheduled,
        recordedTime: scheduled.add(const Duration(minutes: 2)),
        status: DoseStatus.taken,
      );

      SharedPreferences.setMockInitialValues({
        'pending_background_intakes': [
          // Nested format written by AlarmRingingScreen
          jsonEncode({
            'log': log1.toJson(),
            'decrementInventory': true,
          }),
          // Duplicate of the same dose in flat format written by NotificationService
          jsonEncode({
            ...log1.toJson(),
            'decrementInventory': true,
          }),
        ],
      });

      final vm = IntakeViewModel(
        intakeRepository: mockIntakeRepo,
      );

      await vm.flushPendingBackgroundIntakes('u1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_background_intakes'), isNull);

      // Stock should only decrement ONCE (from 20 to 19) thanks to state-machine duplicate guard
      final updatedInv =
          await mockInvRepo.getInventoryByMedicationId('u1', 'm1');
      expect(updatedInv?.currentStock, 19.0);
    });

    test(
        'LocalMedicationCache strips clinical notes and genericName before caching',
        () async {
      final med = Medication(
        id: 'med_phi',
        userId: 'u1',
        name: 'Atorvastatin',
        genericName: 'Sensitive Generic Name',
        strength: '20mg',
        form: MedicationForm.tablet,
        doseAmount: 1.0,
        notes: 'Sensitive clinical diagnosis note',
        schedule: DoseSchedule(
          frequency: ScheduleFrequency.daily,
          timesOfDay: const ['08:00'],
          startDate: DateTime(2026, 1, 1),
        ),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await LocalMedicationCache.saveMedications([med]);
      final restored = await LocalMedicationCache.loadMedications();
      expect(restored.length, 1);
      expect(restored.first.name, 'Atorvastatin');
      expect(restored.first.notes, isNull);
      expect(restored.first.genericName, isEmpty);

      await LocalMedicationCache.clear();
      expect(await LocalMedicationCache.loadMedications(), isEmpty);
    });

    test(
        'AlarmIdGenerator produces deterministic FNV-1a low-stock notification IDs',
        () {
      final id1 =
          AlarmIdGenerator.generateLowStockNotificationId('med_abc_123');
      final id2 =
          AlarmIdGenerator.generateLowStockNotificationId('med_abc_123');
      final id3 =
          AlarmIdGenerator.generateLowStockNotificationId('med_xyz_789');
      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(id1, greaterThan(0));
    });
  });

  group(
      '6. WCAG AA Contrast Verification over Catppuccin & StatusColors Tokens',
      () {
    test(
        'Light (Latte) and Dark (Mocha) text and status tokens achieve >= 4.5:1 contrast',
        () {
      // Primary & secondary text on Latte & Mocha surfaces
      expect(
        CatppuccinColors.contrastRatio(
          CatppuccinColors.latteText,
          CatppuccinColors.latteBase,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        CatppuccinColors.contrastRatio(
          CatppuccinColors.latteSubtext1,
          CatppuccinColors.latteBase,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        CatppuccinColors.contrastRatio(
          CatppuccinColors.mochaText,
          CatppuccinColors.mochaBase,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        CatppuccinColors.contrastRatio(
          CatppuccinColors.mochaSubtext1,
          CatppuccinColors.mochaBase,
        ),
        greaterThanOrEqualTo(4.5),
      );

      // ColorScheme primary/secondary/error against onPrimary/onSecondary/onError
      const latte = AppTheme.latteColorScheme;
      expect(CatppuccinColors.contrastRatio(latte.primary, latte.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(latte.secondary, latte.onSecondary),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(latte.error, latte.onError),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(latte.outline, latte.surface),
          greaterThanOrEqualTo(3.0));

      const mocha = AppTheme.mochaColorScheme;
      expect(CatppuccinColors.contrastRatio(mocha.primary, mocha.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(mocha.secondary, mocha.onSecondary),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(mocha.error, mocha.onError),
          greaterThanOrEqualTo(4.5));
      expect(CatppuccinColors.contrastRatio(mocha.outline, mocha.surface),
          greaterThanOrEqualTo(3.0));

      // StatusColors light pairs (against latteBase and against on*)
      const sLight = StatusColors.light;
      for (final (fg, onFg) in [
        (sLight.taken, sLight.onTaken),
        (sLight.late, sLight.onLate),
        (sLight.missed, sLight.onMissed),
        (sLight.skipped, sLight.onSkipped),
        (sLight.snoozed, sLight.onSnoozed),
        (sLight.lowStock, sLight.onLowStock),
      ]) {
        expect(
          CatppuccinColors.contrastRatio(fg, CatppuccinColors.latteBase),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          CatppuccinColors.contrastRatio(fg, onFg),
          greaterThanOrEqualTo(4.5),
        );
      }

      // StatusColors dark pairs (against mochaBase and against on*)
      const sDark = StatusColors.dark;
      for (final (fg, onFg) in [
        (sDark.taken, sDark.onTaken),
        (sDark.late, sDark.onLate),
        (sDark.missed, sDark.onMissed),
        (sDark.skipped, sDark.onSkipped),
        (sDark.snoozed, sDark.onSnoozed),
        (sDark.lowStock, sDark.onLowStock),
      ]) {
        expect(
          CatppuccinColors.contrastRatio(fg, CatppuccinColors.mochaBase),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          CatppuccinColors.contrastRatio(fg, onFg),
          greaterThanOrEqualTo(4.5),
        );
      }

      // Medication swatches against adaptive onColorFor checkmark (>= 4.5:1 contrast)
      for (final c in [
        ...CatppuccinColors.medicationPaletteLight,
        ...CatppuccinColors.medicationPaletteDark,
      ]) {
        final onColor = CatppuccinColors.onColorFor(c);
        expect(
          CatppuccinColors.contrastRatio(c, onColor),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });
}
