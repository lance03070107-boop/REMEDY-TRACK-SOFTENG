import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Centralized time & date formatting utility respecting 12h/24h user preferences,
/// Filipino/English date formats, and localized relative time displays.
class TimeFormatter {
  const TimeFormatter._();

  /// Formats a [DateTime] into a localized time string (e.g. "8:30 AM" or "08:30").
  static String formatTime(DateTime dateTime, {bool is24Hour = false}) {
    if (is24Hour) {
      return DateFormat('HH:mm').format(dateTime);
    }
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Formats a [TimeOfDay] into a localized time string.
  static String formatTimeOfDay(TimeOfDay time, {bool is24Hour = false}) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return formatTime(dt, is24Hour: is24Hour);
  }

  /// Formats a time string in "HH:mm" format (e.g. "08:00") respecting 12h/24h format.
  static String formatTimeString(String hhmm, {bool is24Hour = false}) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return formatTimeOfDay(TimeOfDay(hour: hour, minute: minute),
        is24Hour: is24Hour);
  }

  /// Formats a date for calendar or card headers (e.g. "Today, Oct 18", "Monday, Oct 18").
  static String formatFriendlyDate(DateTime date,
      {bool includeDayOfWeek = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diffDays = target.difference(today).inDays;

    String prefix;
    if (diffDays == 0) {
      prefix = 'Today';
    } else if (diffDays == -1) {
      prefix = 'Yesterday';
    } else if (diffDays == 1) {
      prefix = 'Tomorrow';
    } else if (includeDayOfWeek) {
      prefix = DateFormat('EEEE').format(date);
    } else {
      prefix = '';
    }

    final datePart = DateFormat('MMM d').format(date);
    return prefix.isNotEmpty ? '$prefix, $datePart' : datePart;
  }
}
