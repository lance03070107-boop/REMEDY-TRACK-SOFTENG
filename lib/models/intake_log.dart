import 'package:flutter/foundation.dart';
import '../core/state/dose_state_machine.dart';
import '../core/utils/app_logger.dart';
import '../services/crashlytics_service.dart';

enum DoseStatus {
  taken,
  late,
  missed,
  skipped,
  snoozed,
  pending,
}

/// Immutable record of a scheduled or logged intake event.
@immutable
class IntakeLog {
  final String id;
  final String userId;
  final String medicationId;
  final String medicationName;
  final double doseAmount;
  final DateTime scheduledTime;
  final DateTime? recordedTime;
  final DoseStatus status;
  final DateTime? snoozeUntil;
  final int snoozeCount;
  final String? notes;
  final bool isPrn;

  const IntakeLog({
    required this.id,
    required this.userId,
    required this.medicationId,
    required this.medicationName,
    required this.doseAmount,
    required this.scheduledTime,
    this.recordedTime,
    this.status = DoseStatus.pending,
    this.snoozeUntil,
    this.snoozeCount = 0,
    this.notes,
    this.isPrn = false,
  });

  /// Generates the deterministic, duplicate-proof log document ID mandated by the paper:
  /// {medicationId}_{scheduledEpochMinutes}
  static String generateIdempotentId({
    required String userId,
    required String medicationId,
    required DateTime scheduledTime,
    bool isPrn = false,
  }) {
    if (isPrn) {
      return '${medicationId}_prn_${scheduledTime.millisecondsSinceEpoch}';
    }
    return DoseStateMachine.generateLogId(medicationId, scheduledTime);
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    try {
      // Handles Cloud Firestore Timestamp without coupling model to cloud_firestore
      return ((raw as dynamic).toDate() as DateTime).toLocal();
    } catch (e, s) {
      AppLogger.w('Failed to parse IntakeLog timestamp (${raw.runtimeType})',
          tag: 'IntakeLog', error: e, stackTrace: s);
      return null;
    }
  }

  IntakeLog copyWith({
    String? id,
    String? userId,
    String? medicationId,
    String? medicationName,
    double? doseAmount,
    DateTime? scheduledTime,
    DateTime? recordedTime,
    DoseStatus? status,
    DateTime? snoozeUntil,
    int? snoozeCount,
    String? notes,
    bool? isPrn,
  }) {
    return IntakeLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      medicationId: medicationId ?? this.medicationId,
      medicationName: medicationName ?? this.medicationName,
      doseAmount: doseAmount ?? this.doseAmount,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      recordedTime: recordedTime ?? this.recordedTime,
      status: status ?? this.status,
      snoozeUntil: snoozeUntil ?? this.snoozeUntil,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      notes: notes ?? this.notes,
      isPrn: isPrn ?? this.isPrn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'medicationId': medicationId,
      'medicationName': medicationName,
      'doseAmount': doseAmount,
      'scheduledTime': scheduledTime.toUtc().toIso8601String(),
      'recordedTime': recordedTime?.toUtc().toIso8601String(),
      'status': status.name,
      'snoozeUntil': snoozeUntil?.toUtc().toIso8601String(),
      'snoozeCount': snoozeCount,
      'notes': notes,
      'isPrn': isPrn,
    };
  }

  factory IntakeLog.fromJson(Map<String, dynamic> json) {
    final parsedSched = _parseDateTime(json['scheduledTime']);
    if (parsedSched == null) {
      final err = FormatException(
        'Missing or corrupted scheduledTime in IntakeLog (id: ${json['id']})',
      );
      CrashlyticsService.recordError(err, StackTrace.current);
      throw err;
    }

    return IntakeLog(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      medicationId: json['medicationId'] as String? ?? '',
      medicationName: json['medicationName'] as String? ?? '',
      doseAmount: (json['doseAmount'] as num?)?.toDouble() ?? 1.0,
      scheduledTime: parsedSched,
      recordedTime: _parseDateTime(json['recordedTime']),
      status: DoseStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DoseStatus.pending,
      ),
      snoozeUntil: _parseDateTime(json['snoozeUntil']),
      snoozeCount: (json['snoozeCount'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String?,
      isPrn: json['isPrn'] as bool? ?? false,
    );
  }
}
