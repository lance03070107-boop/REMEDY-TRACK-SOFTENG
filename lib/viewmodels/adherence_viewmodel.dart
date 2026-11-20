import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/utils/date_time_utils.dart';
import '../models/adherence_pattern.dart';
import '../models/intake_log.dart';
import '../models/medication.dart';
import '../repositories/intake_repository.dart';
import '../services/pdf_report_service.dart';

export '../models/adherence_pattern.dart';

class DailyAdherencePoint {
  final DateTime date;
  final int takenCount;
  final int totalScheduled;
  final double percentage;

  const DailyAdherencePoint({
    required this.date,
    required this.takenCount,
    required this.totalScheduled,
    required this.percentage,
  });
}

/// ViewModel computing adherence metrics, streaks, time-of-day missed-dose patterns,
/// day-of-week breakdowns, fl_chart datasets, and doctor PDF reports under thesis specifications.
class AdherenceViewModel extends ChangeNotifier {
  final PdfReportService _pdfReportService;
  final IntakeRepository? _intakeRepository;

  AdherenceViewModel({
    PdfReportService? pdfReportService,
    IntakeRepository? intakeRepository,
  })  : _pdfReportService = pdfReportService ?? PdfReportService(),
        _intakeRepository = intakeRepository;

  void resetState() {
    notifyListeners();
  }

  static int _statusPriority(DoseStatus status) {
    switch (status) {
      case DoseStatus.taken:
        return 5;
      case DoseStatus.late:
        return 4;
      case DoseStatus.skipped:
        return 3;
      case DoseStatus.snoozed:
        return 2;
      case DoseStatus.missed:
        return 1;
      case DoseStatus.pending:
        return 0;
    }
  }

  /// Selects the authoritative log when multiple logs exist for the same medicationId + scheduled minute
  /// (e.g., legacy server-synthesized duplicate vs. client taken log).
  /// Preference order: taken > late > skipped > snoozed > missed > pending.
  static IntakeLog? selectPreferredLog(Iterable<IntakeLog> candidates) {
    IntakeLog? best;
    for (final candidate in candidates) {
      if (best == null) {
        best = candidate;
        continue;
      }
      final bestRank = _statusPriority(best.status);
      final candRank = _statusPriority(candidate.status);
      if (candRank > bestRank) {
        best = candidate;
      } else if (candRank == bestRank) {
        final bestRec = best.recordedTime;
        final candRec = candidate.recordedTime;
        if (candRec != null && (bestRec == null || candRec.isAfter(bestRec))) {
          best = candidate;
        }
      }
    }
    return best;
  }

  /// Deduplicates non-PRN logs sharing the same medicationId + scheduledTime minute,
  /// keeping the highest-priority status (taken/late > skipped > snoozed > missed > pending).
  static List<IntakeLog> deduplicateLogs(List<IntakeLog> logs) {
    final prnLogs = <IntakeLog>[];
    final grouped = <String, List<IntakeLog>>{};
    for (final log in logs) {
      if (log.isPrn) {
        prnLogs.add(log);
        continue;
      }
      final sched = log.scheduledTime;
      final key =
          '${log.medicationId}_${sched.year}_${sched.month}_${sched.day}_${sched.hour}_${sched.minute}';
      grouped.putIfAbsent(key, () => <IntakeLog>[]).add(log);
    }
    final deduped = <IntakeLog>[
      ...prnLogs,
      for (final group in grouped.values) selectPreferredLog(group)!,
    ];
    return deduped;
  }

