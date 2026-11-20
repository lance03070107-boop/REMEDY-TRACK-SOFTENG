import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/viewmodels/adherence_viewmodel.dart';

void main() {
  group('AdherenceViewModel Calculations Tests', () {
    late AdherenceViewModel viewModel;

    setUp(() {
      viewModel = AdherenceViewModel();
    });

    test(
        'calculateAdherenceRate returns 100% when all non-snoozed doses are taken or late',
        () {
      final logs = [
        IntakeLog(
          id: '1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Amoxicillin',
          doseAmount: 1,
          scheduledTime: DateTime.now().subtract(const Duration(hours: 4)),
          status: DoseStatus.taken,
        ),
        IntakeLog(
          id: '2',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Amoxicillin',
          doseAmount: 1,
          scheduledTime: DateTime.now().subtract(const Duration(hours: 12)),
          status: DoseStatus.late,
        ),
      ];

      final rate = viewModel.calculateAdherenceRate(logs);
      expect(rate, 100.0);
    });

    test('calculateAdherenceRate accurately penalizes missed doses', () {
      final logs = [
        IntakeLog(
          id: '1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Amoxicillin',
          doseAmount: 1,
          scheduledTime: DateTime.now().subtract(const Duration(hours: 4)),
          status: DoseStatus.taken,
        ),
        IntakeLog(
          id: '2',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'Amoxicillin',
          doseAmount: 1,
          scheduledTime: DateTime.now().subtract(const Duration(hours: 12)),
          status: DoseStatus.missed,
        ),
      ];

      final rate = viewModel.calculateAdherenceRate(logs);
      expect(rate, 50.0);
    });

    test(
        'calculateStreakDays accurately counts unbroken consecutive 100% adherence days',
        () {
      final now = DateTime.now();
      final logs = [
        // Today: Taken
        IntakeLog(
          id: '1',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'M1',
          doseAmount: 1,
          scheduledTime: DateTime(now.year, now.month, now.day, 8, 0),
          status: DoseStatus.taken,
        ),
        // Yesterday: Taken
        IntakeLog(
          id: '2',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'M1',
          doseAmount: 1,
          scheduledTime: DateTime(now.year, now.month, now.day - 1, 8, 0),
          status: DoseStatus.taken,
        ),
        // 2 days ago: Missed (Breaks streak)
        IntakeLog(
          id: '3',
          userId: 'u1',
          medicationId: 'm1',
          medicationName: 'M1',
          doseAmount: 1,
          scheduledTime: DateTime(now.year, now.month, now.day - 2, 8, 0),
          status: DoseStatus.missed,
        ),
      ];

      final streak = viewModel.calculateStreakDays(logs);
      expect(streak, 2);
    });
  });
}
