import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/date_time_utils.dart';
import 'dose_schedule.dart';
import 'medication.dart';

/// Immutable model representing medication stock, thresholds, and refill metadata.
@immutable
class InventoryItem {
  static const Object _unset = Object();

  final String id;
  final String userId;
  final String medicationId;
  final double currentStock;
  final String
      unit; // 'tablets', 'capsules', 'mL', 'doses', 'drops', 'puffs', 'applications'
  final double lowStockThreshold;
  final double refillQuantity;
  final DateTime? lastRefillDate;
  final String? notes;

  const InventoryItem({
    required this.id,
    required this.userId,
    required this.medicationId,
    required this.currentStock,
    this.unit = 'tablets',
    this.lowStockThreshold = 7.0,
    this.refillQuantity = 30.0,
    this.lastRefillDate,
    this.notes,
  });

  bool get isLowStock => currentStock <= lowStockThreshold;

  /// Estimate days remaining based on daily expected consumption.
  int? estimatedDaysRemaining(double dailyConsumption) {
    if (dailyConsumption <= 0 || currentStock <= 0) return null;
    return (currentStock / dailyConsumption).floor();
  }

  /// Estimates days of supply remaining for [medication] using the single source of truth
  /// [calculateDailyPrescribedRate]. Returns null for PRN or non-auto-decrementing forms
  /// (syrup, injection, drops, inhaler, topical).
  int? estimatedDaysRemainingForMedication(Medication? medication) {
    if (medication == null || medication.isPrn || medication.schedule == null) {
      return null;
    }
    if (medication.form != MedicationForm.tablet &&
        medication.form != MedicationForm.capsule) {
      return null;
    }
    final dailyRate = calculateDailyPrescribedRate(medication);
    if (dailyRate <= 0) return null;
    if (currentStock <= 0) return 0;
    return (currentStock / dailyRate).floor();
  }

  /// Calculates the projected calendar refill date based on the paper's formula:
  /// projected refill date = remaining count / total daily prescribed intake.
  /// Correctly handles multi-dose and variable schedules, excluding PRN and manual-decrement medications.
  DateTime? calculateProjectedRefillDate(Medication? medication,
      {DateTime? fromDate}) {
    if (medication == null || medication.isPrn || medication.schedule == null) {
      return null;
    }
    if (medication.form != MedicationForm.tablet &&
        medication.form != MedicationForm.capsule) {
      return null;
    }
    if (currentStock <= 0) return fromDate ?? DateTime.now();

    final dailyRate = calculateDailyPrescribedRate(medication);
    if (dailyRate <= 0) return null;

    final daysRemaining = (currentStock / dailyRate).floor();
    final base = fromDate ?? DateTime.now();
    return base.add(Duration(days: daysRemaining));
  }

  /// Deterministically computes total daily prescribed intake based on schedule frequency.
  static double calculateDailyPrescribedRate(Medication medication) {
    if (medication.isPrn ||
        !medication.isActive ||
        medication.schedule == null) {
      return 0.0;
    }
    final schedule = medication.schedule!;
    switch (schedule.frequency) {
      case ScheduleFrequency.daily:
        return schedule.timesOfDay.length * medication.doseAmount;
      case ScheduleFrequency.specificWeekdays:
        if (schedule.weekdays.isEmpty) return 0.0;
        return (schedule.timesOfDay.length *
                medication.doseAmount *
                schedule.weekdays.length) /
            7.0;
      case ScheduleFrequency.everyXDays:
        final interval = schedule.intervalValue ?? 1;
        if (interval <= 0) return 0.0;
        return (schedule.timesOfDay.length * medication.doseAmount) / interval;
      case ScheduleFrequency.cycleBased:
        final activeDays = schedule.cycleActiveDays ?? 21;
        final restDays = schedule.cycleRestDays ?? 7;
        final total = activeDays + restDays;
        if (total <= 0) return 0.0;
        return (schedule.timesOfDay.length *
                medication.doseAmount *
                activeDays) /
            total;
      case ScheduleFrequency.everyXHours:
        final hours = schedule.intervalValue ?? 4;
        if (hours <= 0) return 0.0;
        return (24.0 / hours) * medication.doseAmount;
    }
  }

  InventoryItem copyWith({
    String? id,
    String? userId,
    String? medicationId,
    double? currentStock,
    String? unit,
    double? lowStockThreshold,
    double? refillQuantity,
    Object? lastRefillDate = _unset,
    Object? notes = _unset,
    bool clearLastRefillDate = false,
    bool clearNotes = false,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      medicationId: medicationId ?? this.medicationId,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      refillQuantity: refillQuantity ?? this.refillQuantity,
      lastRefillDate: clearLastRefillDate
          ? null
          : (identical(lastRefillDate, _unset)
              ? this.lastRefillDate
              : lastRefillDate as DateTime?),
      notes: clearNotes
          ? null
          : (identical(notes, _unset) ? this.notes : notes as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'medicationId': medicationId,
      'currentStock':
          currentStock.clamp(AppConstants.minStock, AppConstants.maxStock),
      'unit': unit,
      'lowStockThreshold': lowStockThreshold.clamp(
        AppConstants.minLowStockThreshold,
        AppConstants.maxLowStockThreshold,
      ),
      'refillQuantity':
          refillQuantity.clamp(AppConstants.minStock, AppConstants.maxStock),
      'lastRefillDate': lastRefillDate?.toIso8601String(),
      'notes': notes,
    };
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    final rawStock = (json['currentStock'] as num?)?.toDouble() ?? 0.0;
    final rawThreshold = (json['lowStockThreshold'] as num?)?.toDouble() ?? 7.0;
    final rawRefill = (json['refillQuantity'] as num?)?.toDouble() ?? 30.0;

    final safeStock = (rawStock.isNaN || rawStock.isInfinite) ? 0.0 : rawStock;
    final safeThreshold =
        (rawThreshold.isNaN || rawThreshold.isInfinite) ? 7.0 : rawThreshold;
    final safeRefill =
        (rawRefill.isNaN || rawRefill.isInfinite) ? 30.0 : rawRefill;

    return InventoryItem(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      medicationId: json['medicationId'] as String? ?? '',
      currentStock:
          safeStock.clamp(AppConstants.minStock, AppConstants.maxStock),
      unit: json['unit'] as String? ?? 'tablets',
      lowStockThreshold: safeThreshold.clamp(
        AppConstants.minLowStockThreshold,
        AppConstants.maxLowStockThreshold,
      ),
      refillQuantity:
          safeRefill.clamp(AppConstants.minStock, AppConstants.maxStock),
      lastRefillDate:
          DateTimeUtils.tryParseFlexibleDateTime(json['lastRefillDate']),
      notes: json['notes'] as String?,
    );
  }
}
