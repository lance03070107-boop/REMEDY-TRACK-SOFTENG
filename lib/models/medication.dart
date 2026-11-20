import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/date_time_utils.dart';
import 'dose_schedule.dart';

enum MedicationForm {
  tablet,
  capsule,
  syrup,
  injection,
  drops,
  inhaler,
  topical,
}

/// Core medication entity containing clinical details, PRN constraints, and schedule.
@immutable
class Medication {
  static const Object _unset = Object();

  final String id;
  final String userId;
  final String name;
  final String genericName;
  final String strength;
  final MedicationForm form;
  final double doseAmount;
  final String instructions; // e.g. "Take after meals"
  final String? notes;
  final int colorTag; // Hex value for UI accent
  final String iconTag; // Identifier for medication icon
  final bool isPrn; // As-Needed medication
  final bool isActive;
  final int? minIntervalHours; // PRN safe minimum gap
  final double? dailyMaxDose; // PRN maximum allowed in 24h
  final DoseSchedule? schedule;
  final String alarmSoundId;
  final String? customSoundPath;
  final bool vibrationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Medication({
    required this.id,
    required this.userId,
    required this.name,
    this.genericName = '',
    required this.strength,
    required this.form,
    required this.doseAmount,
    this.instructions = '',
    this.notes,
    this.colorTag = 0xFF1E66F5,
    this.iconTag = 'pill',
    this.isPrn = false,
    this.isActive = true,
    this.minIntervalHours,
    this.dailyMaxDose,
    this.schedule,
    this.alarmSoundId = AppConstants.defaultAlarmSound,
    this.customSoundPath,
    this.vibrationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Medication copyWith({
    String? id,
    String? userId,
    String? name,
    String? genericName,
    String? strength,
    MedicationForm? form,
    double? doseAmount,
    String? instructions,
    Object? notes = _unset,
    int? colorTag,
    String? iconTag,
    bool? isPrn,
    bool? isActive,
    Object? minIntervalHours = _unset,
    Object? dailyMaxDose = _unset,
    Object? schedule = _unset,
    String? alarmSoundId,
    Object? customSoundPath = _unset,
    bool? vibrationEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearNotes = false,
    bool clearMinIntervalHours = false,
    bool clearDailyMaxDose = false,
    bool clearSchedule = false,
    bool clearCustomSoundPath = false,
  }) {
    return Medication(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      genericName: genericName ?? this.genericName,
      strength: strength ?? this.strength,
      form: form ?? this.form,
      doseAmount: doseAmount ?? this.doseAmount,
      instructions: instructions ?? this.instructions,
      notes: clearNotes
          ? null
          : (identical(notes, _unset) ? this.notes : notes as String?),
      colorTag: colorTag ?? this.colorTag,
      iconTag: iconTag ?? this.iconTag,
      isPrn: isPrn ?? this.isPrn,
      isActive: isActive ?? this.isActive,
      minIntervalHours: clearMinIntervalHours
          ? null
          : (identical(minIntervalHours, _unset)
              ? this.minIntervalHours
              : minIntervalHours as int?),
      dailyMaxDose: clearDailyMaxDose
          ? null
          : (identical(dailyMaxDose, _unset)
              ? this.dailyMaxDose
              : dailyMaxDose as double?),
      schedule: clearSchedule
          ? null
          : (identical(schedule, _unset)
              ? this.schedule
              : schedule as DoseSchedule?),
      alarmSoundId: alarmSoundId ?? this.alarmSoundId,
      customSoundPath: clearCustomSoundPath
          ? null
          : (identical(customSoundPath, _unset)
              ? this.customSoundPath
              : customSoundPath as String?),
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'genericName': genericName,
      'strength': strength,
      'form': form.name,
      'doseAmount': doseAmount,
      'instructions': instructions,
      'notes': notes,
      'colorTag': colorTag,
      'iconTag': iconTag,
      'isPrn': isPrn,
      'isActive': isActive,
      'minIntervalHours': minIntervalHours,
      'dailyMaxDose': dailyMaxDose,
      'schedule': schedule?.toJson(),
      'alarmSoundId': alarmSoundId,
      'customSoundPath': customSoundPath,
      'vibrationEnabled': vibrationEnabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String,
      genericName: json['genericName'] as String? ?? '',
      strength: json['strength'] as String? ?? '',
      form: MedicationForm.values.firstWhere(
        (e) => e.name == json['form'],
        orElse: () => MedicationForm.tablet,
      ),
      doseAmount: (json['doseAmount'] as num?)?.toDouble() ?? 1.0,
      instructions: json['instructions'] as String? ?? '',
      notes: json['notes'] as String?,
      colorTag: (json['colorTag'] as num?)?.toInt() ?? 0xFF1E66F5,
      iconTag: json['iconTag'] as String? ?? 'pill',
      isPrn: json['isPrn'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      minIntervalHours: (json['minIntervalHours'] as num?)?.toInt(),
      dailyMaxDose: (json['dailyMaxDose'] as num?)?.toDouble(),
      schedule: json['schedule'] != null
          ? DoseSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
          : null,
      alarmSoundId:
          json['alarmSoundId'] as String? ?? AppConstants.defaultAlarmSound,
      customSoundPath: json['customSoundPath'] as String?,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      createdAt: DateTimeUtils.tryParseFlexibleDateTime(json['createdAt']) ??
          DateTime.now(),
      updatedAt: DateTimeUtils.tryParseFlexibleDateTime(json['updatedAt']) ??
          DateTime.now(),
    );
  }
}
