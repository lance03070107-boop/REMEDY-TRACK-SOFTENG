import 'package:flutter/foundation.dart';
import '../core/utils/date_time_utils.dart';

enum ScheduleFrequency {
  daily,
  specificWeekdays,
  everyXHours,
  everyXDays,
  cycleBased,
}

/// Comprehensive scheduling specification for recurring doses.
@immutable
class DoseSchedule {
  static const Object _unset = Object();

  final ScheduleFrequency frequency;
  final List<String> timesOfDay; // Format: "HH:mm" (24h)
  final List<int> weekdays; // 1 = Mon, 7 = Sun
  final int? intervalValue; // X hours or X days
  final int? cycleActiveDays; // e.g. 21 days on
  final int? cycleRestDays; // e.g. 7 days off
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? updatedAt;
  final String? alarmSoundId;
  final String? customSoundPath;
  final bool? vibrationEnabled;

  const DoseSchedule({
    required this.frequency,
    required this.timesOfDay,
    this.weekdays = const [],
    this.intervalValue,
    this.cycleActiveDays,
    this.cycleRestDays,
    required this.startDate,
    this.endDate,
    this.updatedAt,
    this.alarmSoundId,
    this.customSoundPath,
    this.vibrationEnabled,
  });

  DoseSchedule copyWith({
    ScheduleFrequency? frequency,
    List<String>? timesOfDay,
    List<int>? weekdays,
    Object? intervalValue = _unset,
    Object? cycleActiveDays = _unset,
    Object? cycleRestDays = _unset,
    DateTime? startDate,
    Object? endDate = _unset,
    Object? updatedAt = _unset,
    Object? alarmSoundId = _unset,
    Object? customSoundPath = _unset,
    Object? vibrationEnabled = _unset,
    bool clearIntervalValue = false,
    bool clearCycleActiveDays = false,
    bool clearCycleRestDays = false,
    bool clearEndDate = false,
    bool clearUpdatedAt = false,
    bool clearAlarmSoundId = false,
    bool clearCustomSoundPath = false,
    bool clearVibrationEnabled = false,
  }) {
    return DoseSchedule(
      frequency: frequency ?? this.frequency,
      timesOfDay: timesOfDay != null
          ? List<String>.unmodifiable(timesOfDay)
          : List<String>.unmodifiable(this.timesOfDay),
      weekdays: weekdays != null
          ? List<int>.unmodifiable(weekdays)
          : List<int>.unmodifiable(this.weekdays),
      intervalValue: clearIntervalValue
          ? null
          : (identical(intervalValue, _unset)
              ? this.intervalValue
              : intervalValue as int?),
      cycleActiveDays: clearCycleActiveDays
          ? null
          : (identical(cycleActiveDays, _unset)
              ? this.cycleActiveDays
              : cycleActiveDays as int?),
      cycleRestDays: clearCycleRestDays
          ? null
          : (identical(cycleRestDays, _unset)
              ? this.cycleRestDays
              : cycleRestDays as int?),
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate
          ? null
          : (identical(endDate, _unset) ? this.endDate : endDate as DateTime?),
      updatedAt: clearUpdatedAt
          ? null
          : (identical(updatedAt, _unset)
              ? this.updatedAt
              : updatedAt as DateTime?),
      alarmSoundId: clearAlarmSoundId
          ? null
          : (identical(alarmSoundId, _unset)
              ? this.alarmSoundId
              : alarmSoundId as String?),
      customSoundPath: clearCustomSoundPath
          ? null
          : (identical(customSoundPath, _unset)
              ? this.customSoundPath
              : customSoundPath as String?),
      vibrationEnabled: clearVibrationEnabled
          ? null
          : (identical(vibrationEnabled, _unset)
              ? this.vibrationEnabled
              : vibrationEnabled as bool?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frequency': frequency.name,
      'timesOfDay': List<String>.unmodifiable(timesOfDay),
      'weekdays': List<int>.unmodifiable(weekdays),
      'intervalValue': intervalValue,
      'cycleActiveDays': cycleActiveDays,
      'cycleRestDays': cycleRestDays,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'alarmSoundId': alarmSoundId,
      'customSoundPath': customSoundPath,
      'vibrationEnabled': vibrationEnabled,
    };
  }

  factory DoseSchedule.fromJson(Map<String, dynamic> json) {
    return DoseSchedule(
      frequency: ScheduleFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
        orElse: () => ScheduleFrequency.daily,
      ),
      timesOfDay: List<String>.unmodifiable(
        (json['timesOfDay'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['08:00'],
      ),
      weekdays: List<int>.unmodifiable(
        (json['weekdays'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
      ),
      intervalValue: (json['intervalValue'] as num?)?.toInt(),
      cycleActiveDays: (json['cycleActiveDays'] as num?)?.toInt(),
      cycleRestDays: (json['cycleRestDays'] as num?)?.toInt(),
      startDate: DateTimeUtils.tryParseFlexibleDateTime(json['startDate']) ??
          DateTime.now(),
      endDate: DateTimeUtils.tryParseFlexibleDateTime(json['endDate']),
      updatedAt: DateTimeUtils.tryParseFlexibleDateTime(json['updatedAt']),
      alarmSoundId: json['alarmSoundId'] as String?,
      customSoundPath: json['customSoundPath'] as String?,
      vibrationEnabled: json['vibrationEnabled'] as bool?,
    );
  }
}
