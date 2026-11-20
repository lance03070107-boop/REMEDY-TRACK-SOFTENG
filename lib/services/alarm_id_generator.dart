/// Deterministic 31-bit FNV-1a hash generator for alarm and inventory notification IDs.
/// Guarantees that:
/// 1. The ID is completely deterministic for any given medication, date, and dose slot.
/// 2. Primary IDs and escalation IDs (+500,000) strictly remain within positive
///    32-bit signed integer limits (< 2,147,483,647) expected by Android NotificationManager
///    and iOS UNUserNotificationCenter.
/// 3. Cross-medication hash collision is minimized across calendar rolling windows.
class AlarmIdGenerator {
  const AlarmIdGenerator._();

  /// Constant offset added to primary alarm IDs to produce deterministic escalation alerts.
  /// Chosen as 1,000,000,000 so primary IDs ([1,000,000 .. 999,999,999]) and
  /// escalation IDs ([1,001,000,000 .. 1,999,999,999]) are 100% disjoint while
  /// remaining safely below Int32.MAX (2,147,483,647).
  static const int escalationOffset = 1000000000;

  static int _fnv1a32(String input) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x3FFFFFFF;
  }

  static int generateDoseAlarmId({
    required String medicationId,
    required DateTime scheduledDateTime,
    required int timeIndex,
  }) {
    final key =
        '$medicationId|${scheduledDateTime.year}-${scheduledDateTime.month}-${scheduledDateTime.day}|$timeIndex';

    // Range: [1,000,000 .. 999,999,999]
    // Completely disjoint from:
    // - Caregiver / general alerts: [10,000 .. 79,999]
    // - Tone preview: 88,888
    // - Low-stock alerts: [900,000 .. 999,999]
    // - Escalation dose alarms (+1,000,000,000): [1,001,000,000 .. 1,999,999,999]
    final positiveHash = _fnv1a32(key);
    return 1000000 + (positiveHash % 999000000);
  }

  /// Generates a stable, deterministic notification ID for low-stock alerts in range [900,000, 999,999].
  static int generateLowStockNotificationId(String inventoryOrMedicationId) {
    final positiveHash = _fnv1a32('low_stock|$inventoryOrMedicationId');
    return 900000 + (positiveHash % 100000);
  }

  /// Calculates the corresponding escalation notification ID for a primary alarm.
  static int getEscalationId(int primaryAlarmId) {
    return primaryAlarmId + escalationOffset;
  }

  /// Checks whether [notifId] is in the escalation alarm ID range.
  static bool isEscalationAlarmId(int notifId) {
    return notifId >= 1001000000;
  }

  /// Resolves the primary alarm ID regardless of whether [notifId] is primary or escalation.
  static int getPrimaryId(int notifId, {bool? isEscalation}) {
    if ((isEscalation ?? isEscalationAlarmId(notifId)) &&
        notifId > escalationOffset) {
      return notifId - escalationOffset;
    }
    return notifId;
  }
}
