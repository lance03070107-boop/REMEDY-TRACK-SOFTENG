import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/core/state/dose_state_machine.dart';

void main() {
  group('DoseStateMachine Transition Table & Invariants Tests', () {
    final scheduled = DateTime(2026, 10, 11, 8, 0, 0);

    test(
        'generates deterministic log ID matching {medicationId}_{scheduledEpochMinutes}',
        () {
      final logId =
          DoseStateMachine.generateLogId('med_aspirin_100', scheduled);
      final expectedMinutes = scheduled.millisecondsSinceEpoch ~/ (1000 * 60);
      expect(logId, 'med_aspirin_100_$expectedMinutes');

      // Repeated calls produce identical IDs (duplicate-proof)
      expect(
          DoseStateMachine.generateLogId('med_aspirin_100', scheduled), logId);
    });

    // -------------------------------------------------------------------------
    // Scheduled -> Transitions
    // -------------------------------------------------------------------------
    test(
        'scheduled -> taken within 60 mins is legal and requests inventory decrement',
        () {
      final actionTime = scheduled.add(const Duration(minutes: 15));
      final result = DoseStateMachine.transition(
        currentState: DoseState.scheduled,
        targetState: DoseState.taken,
        scheduledTime: scheduled,
        actionTime: actionTime,
      );

      expect(result.toState, DoseState.taken);
      expect(result.shouldDecrementInventory, isTrue);
      expect(result.isLate, isFalse);
    });

    test('scheduled -> taken past 60 mins flags isLate: true', () {
      final actionTime = scheduled.add(const Duration(minutes: 75));
      final result = DoseStateMachine.transition(
        currentState: DoseState.scheduled,
        targetState: DoseState.taken,
        scheduledTime: scheduled,
        actionTime: actionTime,
      );

      expect(result.toState, DoseState.taken);
      expect(result.shouldDecrementInventory, isTrue);
      expect(result.isLate, isTrue);
    });

    test('scheduled -> skipped does NOT decrement inventory', () {
      final actionTime = scheduled.add(const Duration(minutes: 5));
      final result = DoseStateMachine.transition(
        currentState: DoseState.scheduled,
        targetState: DoseState.skipped,
        scheduledTime: scheduled,
        actionTime: actionTime,
      );

      expect(result.toState, DoseState.skipped);
      expect(result.shouldDecrementInventory, isFalse);
      expect(result.isLate, isFalse);
    });

    test(
        'scheduled -> snoozed within 60 mins is legal and initializes snoozeCount: 1',
        () {
      final actionTime = scheduled.add(const Duration(minutes: 10));
      final result = DoseStateMachine.transition(
        currentState: DoseState.scheduled,
        targetState: DoseState.snoozed,
        scheduledTime: scheduled,
        actionTime: actionTime,
      );

      expect(result.toState, DoseState.snoozed);
      expect(result.shouldDecrementInventory, isFalse);
      expect(result.newSnoozeCount, 1);
    });

    test(
        'scheduled -> snoozed past 60 mins throws IllegalDoseTransitionException',
        () {
      final actionTime = scheduled.add(const Duration(minutes: 65));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.scheduled,
          targetState: DoseState.snoozed,
          scheduledTime: scheduled,
          actionTime: actionTime,
        ),
        throwsA(isA<IllegalDoseTransitionException>()),
      );
    });

    test('scheduled -> missed is legal and does NOT decrement inventory', () {
      final actionTime = scheduled.add(const Duration(minutes: 60));
      final result = DoseStateMachine.transition(
        currentState: DoseState.scheduled,
        targetState: DoseState.missed,
        scheduledTime: scheduled,
        actionTime: actionTime,
      );

      expect(result.toState, DoseState.missed);
      expect(result.shouldDecrementInventory, isFalse);
    });

    // -------------------------------------------------------------------------
    // Snoozed -> Transitions
    // -------------------------------------------------------------------------
    test('snoozed -> snoozed increments snooze count up to 3', () {
      final at20 = scheduled.add(const Duration(minutes: 20));
      final at30 = scheduled.add(const Duration(minutes: 30));

      final res1 = DoseStateMachine.transition(
        currentState: DoseState.snoozed,
        targetState: DoseState.snoozed,
        scheduledTime: scheduled,
        actionTime: at20,
        currentSnoozeCount: 1,
      );
      expect(res1.newSnoozeCount, 2);

      final res2 = DoseStateMachine.transition(
        currentState: DoseState.snoozed,
        targetState: DoseState.snoozed,
        scheduledTime: scheduled,
        actionTime: at30,
        currentSnoozeCount: 2,
      );
      expect(res2.newSnoozeCount, 3);
    });

    test(
        'snoozed -> snoozed past 3 snoozes throws IllegalDoseTransitionException',
        () {
      final at40 = scheduled.add(const Duration(minutes: 40));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.snoozed,
          targetState: DoseState.snoozed,
          scheduledTime: scheduled,
          actionTime: at40,
          currentSnoozeCount: 3, // Already at maximum
        ),
        throwsA(
          isA<IllegalDoseTransitionException>().having(
            (e) => e.message,
            'message',
            contains('Maximum snooze limit reached'),
          ),
        ),
      );
    });

    test(
        'snoozed -> snoozed past 60 mins throws IllegalDoseTransitionException',
        () {
      final at65 = scheduled.add(const Duration(minutes: 65));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.snoozed,
          targetState: DoseState.snoozed,
          scheduledTime: scheduled,
          actionTime: at65,
          currentSnoozeCount: 1,
        ),
        throwsA(
          isA<IllegalDoseTransitionException>().having(
            (e) => e.message,
            'message',
            contains('exceeds the 60-minute unacknowledged window'),
          ),
        ),
      );
    });

    test('snoozed -> taken decrements inventory', () {
      final at25 = scheduled.add(const Duration(minutes: 25));
      final result = DoseStateMachine.transition(
        currentState: DoseState.snoozed,
        targetState: DoseState.taken,
        scheduledTime: scheduled,
        actionTime: at25,
        currentSnoozeCount: 1,
      );

      expect(result.toState, DoseState.taken);
      expect(result.shouldDecrementInventory, isTrue);
    });

    test('snoozed -> skipped does NOT decrement inventory', () {
      final at25 = scheduled.add(const Duration(minutes: 25));
      final result = DoseStateMachine.transition(
        currentState: DoseState.snoozed,
        targetState: DoseState.skipped,
        scheduledTime: scheduled,
        actionTime: at25,
        currentSnoozeCount: 1,
      );

      expect(result.toState, DoseState.skipped);
      expect(result.shouldDecrementInventory, isFalse);
    });

    // -------------------------------------------------------------------------
    // Missed -> Transitions ("I actually took it" correction)
    // -------------------------------------------------------------------------
    test(
        'missed -> taken WITHOUT isLateCorrection throws IllegalDoseTransitionException',
        () {
      final at90 = scheduled.add(const Duration(minutes: 90));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.missed,
          targetState: DoseState.taken,
          scheduledTime: scheduled,
          actionTime: at90,
          isLateCorrection: false,
        ),
        throwsA(
          isA<IllegalDoseTransitionException>().having(
            (e) => e.message,
            'message',
            contains('explicit "I actually took it" correction'),
          ),
        ),
      );
    });

    test(
        'missed -> taken WITH isLateCorrection is legal, decrements inventory, and flags isLate: true',
        () {
      final at90 = scheduled.add(const Duration(minutes: 90));
      final result = DoseStateMachine.transition(
        currentState: DoseState.missed,
        targetState: DoseState.taken,
        scheduledTime: scheduled,
        actionTime: at90,
        isLateCorrection: true,
      );

      expect(result.toState, DoseState.taken);
      expect(result.shouldDecrementInventory, isTrue);
      expect(result.isLate, isTrue);
    });

    test('missed -> snoozed or skipped is illegal', () {
      final at90 = scheduled.add(const Duration(minutes: 90));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.missed,
          targetState: DoseState.snoozed,
          scheduledTime: scheduled,
          actionTime: at90,
        ),
        throwsA(isA<IllegalDoseTransitionException>()),
      );
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.missed,
          targetState: DoseState.skipped,
          scheduledTime: scheduled,
          actionTime: at90,
        ),
        throwsA(isA<IllegalDoseTransitionException>()),
      );
    });

    // -------------------------------------------------------------------------
    // Taken & Skipped Terminal Transitions
    // -------------------------------------------------------------------------
    test('taken -> scheduled is legal for Undo taken', () {
      final at30 = scheduled.add(const Duration(minutes: 30));
      final result = DoseStateMachine.transition(
        currentState: DoseState.taken,
        targetState: DoseState.scheduled,
        scheduledTime: scheduled,
        actionTime: at30,
      );

      expect(result.toState, DoseState.scheduled);
      expect(result.shouldDecrementInventory, isFalse);
    });

    test('taken -> missed or snoozed throws IllegalDoseTransitionException',
        () {
      final at30 = scheduled.add(const Duration(minutes: 30));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.taken,
          targetState: DoseState.missed,
          scheduledTime: scheduled,
          actionTime: at30,
        ),
        throwsA(isA<IllegalDoseTransitionException>()),
      );
    });

    test('skipped cannot transition to any other state', () {
      final at30 = scheduled.add(const Duration(minutes: 30));
      expect(
        () => DoseStateMachine.transition(
          currentState: DoseState.skipped,
          targetState: DoseState.taken,
          scheduledTime: scheduled,
          actionTime: at30,
        ),
        throwsA(isA<IllegalDoseTransitionException>()),
      );
    });

    // -------------------------------------------------------------------------
    // Auto-Reconciliation Check
    // -------------------------------------------------------------------------
    test(
        'shouldAutoReconcileToMissed accurately identifies unacknowledged doses past 60 min',
        () {
      final at30 = scheduled.add(const Duration(minutes: 30));
      final at59 = scheduled.add(const Duration(minutes: 59));
      final at60 = scheduled.add(const Duration(minutes: 60));
      final at90 = scheduled.add(const Duration(minutes: 90));

      // Before 60 minutes: false
      expect(
        DoseStateMachine.shouldAutoReconcileToMissed(
          scheduledTime: scheduled,
          currentTime: at30,
          hasExistingLog: false,
        ),
        isFalse,
      );
      expect(
        DoseStateMachine.shouldAutoReconcileToMissed(
          scheduledTime: scheduled,
          currentTime: at59,
          hasExistingLog: false,
        ),
        isFalse,
      );

      // At or after 60 minutes: true
      expect(
        DoseStateMachine.shouldAutoReconcileToMissed(
          scheduledTime: scheduled,
          currentTime: at60,
          hasExistingLog: false,
        ),
        isTrue,
      );
      expect(
        DoseStateMachine.shouldAutoReconcileToMissed(
          scheduledTime: scheduled,
          currentTime: at90,
          hasExistingLog: false,
        ),
        isTrue,
      );

      // Already has existing log: false
      expect(
        DoseStateMachine.shouldAutoReconcileToMissed(
          scheduledTime: scheduled,
          currentTime: at90,
          hasExistingLog: true,
        ),
        isFalse,
      );
    });
  });
}
