import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import '../../models/dose_schedule.dart';
import '../../models/medication.dart';
import '../../services/alarm_id_generator.dart';

/// Representation of a concrete scheduled dose occurrence.
@immutable
class ScheduledDoseOccurrence {
  final Medication medication;
  final DateTime scheduledDateTime;
  final int timeIndex;
  final int notificationId;

  const ScheduledDoseOccurrence({
    required this.medication,
    required this.scheduledDateTime,
    required this.timeIndex,
    required this.notificationId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledDoseOccurrence &&
          runtimeType == other.runtimeType &&
          medication.id == other.medication.id &&
          scheduledDateTime == other.scheduledDateTime &&
          timeIndex == other.timeIndex &&
          notificationId == other.notificationId;

  @override
  int get hashCode =>
      medication.id.hashCode ^
      scheduledDateTime.hashCode ^
      timeIndex.hashCode ^
      notificationId.hashCode;

  @override
  String toString() =>
      'ScheduledDoseOccurrence(${medication.name}, $scheduledDateTime, slot=$timeIndex, notifId=$notificationId)';
}

/// Pure-Dart single source of truth for schedule mathematical expansion.
///
/// Guarantees:
/// 1. Strict date-only UTC comparisons to prevent DST (Daylight Saving Time) shifts.
/// 2. Strict enforcement of `startDate` (future starts are never scheduled prematurely).
/// 3. Strict enforcement of `endDate` (boundary midnight comparison).
/// 4. Safe time-of-day parsing with boundary validation (00:00 - 23:59).
/// 5. Full support for daily, specificWeekdays, everyXDays, cycleBased, and everyXHours frequencies.
class ScheduleExpander {
  const ScheduleExpander._();

  /// Safely parses an "HH:mm" 24-hour string into hour and minute components.
  /// Returns null if format or values are invalid.
  static (int, int)? parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return (hour, minute);
    } catch (e, s) {
      AppLogger.w('Failed to parse time string: $e',
          tag: 'ScheduleExpander', error: e, stackTrace: s);
      return null;
    }
  }

  /// Checks whether a medication's schedule falls on the specified calendar date.
  /// Performs date-only UTC arithmetic to eliminate DST and timezone offset anomalies.
  static bool isScheduledOnDate(DoseSchedule schedule, DateTime date) {
    final startUtc = DateTime.utc(
      schedule.startDate.year,
      schedule.startDate.month,
      schedule.startDate.day,
    );
    final targetUtc = DateTime.utc(
      date.year,
      date.month,
      date.day,
    );

    // Rule: Never scheduled before the start date
    if (targetUtc.isBefore(startUtc)) {
      return false;
    }

    // Rule: Never scheduled after the end date
    if (schedule.endDate != null) {
      final endUtc = DateTime.utc(
        schedule.endDate!.year,
        schedule.endDate!.month,
        schedule.endDate!.day,
      );
      if (targetUtc.isAfter(endUtc)) {
        return false;
      }
    }

    switch (schedule.frequency) {
      case ScheduleFrequency.daily:
      case ScheduleFrequency.everyXHours:
        return true;

      case ScheduleFrequency.specificWeekdays:
        return schedule.weekdays.contains(date.weekday);

      case ScheduleFrequency.everyXDays:
        final interval = schedule.intervalValue ?? 1;
        if (interval <= 0) return true;
        final diffDays = targetUtc.difference(startUtc).inDays;
        return diffDays >= 0 && (diffDays % interval == 0);

      case ScheduleFrequency.cycleBased:
        final active = schedule.cycleActiveDays ?? 21;
        final rest = schedule.cycleRestDays ?? 7;
        final totalCycle = active + rest;
        if (totalCycle <= 0) return false;
        final diffDays = targetUtc.difference(startUtc).inDays;
        if (diffDays < 0) return false;
        final dayInCycle = diffDays % totalCycle;
        return dayInCycle < active;
    }
  }

