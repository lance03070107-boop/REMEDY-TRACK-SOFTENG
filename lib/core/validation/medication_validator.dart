import 'package:flutter/services.dart';
import '../../models/dose_schedule.dart';
import '../../models/inventory_item.dart';
import '../../models/medication.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../scheduling/schedule_expander.dart';
import '../utils/result.dart';

/// Pure-Dart validation and unit-mapping module used across forms, ViewModels, and repositories.
/// Enforces clinical bounds, rejects NaN/Infinity/out-of-range inputs, and provides sanitizing formatters.
class MedicationValidator {
  const MedicationValidator._();

  /// Returns the canonical plural unit label for a [MedicationForm].
  static String unitForForm(MedicationForm form) {
    switch (form) {
      case MedicationForm.tablet:
        return 'tablets';
      case MedicationForm.capsule:
        return 'capsules';
      case MedicationForm.syrup:
        return 'mL';
      case MedicationForm.injection:
        return 'doses';
      case MedicationForm.drops:
        return 'drops';
      case MedicationForm.inhaler:
        return 'puffs';
      case MedicationForm.topical:
        return 'applications';
    }
  }

  /// Returns the singular unit label for a [MedicationForm].
  static String singularUnitForForm(MedicationForm form) {
    switch (form) {
      case MedicationForm.tablet:
        return 'tablet';
      case MedicationForm.capsule:
        return 'capsule';
      case MedicationForm.syrup:
        return 'mL';
      case MedicationForm.injection:
        return 'dose';
      case MedicationForm.drops:
        return 'drop';
      case MedicationForm.inhaler:
        return 'puff';
      case MedicationForm.topical:
        return 'application';
    }
  }

  /// Returns the appropriate unit label based on quantity.
  static String formatUnit(MedicationForm form, double amount) {
    if (form == MedicationForm.syrup) return 'mL';
    return (amount == 1.0) ? singularUnitForForm(form) : unitForForm(form);
  }

  /// Formats a dose amount with its singular/plural unit (e.g., "1 tablet", "2 capsules", "5 mL").
  static String formatDoseWithUnit(double amount, MedicationForm form) {
    return '${formatQuantity(amount)} ${formatUnit(form, amount)}';
  }

  /// Returns a clean, user-friendly form name (never raw uppercase enum text).
  static String displayNameForForm(MedicationForm form) {
    switch (form) {
      case MedicationForm.tablet:
        return 'Tablet';
      case MedicationForm.capsule:
        return 'Capsule';
      case MedicationForm.syrup:
        return 'Liquid / Syrup';
      case MedicationForm.injection:
        return 'Injection';
      case MedicationForm.drops:
        return 'Drops';
      case MedicationForm.inhaler:
        return 'Inhaler';
      case MedicationForm.topical:
        return 'Topical / Cream';
    }
  }

  /// Returns a form-appropriate stock field label (never "Pill Count" for liquids/inhalers).
  static String stockFieldLabelForForm(MedicationForm form) {
    switch (form) {
      case MedicationForm.tablet:
        return 'Current Tablet Count';
      case MedicationForm.capsule:
        return 'Current Capsule Count';
      case MedicationForm.syrup:
        return 'Current Volume (mL)';
      case MedicationForm.injection:
        return 'Current Injection Doses';
      case MedicationForm.drops:
        return 'Current Drop Count';
      case MedicationForm.inhaler:
        return 'Current Inhaler Puffs';
      case MedicationForm.topical:
        return 'Current Applications';
    }
  }

  /// Returns true if the given [MedicationForm] supports automatic stock deduction on dose intake.
  /// Only discrete solid oral forms (tablets and capsules) auto-decrement.
  static bool supportsAutoDecrement(MedicationForm form) {
    return form == MedicationForm.tablet || form == MedicationForm.capsule;
  }

  /// Returns true if the given [MedicationForm] accepts decimal stock quantities (max 1 decimal).
  static bool allowsDecimalStock(MedicationForm form) {
    return form == MedicationForm.syrup;
  }

