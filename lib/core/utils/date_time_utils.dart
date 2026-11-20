import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TimeBucket { morning, afternoon, evening, night }

/// Utility class for medication time formatting, bucket calculation, and interval math.
class DateTimeUtils {
  const DateTimeUtils._();

  /// Parses [DateTime], Firestore [Timestamp], epoch milliseconds, map representations,
  /// or ISO-8601 strings safely without throwing [TypeError].
  static DateTime? tryParseFlexibleDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is num) {
        final nanos = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
        final extraMs = nanos is num ? (nanos / 1000000).round() : 0;
        return DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000 + extraMs,
        );
      }
    }
    return null;
  }

  /// Determine time of day grouping for schedule presentation:
  /// Morning: 05:00 - 11:59
  /// Afternoon: 12:00 - 16:59
  /// Evening: 17:00 - 20:59
  /// Night: 21:00 - 04:59
  static TimeBucket getTimeBucket(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    if (minutes >= 5 * 60 && minutes < 12 * 60) {
      return TimeBucket.morning;
    } else if (minutes >= 12 * 60 && minutes < 17 * 60) {
      return TimeBucket.afternoon;
    } else if (minutes >= 17 * 60 && minutes < 21 * 60) {
      return TimeBucket.evening;
    } else {
      return TimeBucket.night;
    }
  }

  /// Format TimeOfDay based on 12-hour or 24-hour setting
  static String formatTimeOfDay(TimeOfDay time, {bool is24Hour = false}) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return is24Hour
        ? DateFormat('HH:mm').format(dt)
        : DateFormat('h:mm a').format(dt);
  }

  /// Human-readable relative countdown to scheduled time
  static String formatCountdown(DateTime target) {
    final now = DateTime.now();
    final difference = target.difference(now);

    if (difference.isNegative) {
      final elapsed = difference.abs();
      if (elapsed.inMinutes < 60) {
        return '${elapsed.inMinutes}m ago';
      }
      return '${elapsed.inHours}h ${elapsed.inMinutes % 60}m ago';
    }

    if (difference.inMinutes < 60) {
      return 'in ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'in ${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      return 'in ${difference.inDays}d';
    }
  }
}