  /// Loads full un-truncated logs for a specific user and date range directly from repository.
  Future<List<IntakeLog>> loadLogsForDateRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    if (_intakeRepository == null) return [];
    return _intakeRepository!.getLogsForDateRange(userId, start, end);
  }

  /// Calculates Monthly Adherence Percentage as claimed in the capstone paper:
  /// Monthly Adherence % = (taken doses) / (total scheduled doses in the period) * 100.
  /// Excludes PRN (as-needed) and active snoozed doses.
  double calculateMonthlyAdherence(List<IntakeLog> logs,
      {DateTime? targetMonth}) {
    final now = targetMonth ?? DateTime.now();
    final monthLogs = deduplicateLogs(logs)
        .where((l) =>
            !l.isPrn &&
            l.status != DoseStatus.snoozed &&
            l.status != DoseStatus.pending &&
            l.scheduledTime.year == now.year &&
            l.scheduledTime.month == now.month)
        .toList();

    if (monthLogs.isEmpty) return 100.0;

    final takenCount = monthLogs
        .where(
            (l) => l.status == DoseStatus.taken || l.status == DoseStatus.late)
        .length;

    return (takenCount / monthLogs.length) * 100.0;
  }

  /// Returns true when at least one decisive scheduled (non-PRN) log exists in [logs].
  bool hasScheduledAdherenceData(List<IntakeLog> logs) {
    return deduplicateLogs(logs).any((l) =>
        !l.isPrn &&
        l.status != DoseStatus.snoozed &&
        l.status != DoseStatus.pending);
  }

  /// Calculates overall adherence rate percentage across all decisive scheduled logs.
  double calculateAdherenceRate(List<IntakeLog> logs) {
    final decisiveLogs = deduplicateLogs(logs)
        .where((l) =>
            !l.isPrn &&
            l.status != DoseStatus.snoozed &&
            l.status != DoseStatus.pending)
        .toList();
    if (decisiveLogs.isEmpty) return 100.0;

    final compliantCount = decisiveLogs
        .where(
            (l) => l.status == DoseStatus.taken || l.status == DoseStatus.late)
        .length;

    return (compliantCount / decisiveLogs.length) * 100.0;
  }

  /// Calculates consecutive day streak of 100% adherence (up to 30 days lookback).
  /// When [todayExpectedCount] is supplied, Today is credited only after all expected
  /// scheduled doses for Today have been taken/completed.
  int calculateStreakDays(List<IntakeLog> logs, {int? todayExpectedCount}) {
    final scheduledLogs =
        deduplicateLogs(logs).where((l) => !l.isPrn).toList();
    if (scheduledLogs.isEmpty) return 0;

    final now = DateTime.now();
    int streak = 0;

    for (int dayOffset = 0; dayOffset < 30; dayOffset++) {
      final targetDate = DateTime(now.year, now.month, now.day - dayOffset);
      final dayLogs = scheduledLogs.where((l) {
        return l.scheduledTime.year == targetDate.year &&
            l.scheduledTime.month == targetDate.month &&
            l.scheduledTime.day == targetDate.day;
      }).toList();

      if (dayLogs.isEmpty) {
        continue; // Day with no scheduled doses doesn't break streak
      }

      final hasMissed = dayLogs.any((l) => l.status == DoseStatus.missed);
      if (hasMissed) {
        break; // Streak broken
      }

      final hasPendingOrSnoozed = dayLogs.any(
        (l) => l.status == DoseStatus.pending || l.status == DoseStatus.snoozed,
      );
      if (dayOffset == 0 &&
          (hasPendingOrSnoozed ||
              (todayExpectedCount != null &&
                  dayLogs.length < todayExpectedCount))) {
        // Today is still in progress: don't prematurely credit or break streak.
        continue;
      }

      final allTaken = dayLogs.every(
          (l) => l.status == DoseStatus.taken || l.status == DoseStatus.late);
      if (allTaken) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  /// Computes missed-dose pattern analysis grouped by time-of-day bucket and day-of-week
  /// across 30 or 90 day ranges. Generates a deterministic insight sentence.
  MissedDosePattern analyzeMissedDosePatterns(
    List<IntakeLog> logs, {
    int daysRange = 30,
    String? medicationId,
    DateTime? fromDate,
  }) {
    final end = fromDate ?? DateTime.now();
    final start = end.subtract(Duration(days: daysRange));

    final filteredLogs = deduplicateLogs(logs).where((l) {
      if (medicationId != null && l.medicationId != medicationId) return false;
      return l.scheduledTime.isAfter(start) && l.scheduledTime.isBefore(end);
    }).toList();

    final timeOfDayCounts = <TimeBucket, int>{
      TimeBucket.morning: 0,
      TimeBucket.afternoon: 0,
      TimeBucket.evening: 0,
      TimeBucket.night: 0,
    };

    final dayOfWeekCounts = <int, int>{
      1: 0, // Monday
      2: 0, // Tuesday
      3: 0, // Wednesday
      4: 0, // Thursday
      5: 0, // Friday
      6: 0, // Saturday
      7: 0, // Sunday
    };

    int totalMissed = 0;

    for (final log in filteredLogs) {
      if (log.status == DoseStatus.missed) {
        totalMissed++;
        final time = TimeOfDay.fromDateTime(log.scheduledTime);
        final bucket = DateTimeUtils.getTimeBucket(time);
        timeOfDayCounts[bucket] = (timeOfDayCounts[bucket] ?? 0) + 1;

        final weekday = log.scheduledTime.weekday;
        dayOfWeekCounts[weekday] = (dayOfWeekCounts[weekday] ?? 0) + 1;
      }
    }

    final insight = _generateDeterministicInsight(timeOfDayCounts, totalMissed);

    return MissedDosePattern(
      timeOfDayCounts: timeOfDayCounts,
      dayOfWeekCounts: dayOfWeekCounts,
      totalMissed: totalMissed,
      totalScheduled: filteredLogs.length,
      insightSentence: insight,
    );
  }

  /// Generates a purely deterministic insight sentence from statistical frequency.
  /// Strictly avoids any medical advice or diagnosis.
  static String _generateDeterministicInsight(
    Map<TimeBucket, int> timeCounts,
    int totalMissed,
  ) {
    if (totalMissed == 0) {
      return 'Great consistency: no missed doses recorded in this period.';
    }

    TimeBucket? highestBucket;
    int highestCount = -1;
    bool isTied = false;

    for (final entry in timeCounts.entries) {
      if (entry.value > highestCount) {
        highestCount = entry.value;
        highestBucket = entry.key;
        isTied = false;
      } else if (entry.value == highestCount && entry.value > 0) {
        isTied = true;
      }
    }

    if (highestBucket != null && highestCount > 0 && !isTied) {
      final name = highestBucket.name;
      return 'Most missed doses occur in the $name ($highestCount of $totalMissed).';
    }

    return 'Missed doses are distributed evenly across scheduled time slots ($totalMissed total missed).';
  }

  /// Generates the past 7 days adherence data points for fl_chart BarChart
  List<DailyAdherencePoint> getPast7DaysBreakdown(List<IntakeLog> logs) {
    return getDaysBreakdown(logs, days: 7);
  }

  /// Generates adherence data points for fl_chart for any arbitrary day range (e.g. 7, 30, 90).
  List<DailyAdherencePoint> getDaysBreakdown(List<IntakeLog> logs,
      {int days = 30}) {
    final now = DateTime.now();
    final List<DailyAdherencePoint> points = [];

    final dedupedLogs = deduplicateLogs(logs);
    for (int i = days - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      final dayLogs = dedupedLogs
          .where((l) =>
              !l.isPrn &&
              l.scheduledTime.year == date.year &&
              l.scheduledTime.month == date.month &&
              l.scheduledTime.day == date.day &&
              l.status != DoseStatus.snoozed &&
              l.status != DoseStatus.pending)
          .toList();

      if (dayLogs.isEmpty) {
        points.add(DailyAdherencePoint(
          date: date,
          takenCount: 0,
          totalScheduled: 0,
          percentage: 100.0,
        ));
      } else {
        final taken = dayLogs
            .where((l) =>
                l.status == DoseStatus.taken || l.status == DoseStatus.late)
            .length;
        final pct = (taken / dayLogs.length) * 100.0;
        points.add(DailyAdherencePoint(
          date: date,
          takenCount: taken,
          totalScheduled: dayLogs.length,
          percentage: pct,
        ));
      }
    }

    return points;
  }

  /// Exports Doctor-Ready PDF Report with embedded Missed-Dose Pattern Table
  Future<Uint8List> exportReportPdf({
    required String patientName,
    required String patientEmail,
    required List<Medication> medications,
    required List<IntakeLog> logs,
  }) async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 30));
    final adherenceRate = calculateAdherenceRate(logs);
    final pattern = analyzeMissedDosePatterns(logs, daysRange: 30);

    final pdfBytes = await _pdfReportService.generateDoctorReport(
      patientName: patientName,
      patientEmail: patientEmail,
      adherencePercentage: adherenceRate,
      medications: medications,
      logs: logs,
      startDate: startDate,
      endDate: now,
      pattern: pattern,
    );

    await _pdfReportService.printOrShareReport(
      pdfBytes,
      'RemedyTrack_Adherence_Report_${now.millisecondsSinceEpoch}.pdf',
    );

    return pdfBytes;
  }
}