  /// Returns true if the given [MedicationForm] accepts fractional dose amounts.
  /// Capsules, drops, and inhaler puffs cannot be split into fractional doses.
  static bool allowsDecimalDose(MedicationForm form) {
    return form != MedicationForm.capsule &&
        form != MedicationForm.drops &&
        form != MedicationForm.inhaler;
  }

  /// Formats a stock or dose number cleanly (no trailing `.0` for whole numbers, 1 decimal otherwise).
  static String formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  /// Formats a stock count for compact UI display (at most two digits: `0`–`99`, capped at `99` for `> 99`).
  /// Display-only: NEVER use this helper when persisting, deducting, or comparing inventory values.
  static String formatCompactStockCount(double value) {
    if (value.isNaN || value.isInfinite || value <= 0) {
      return '0';
    }
    if (value > 99) {
      return '99';
    }
    return formatQuantity(value);
  }

  /// Calculates the default low-stock threshold equal to 7 days of prescribed supply.
  /// Never returns a hardcoded 2.0.
  static double calculateDefaultThreshold(Medication medication) {
    final dailyRate = InventoryItem.calculateDailyPrescribedRate(medication);
    final raw = dailyRate > 0
        ? dailyRate * AppConstants.defaultLowStockDaysSupply
        : medication.doseAmount * AppConstants.defaultLowStockDaysSupply;
    final clamped = raw.clamp(1.0, AppConstants.maxLowStockThreshold);
    if (allowsDecimalStock(medication.form)) {
      return (clamped * 10).roundToDouble() / 10.0;
    }
    return clamped.ceilToDouble().clamp(1.0, AppConstants.maxLowStockThreshold);
  }

  /// Parses a finite double, rejecting null, empty, NaN, and Infinity.
  static double? tryParseFiniteDouble(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final val = double.tryParse(trimmed);
    if (val == null || val.isNaN || val.isInfinite) return null;
    return val;
  }

  /// Checks if a string has at most [maxDecimals] digits after the decimal point.
  static bool hasValidPrecision(String raw, int maxDecimals) {
    final trimmed = raw.trim();
    final parts = trimmed.split('.');
    if (parts.length == 1) return true;
    if (parts.length > 2) return false;
    if (maxDecimals <= 0) return false;
    return parts[1].length <= maxDecimals && parts[1].isNotEmpty;
  }