  /// Expands the effective daily time-of-day strings for a schedule.
  ///
  /// For [ScheduleFrequency.everyXHours], if only a single anchor start time
  /// (or none) is stored in [DoseSchedule.timesOfDay], generates all 24-hour
  /// slots separated by [DoseSchedule.intervalValue] hours. If the caller
  /// already supplied multiple explicit times, preserves them verbatim.
  static List<String> effectiveTimesOfDay(DoseSchedule schedule) {
    if (schedule.frequency != ScheduleFrequency.everyXHours) {
      return schedule.timesOfDay;
    }
    if (schedule.timesOfDay.length > 1) {
      return schedule.timesOfDay;
    }
    final anchorStr =
        schedule.timesOfDay.isNotEmpty ? schedule.timesOfDay.first : '08:00';
    final anchor = parseTimeOfDay(anchorStr) ?? (8, 0);
    final intervalHours = (schedule.intervalValue ?? 4).clamp(1, 24);
    final anchorMinutes = anchor.$1 * 60 + anchor.$2;
    final generated = <String>{};
    for (int step = 0; step * intervalHours < 24; step++) {
      final totalMinutes = (anchorMinutes + step * intervalHours * 60) % 1440;
      final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
      final m = (totalMinutes % 60).toString().padLeft(2, '0');
      generated.add('$h:$m');
    }
    final sorted = generated.toList()..sort();
    return sorted;
  }

  /// Expands all concrete dose occurrences for a [Medication] between [start] and [end].
  /// Doses scheduled before [start] or after [end] are excluded.
  static List<ScheduledDoseOccurrence> expandOccurrences({
    required Medication medication,
    required DateTime start,
    required DateTime end,
    DateTime? createdAfter,
  }) {
    if (!medication.isActive ||
        medication.isPrn ||
        medication.schedule == null) {
      return const [];
    }

    final schedule = medication.schedule!;
    final effectiveTimes = effectiveTimesOfDay(schedule);
    final List<ScheduledDoseOccurrence> occurrences = [];

    // Date range boundaries (date-only)
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);

    while (!cursor.isAfter(lastDay)) {
      if (isScheduledOnDate(schedule, cursor)) {
        for (int tIdx = 0; tIdx < effectiveTimes.length; tIdx++) {
          final parsed = parseTimeOfDay(effectiveTimes[tIdx]);
          if (parsed == null) continue;

          final doseDateTime = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            parsed.$1,
            parsed.$2,
          );

          // Must be within [start, end] window
          if (doseDateTime.isBefore(start) || doseDateTime.isAfter(end)) {
            continue;
          }

          // If a creation anchor is provided, never generate doses before it
          if (createdAfter != null && doseDateTime.isBefore(createdAfter)) {
            continue;
          }

          final notifId = AlarmIdGenerator.generateDoseAlarmId(
            medicationId: medication.id,
            scheduledDateTime: doseDateTime,
            timeIndex: tIdx,
          );

          occurrences.add(
            ScheduledDoseOccurrence(
              medication: medication,
              scheduledDateTime: doseDateTime,
              timeIndex: tIdx,
              notificationId: notifId,
            ),
          );
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    occurrences
        .sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
    return occurrences;
  }

  /// Convenience method for retrieving theoretical DateTime occurrences in range.
  /// Used by reconcilers and history projectors.
  static List<DateTime> getOccurrencesInRange({
    required DoseSchedule schedule,
    required DateTime start,
    required DateTime end,
    DateTime? createdAfter,
  }) {
    final List<DateTime> result = [];
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);

    final effectiveTimes = effectiveTimesOfDay(schedule);
    while (!cursor.isAfter(lastDay)) {
      if (isScheduledOnDate(schedule, cursor)) {
        for (final timeStr in effectiveTimes) {
          final parsed = parseTimeOfDay(timeStr);
          if (parsed == null) continue;

          final occurrence = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            parsed.$1,
            parsed.$2,
          );

          if (occurrence.isAfter(start) && occurrence.isBefore(end)) {
            if (createdAfter == null || !occurrence.isBefore(createdAfter)) {
              result.add(occurrence);
            }
          }
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    result.sort();
    return result;
  }
}
