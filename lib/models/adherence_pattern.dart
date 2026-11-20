import '../core/utils/date_time_utils.dart';

/// Statistical summary of missed dose occurrences across time-of-day slots and weekdays.
class MissedDosePattern {
  final Map<TimeBucket, int> timeOfDayCounts;
  final Map<int, int> dayOfWeekCounts;
  final int totalMissed;
  final int totalScheduled;
  final String insightSentence;

  const MissedDosePattern({
    required this.timeOfDayCounts,
    required this.dayOfWeekCounts,
    required this.totalMissed,
    required this.totalScheduled,
    required this.insightSentence,
  });

  int get morningMissed => timeOfDayCounts[TimeBucket.morning] ?? 0;
  int get afternoonMissed => timeOfDayCounts[TimeBucket.afternoon] ?? 0;
  int get eveningMissed => timeOfDayCounts[TimeBucket.evening] ?? 0;
  int get nightMissed => timeOfDayCounts[TimeBucket.night] ?? 0;
}
