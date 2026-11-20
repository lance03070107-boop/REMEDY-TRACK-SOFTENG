/// Pure-Dart Dose State Machine enforcing Laguna University capstone paper requirements
/// and ISO/IEC 25010 reliability specifications.
///
/// Contains ZERO dependencies on Flutter or Firebase.
/// Explicit transition table:
///   scheduled -> taken | skipped | snoozed | missed
///   snoozed   -> taken | skipped | snoozed (max 3 snoozes, <= 60m window) | missed
///   missed    -> taken (only via explicit "I actually took it" correction, late: true)
///
/// Deterministic log IDs: {medicationId}_{scheduledEpochMinutes}
library dose_state_machine;

enum DoseState {
  scheduled,
  taken,
  skipped,
  snoozed,
  missed,
}

/// Typed exception thrown whenever an illegal state transition is attempted.
class IllegalDoseTransitionException implements Exception {
  final DoseState fromState;
  final DoseState toState;
  final String message;

  const IllegalDoseTransitionException({
    required this.fromState,
    required this.toState,
    required this.message,
  });

  @override
  String toString() =>
      'IllegalDoseTransitionException: Cannot transition from ${fromState.name} to ${toState.name}: $message';
}

/// Result of a validated dose transition.
class DoseTransitionResult {
  final DoseState fromState;
  final DoseState toState;
  final bool shouldDecrementInventory;
  final bool isLate;
  final int newSnoozeCount;
  final DateTime actionTime;
  final String? reason;

  const DoseTransitionResult({
    required this.fromState,
    required this.toState,
    required this.shouldDecrementInventory,
    this.isLate = false,
    this.newSnoozeCount = 0,
    required this.actionTime,
    this.reason,
  });
}

class DoseStateMachine {
  const DoseStateMachine._();

  static const int maxSnoozeLimit = 3;
  static const int missedThresholdMinutes = 60;

  /// Deterministic log identity mandated by capstone paper:
  /// {medicationId}_{scheduledEpochMinutes}
  /// Guarantees duplicate-proof offline replay and deterministic Firestore document IDs.
  static String generateLogId(String medicationId, DateTime scheduledTime) {
    final scheduledEpochMinutes =
        scheduledTime.millisecondsSinceEpoch ~/ (1000 * 60);
    return '${medicationId}_$scheduledEpochMinutes';
  }

  /// Validates and computes the transition from [currentState] to [targetState].
  /// Throws [IllegalDoseTransitionException] if the transition violates thesis rules.
  static DoseTransitionResult transition({
    required DoseState currentState,
    required DoseState targetState,
    required DateTime scheduledTime,
    required DateTime actionTime,
    int currentSnoozeCount = 0,
    bool isLateCorrection = false,
    String? reason,
  }) {
    final elapsedMinutes = actionTime.difference(scheduledTime).inMinutes;

    switch (currentState) {
      case DoseState.scheduled:
        if (targetState == DoseState.taken) {
          final isLate = elapsedMinutes > missedThresholdMinutes;
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: true,
            isLate: isLate,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.skipped) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.snoozed) {
          if (elapsedMinutes > missedThresholdMinutes) {
            throw IllegalDoseTransitionException(
              fromState: currentState,
              toState: targetState,
              message:
                  'Cannot snooze dose: 60-minute alarm acknowledgment window has expired ($elapsedMinutes minutes elapsed).',
            );
          }
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: 1,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.missed) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason ?? 'Unacknowledged 60 minutes after scheduled alarm',
          );
        }

        throw IllegalDoseTransitionException(
          fromState: currentState,
          toState: targetState,
          message: 'Unsupported target state from scheduled.',
        );

      case DoseState.snoozed:
        if (targetState == DoseState.taken) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: true,
            isLate: elapsedMinutes > missedThresholdMinutes,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.skipped) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.snoozed) {
          if (currentSnoozeCount >= maxSnoozeLimit) {
            throw IllegalDoseTransitionException(
              fromState: currentState,
              toState: targetState,
              message:
                  'Maximum snooze limit reached (maximum $maxSnoozeLimit snoozes allowed).',
            );
          }
          if (elapsedMinutes > missedThresholdMinutes) {
            throw IllegalDoseTransitionException(
              fromState: currentState,
              toState: targetState,
              message:
                  'Cannot snooze dose: cumulative duration exceeds the 60-minute unacknowledged window ($elapsedMinutes minutes elapsed).',
            );
          }
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: currentSnoozeCount + 1,
            actionTime: actionTime,
            reason: reason,
          );
        }

        if (targetState == DoseState.missed) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: false,
            isLate: false,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason ?? 'Snooze window expired past 60 minutes',
          );
        }

        throw IllegalDoseTransitionException(
          fromState: currentState,
          toState: targetState,
          message: 'Unsupported target state from snoozed.',
        );

      case DoseState.missed:
        if (targetState == DoseState.taken) {
          if (!isLateCorrection) {
            throw IllegalDoseTransitionException(
              fromState: currentState,
              toState: targetState,
              message:
                  'A missed dose can only transition to taken via an explicit "I actually took it" correction.',
            );
          }
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory: true,
            isLate: true,
            newSnoozeCount: currentSnoozeCount,
            actionTime: actionTime,
            reason: reason ?? 'Explicit late correction ("I actually took it")',
          );
        }

        throw IllegalDoseTransitionException(
          fromState: currentState,
          toState: targetState,
          message:
              'Missed doses cannot be snoozed or skipped; only explicit late taken is permitted.',
        );

      case DoseState.taken:
        // Undo taken action: restores stock exactly once, reverting to scheduled state
        if (targetState == DoseState.scheduled) {
          return DoseTransitionResult(
            fromState: currentState,
            toState: targetState,
            shouldDecrementInventory:
                false, // Undo will increment stock separately
            isLate: false,
            newSnoozeCount: 0,
            actionTime: actionTime,
            reason: reason ?? 'Undo taken action',
          );
        }

        throw IllegalDoseTransitionException(
          fromState: currentState,
          toState: targetState,
          message:
              'Taken is a completed state and cannot transition to ${targetState.name}.',
        );

      case DoseState.skipped:
        throw IllegalDoseTransitionException(
          fromState: currentState,
          toState: targetState,
          message:
              'Skipped is a terminal state and cannot transition to ${targetState.name}.',
        );
    }
  }

  /// Determines if an unacknowledged scheduled dose has crossed the 60-minute window
  /// and should be automatically reconciled to missed.
  static bool shouldAutoReconcileToMissed({
    required DateTime scheduledTime,
    required DateTime currentTime,
    required bool hasExistingLog,
  }) {
    if (hasExistingLog) return false;
    final elapsedMinutes = currentTime.difference(scheduledTime).inMinutes;
    return elapsedMinutes >= missedThresholdMinutes;
  }
}