  static String? validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Medication name is required (1–${AppConstants.maxMedicationNameLength} chars).';
    }
    if (trimmed.length > AppConstants.maxMedicationNameLength) {
      return 'Name must be ${AppConstants.maxMedicationNameLength} characters or fewer.';
    }
    return null;
  }

  static String? validateGenericName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > AppConstants.maxGenericNameLength) {
      return 'Generic name must be ${AppConstants.maxGenericNameLength} characters or fewer.';
    }
    return null;
  }

  static String? validateStrength(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Strength is required (1–${AppConstants.maxStrengthLength} chars, e.g. 500mg).';
    }
    if (trimmed.length > AppConstants.maxStrengthLength) {
      return 'Strength must be ${AppConstants.maxStrengthLength} characters or fewer.';
    }
    return null;
  }

  static String? validateInstructions(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > AppConstants.maxInstructionsLength) {
      return 'Instructions must be ${AppConstants.maxInstructionsLength} characters or fewer.';
    }
    return null;
  }

  static String? validateNotes(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > AppConstants.maxNotesLength) {
      return 'Notes must be ${AppConstants.maxNotesLength} characters or fewer.';
    }
    return null;
  }

  static String? validateSkipReason(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > AppConstants.maxSkipReasonLength) {
      return 'Reason must be ${AppConstants.maxSkipReasonLength} characters or fewer.';
    }
    return null;
  }

  static String? validateDisplayName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.length < AppConstants.minDisplayNameLength) {
      return 'Name must be at least ${AppConstants.minDisplayNameLength} characters.';
    }
    if (trimmed.length > AppConstants.maxDisplayNameLength) {
      return 'Name must be ${AppConstants.maxDisplayNameLength} characters or fewer.';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Email address is required.';
    }
    if (trimmed.length > AppConstants.maxEmailLength) {
      return 'Email must be ${AppConstants.maxEmailLength} characters or fewer.';
    }
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validatePassword(String? value, {bool isSignIn = false}) {
    final raw = value ?? '';
    if (raw.trim().isEmpty) {
      return 'Password is required.';
    }
    if (raw.length > AppConstants.maxPasswordLength) {
      return 'Password must be ${AppConstants.maxPasswordLength} characters or fewer.';
    }
    if (!isSignIn && raw.length < AppConstants.minPasswordLength) {
      return 'Password must be at least ${AppConstants.minPasswordLength} characters.';
    }
    return null;
  }

  static String? validateDoseAmount(String? value, {MedicationForm? form}) {
    final parsed = tryParseFiniteDouble(value);
    if (parsed == null) {
      return 'Enter a valid dose between ${AppConstants.minDoseAmount} and ${AppConstants.maxDoseAmount.toInt()}.';
    }
    if (parsed <= 0 || parsed > AppConstants.maxDoseAmount) {
      return 'Dose must be greater than 0 and at most ${AppConstants.maxDoseAmount.toInt()}.';
    }
    if (form != null && !allowsDecimalDose(form)) {
      if (parsed != parsed.roundToDouble() || value!.trim().contains('.')) {
        return 'Enter a whole number of ${unitForForm(form)} (no decimals).';
      }
      return null;
    }
    if (!hasValidPrecision(value!, 2)) {
      return 'Dose can have at most 2 decimal places.';
    }
    return null;
  }

  static String? validateStock(
    String? value, {
    required MedicationForm form,
  }) {
    final parsed = tryParseFiniteDouble(value);
    final unit = unitForForm(form);
    final maxInt = AppConstants.maxStock.toInt();
    if (parsed == null) {
      return 'Enter a valid stock amount (0–$maxInt $unit).';
    }
    if (parsed < AppConstants.minStock || parsed > AppConstants.maxStock) {
      return 'Stock must be between 0 and $maxInt $unit.';
    }
    if (allowsDecimalStock(form)) {
      if (!hasValidPrecision(value!, 1)) {
        return 'Volume in mL can have at most 1 decimal place.';
      }
    } else {
      if (parsed != parsed.roundToDouble() || value!.trim().contains('.')) {
        return 'Enter a whole number of $unit (no decimals).';
      }
    }
    return null;
  }

  static String? validateRefillAmount(
    String? value, {
    required MedicationForm form,
    required double currentStock,
  }) {
    final parsed = tryParseFiniteDouble(value);
    final unit = unitForForm(form);
    final maxInt = AppConstants.maxStock.toInt();
    if (parsed == null || parsed <= 0) {
      return 'Enter a refill amount greater than 0 $unit.';
    }
    if (allowsDecimalStock(form)) {
      if (!hasValidPrecision(value!, 1)) {
        return 'Volume in mL can have at most 1 decimal place.';
      }
    } else {
      if (parsed != parsed.roundToDouble() || value!.trim().contains('.')) {
        return 'Enter a whole number of $unit (no decimals).';
      }
    }
    if (currentStock + parsed > AppConstants.maxStock) {
      final maxAdd = (AppConstants.maxStock - currentStock)
          .clamp(0.0, AppConstants.maxStock);
      return 'Total stock cannot exceed $maxInt $unit (max add: ${formatQuantity(maxAdd)}).';
    }
    return null;
  }

  static String? validateThreshold(
    String? value, {
    required MedicationForm form,
  }) {
    final parsed = tryParseFiniteDouble(value);
    final unit = unitForForm(form);
    final maxInt = AppConstants.maxLowStockThreshold.toInt();
    if (parsed == null) {
      return 'Enter a low-stock alert threshold (0–$maxInt $unit).';
    }
    if (parsed < AppConstants.minLowStockThreshold ||
        parsed > AppConstants.maxLowStockThreshold) {
      return 'Threshold must be between 0 and $maxInt $unit.';
    }
    if (allowsDecimalStock(form)) {
      if (!hasValidPrecision(value!, 1)) {
        return 'Threshold in mL can have at most 1 decimal place.';
      }
    } else {
      if (parsed != parsed.roundToDouble() || value!.trim().contains('.')) {
        return 'Enter a whole number of $unit (no decimals).';
      }
    }
    return null;
  }

  static String? validatePrnMinInterval(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Enter minimum hours between doses (${AppConstants.minPrnIntervalHours}–${AppConstants.maxPrnIntervalHours} h).';
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null ||
        parsed < AppConstants.minPrnIntervalHours ||
        parsed > AppConstants.maxPrnIntervalHours) {
      return 'Interval must be a whole number from ${AppConstants.minPrnIntervalHours} to ${AppConstants.maxPrnIntervalHours} hours.';
    }
    return null;
  }

  static String? validatePrnDailyMax(String? value,
      {required double doseAmount}) {
    final parsed = tryParseFiniteDouble(value);
    if (parsed == null) {
      return 'Enter max daily units (${formatQuantity(doseAmount)}–${AppConstants.maxPrnDailyDose.toInt()}).';
    }
    if (parsed > AppConstants.maxPrnDailyDose || parsed <= 0) {
      return 'Max daily dose must be between ${formatQuantity(doseAmount)} and ${AppConstants.maxPrnDailyDose.toInt()}.';
    }
    if (parsed < doseAmount) {
      return 'Max daily dose (${formatQuantity(parsed)}) cannot be less than a single dose (${formatQuantity(doseAmount)}).';
    }
    if (!hasValidPrecision(value!, 2)) {
      return 'Max daily dose can have at most 2 decimal places.';
    }
    return null;
  }

  static String? validateEveryXDays(String? value) {
    final trimmed = value?.trim() ?? '';
    final parsed = int.tryParse(trimmed);
    if (parsed == null ||
        parsed < AppConstants.minScheduleIntervalDays ||
        parsed > AppConstants.maxScheduleIntervalDays) {
      return 'Enter an interval between ${AppConstants.minScheduleIntervalDays} and ${AppConstants.maxScheduleIntervalDays} days.';
    }
    return null;
  }

  static String? validateEveryXHours(String? value) {
    final trimmed = value?.trim() ?? '';
    final parsed = int.tryParse(trimmed);
    if (parsed == null ||
        parsed < AppConstants.minScheduleIntervalHours ||
        parsed > AppConstants.maxScheduleIntervalHours) {
      return 'Enter an interval between ${AppConstants.minScheduleIntervalHours} and ${AppConstants.maxScheduleIntervalHours} hours.';
    }
    return null;
  }

  static String? validateCycleDays(String? value,
      {String label = 'Cycle days'}) {
    final trimmed = value?.trim() ?? '';
    final parsed = int.tryParse(trimmed);
    if (parsed == null ||
        parsed < AppConstants.minCycleDays ||
        parsed > AppConstants.maxCycleDays) {
      return '$label must be between ${AppConstants.minCycleDays} and ${AppConstants.maxCycleDays} days.';
    }
    return null;
  }

  static String? validateTimeSlots(List<String> slots) {
    if (slots.length < AppConstants.minTimeSlots ||
        slots.length > AppConstants.maxTimeSlots) {
      return 'Add between ${AppConstants.minTimeSlots} and ${AppConstants.maxTimeSlots} dose times.';
    }
    final seen = <String>{};
    for (final slot in slots) {
      final parsed = ScheduleExpander.parseTimeOfDay(slot);
      if (parsed == null) {
        return 'Invalid time slot "$slot" (expected HH:mm).';
      }
      final canonical =
          '${parsed.$1.toString().padLeft(2, '0')}:${parsed.$2.toString().padLeft(2, '0')}';
      if (!seen.add(canonical)) {
        return 'Duplicate dose time "$canonical" is not allowed.';
      }
    }
    return null;
  }

  static String? validateWeekdays(List<int> weekdays) {
    if (weekdays.isEmpty) {
      return 'Select at least one day of the week.';
    }
    final seen = <int>{};
    for (final day in weekdays) {
      if (day < 1 || day > 7) {
        return 'Weekday must be between Monday (1) and Sunday (7).';
      }
      if (!seen.add(day)) {
        return 'Duplicate weekday selection is not allowed.';
      }
    }
    return null;
  }

  /// Normalizes and sorts a list of `HH:mm` time strings, removing duplicates.
  static List<String> normalizeAndSortTimeSlots(Iterable<String> slots) {
    final normalized = <String>{};
    for (final slot in slots) {
      final parsed = ScheduleExpander.parseTimeOfDay(slot);
      if (parsed != null) {
        normalized.add(
          '${parsed.$1.toString().padLeft(2, '0')}:${parsed.$2.toString().padLeft(2, '0')}',
        );
      }
    }
    final list = normalized.toList()..sort();
    return List.unmodifiable(list);
  }

  /// Validates a complete [Medication] domain model before persistence.
  static Result<void> validateMedicationModel(Medication med) {
    final nameErr = validateName(med.name);
    if (nameErr != null) return Failure(ValidationException(nameErr));

    final genErr = validateGenericName(med.genericName);
    if (genErr != null) return Failure(ValidationException(genErr));

    final strengthErr = validateStrength(med.strength);
    if (strengthErr != null) return Failure(ValidationException(strengthErr));

    final instrErr = validateInstructions(med.instructions);
    if (instrErr != null) return Failure(ValidationException(instrErr));

    final notesErr = validateNotes(med.notes);
    if (notesErr != null) return Failure(ValidationException(notesErr));

    if (med.doseAmount.isNaN ||
        med.doseAmount.isInfinite ||
        med.doseAmount <= 0 ||
        med.doseAmount > AppConstants.maxDoseAmount) {
      return Failure(
        ValidationException(
          'Dose amount must be between ${AppConstants.minDoseAmount} and ${AppConstants.maxDoseAmount.toInt()}.',
        ),
      );
    }

    if (!allowsDecimalDose(med.form) &&
        med.doseAmount != med.doseAmount.roundToDouble()) {
      return Failure(
        ValidationException(
          'Dose amount for ${unitForForm(med.form)} must be a whole number.',
        ),
      );
    }

    if (med.isPrn) {
      if (med.minIntervalHours != null &&
          (med.minIntervalHours! < AppConstants.minPrnIntervalHours ||
              med.minIntervalHours! > AppConstants.maxPrnIntervalHours)) {
        return const Failure(
          ValidationException(
            'Minimum hours between doses must be between ${AppConstants.minPrnIntervalHours} and ${AppConstants.maxPrnIntervalHours} hours.',
          ),
        );
      }
      if (med.dailyMaxDose != null) {
        if (med.dailyMaxDose!.isNaN ||
            med.dailyMaxDose!.isInfinite ||
            med.dailyMaxDose! < med.doseAmount ||
            med.dailyMaxDose! > AppConstants.maxPrnDailyDose) {
          return Failure(
            ValidationException(
              'Maximum daily dose must be between ${formatQuantity(med.doseAmount)} and ${AppConstants.maxPrnDailyDose.toInt()}.',
            ),
          );
        }
      }
    } else {
      final sched = med.schedule;
      if (sched == null) {
        return const Failure(
          ValidationException(
              'Scheduled medications require a valid schedule.'),
        );
      }
      final slotsErr = validateTimeSlots(sched.timesOfDay);
      if (slotsErr != null) return Failure(ValidationException(slotsErr));

      switch (sched.frequency) {
        case ScheduleFrequency.daily:
          break;
        case ScheduleFrequency.specificWeekdays:
          final wdErr = validateWeekdays(sched.weekdays);
          if (wdErr != null) return Failure(ValidationException(wdErr));
        case ScheduleFrequency.everyXDays:
          final iv = sched.intervalValue;
          if (iv == null ||
              iv < AppConstants.minScheduleIntervalDays ||
              iv > AppConstants.maxScheduleIntervalDays) {
            return const Failure(
              ValidationException(
                'Interval must be between ${AppConstants.minScheduleIntervalDays} and ${AppConstants.maxScheduleIntervalDays} days.',
              ),
            );
          }
        case ScheduleFrequency.everyXHours:
          final iv = sched.intervalValue;
          if (iv == null ||
              iv < AppConstants.minScheduleIntervalHours ||
              iv > AppConstants.maxScheduleIntervalHours) {
            return const Failure(
              ValidationException(
                'Hourly interval must be between ${AppConstants.minScheduleIntervalHours} and ${AppConstants.maxScheduleIntervalHours} hours.',
              ),
            );
          }
        case ScheduleFrequency.cycleBased:
          final active = sched.cycleActiveDays;
          final rest = sched.cycleRestDays;
          if (active == null ||
              active < AppConstants.minCycleDays ||
              active > AppConstants.maxCycleDays ||
              rest == null ||
              rest < AppConstants.minCycleDays ||
              rest > AppConstants.maxCycleDays) {
            return const Failure(
              ValidationException(
                'Cycle active and rest days must each be between ${AppConstants.minCycleDays} and ${AppConstants.maxCycleDays}.',
              ),
            );
          }
      }
    }

    return const Success(null);
  }

  /// Validates an [InventoryItem] domain model before persistence.
  static Result<void> validateInventoryItemModel(
    InventoryItem item, {
    MedicationForm? form,
  }) {
    if (item.currentStock.isNaN ||
        item.currentStock.isInfinite ||
        item.currentStock < AppConstants.minStock ||
        item.currentStock > AppConstants.maxStock) {
      return Failure(
        ValidationException(
          'Stock must be between 0 and ${AppConstants.maxStock.toInt()}.',
        ),
      );
    }
    if (item.lowStockThreshold.isNaN ||
        item.lowStockThreshold.isInfinite ||
        item.lowStockThreshold < AppConstants.minLowStockThreshold ||
        item.lowStockThreshold > AppConstants.maxLowStockThreshold) {
      return Failure(
        ValidationException(
          'Low-stock threshold must be between 0 and ${AppConstants.maxLowStockThreshold.toInt()}.',
        ),
      );
    }
    if (form != null && !allowsDecimalStock(form)) {
      if (item.currentStock != item.currentStock.roundToDouble()) {
        return Failure(
          ValidationException(
            'Stock for ${unitForForm(form)} must be a whole number.',
          ),
        );
      }
      if (item.lowStockThreshold != item.lowStockThreshold.roundToDouble()) {
        return Failure(
          ValidationException(
            'Low-stock threshold for ${unitForForm(form)} must be a whole number.',
          ),
        );
      }
    }
    return const Success(null);
  }

  /// Input formatters for whole-number fields (e.g., tablet count, intervals).
  static List<TextInputFormatter> wholeNumberFormatters({int maxLength = 4}) {
    return [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Input formatters for decimal fields, sanitizing paste and restricting decimal places.
  static List<TextInputFormatter> decimalFormatters({
    int maxDecimals = 1,
    int maxLength = 6,
  }) {
    return [
      _SanitizingDecimalTextInputFormatter(maxDecimals: maxDecimals),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Input formatters for dose-per-intake fields depending on [MedicationForm].
  static List<TextInputFormatter> doseFormattersForForm(MedicationForm form) {
    if (allowsDecimalDose(form)) {
      return decimalFormatters(maxDecimals: 2, maxLength: 6);
    }
    return wholeNumberFormatters(maxLength: 3);
  }

  /// Input formatters for stock fields depending on [MedicationForm] (max stock is 9999).
  static List<TextInputFormatter> stockFormattersForForm(MedicationForm form) {
    if (allowsDecimalStock(form)) {
      return decimalFormatters(maxDecimals: 1, maxLength: 6);
    }
    return wholeNumberFormatters(maxLength: 4);
  }
}

class _SanitizingDecimalTextInputFormatter extends TextInputFormatter {
  final int maxDecimals;

  const _SanitizingDecimalTextInputFormatter({required this.maxDecimals});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool hasDot = false;
    int decimalsAfterDot = 0;

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        if (hasDot) {
          if (decimalsAfterDot < maxDecimals) {
            buffer.write(ch);
            decimalsAfterDot++;
          }
        } else {
          buffer.write(ch);
        }
      } else if ((ch == '.' || ch == ',') && !hasDot && maxDecimals > 0) {
        if (buffer.isEmpty) {
          buffer.write('0');
        }
        buffer.write('.');
        hasDot = true;
      }
    }

    final sanitized = buffer.toString();
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(
        offset: newValue.selection.end.clamp(0, sanitized.length),
      ),
    );
  }
}
