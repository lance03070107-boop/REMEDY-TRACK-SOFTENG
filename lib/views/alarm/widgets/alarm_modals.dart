import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/state/dose_state_machine.dart';

/// Modal bottom sheets for Snooze duration selection and skip reason capture
/// on [AlarmRingingScreen].
class AlarmModals {
  const AlarmModals._();

  static Future<int?> showSnoozeSheet({
    required BuildContext context,
    required int initialMinutes,
    required int currentSnoozeCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final sheetBg = scheme.surfaceContainerLowest;
    final textColor = scheme.onSurface;
    final subtextColor = scheme.onSurfaceVariant;
    final chipBg = scheme.surfaceContainer;

    int selectedMinutes = initialMinutes;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final remaining =
                DoseStateMachine.maxSnoozeLimit - currentSnoozeCount;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: subtextColor.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.snooze_rounded,
                            color: scheme.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Snooze Reminder',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$remaining of ${DoseStateMachine.maxSnoozeLimit} snoozes remaining',
                                style: TextStyle(
                                  color: subtextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Remind me again in:',
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [5, 10, 15, 30].map((mins) {
                        final isSel = selectedMinutes == mins;
                        return ChoiceChip(
                          label: Text('+$mins mins'),
                          selected: isSel,
                          backgroundColor: chipBg,
                          selectedColor: scheme.primary,
                          checkmarkColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSel
                                  ? scheme.primary
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          labelStyle: TextStyle(
                            color: isSel ? scheme.onPrimary : textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => selectedMinutes = mins);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: subtextColor,
                              minimumSize: const Size.fromHeight(52),
                              side: BorderSide(
                                  color: subtextColor.withValues(alpha: 0.35)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, null),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.pop(ctx, selectedMinutes),
                            icon: const Icon(Icons.alarm_add_rounded, size: 20),
                            label: Text(
                              'Snooze $selectedMinutes Mins',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<String?> showSkipSheet({
    required BuildContext context,
    required String medicationName,
  }) async {
    const skipReasons = [
      'Fasting before a medical test',
      'Side effects or feeling unwell',
      'Doctor advised me to pause',
      'Out of medicine stock',
      'Already took this dose',
      'Other reason',
    ];

    final scheme = Theme.of(context).colorScheme;
    final sheetBg = scheme.surfaceContainerLowest;
    final textColor = scheme.onSurface;
    final subtextColor = scheme.onSurfaceVariant;
    final tileBg = scheme.surfaceContainer;

    String? selectedReason = skipReasons.first;
    final customNotesController = TextEditingController();

    try {
      return await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: sheetBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final isOther = selectedReason == 'Other reason';
              return Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: subtextColor.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: scheme.error.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.fast_forward_rounded,
                              color: scheme.error,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Skip $medicationName?',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Skipping saves your reason without changing your medicine count.',
                                  style: TextStyle(
                                    color: subtextColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Why are you skipping this dose?',
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...skipReasons.map((reason) {
                        final isSel = selectedReason == reason;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: InkWell(
                            onTap: () {
                              setModalState(() => selectedReason = reason);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? scheme.error.withValues(alpha: 0.12)
                                    : tileBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSel
                                      ? scheme.error
                                      : subtextColor.withValues(alpha: 0.18),
                                  width: isSel ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSel
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSel ? scheme.error : subtextColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      reason,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      if (isOther) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: customNotesController,
                          maxLength: AppConstants.maxSkipReasonLength,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Write your reason...',
                            hintStyle: TextStyle(color: subtextColor),
                            filled: true,
                            fillColor: tileBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                foregroundColor: subtextColor,
                                side: BorderSide(
                                    color:
                                        subtextColor.withValues(alpha: 0.35)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => Navigator.pop(ctx, null),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.error,
                                foregroundColor: scheme.onError,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: selectedReason == null
                                  ? null
                                  : () {
                                      final typed =
                                          customNotesController.text.trim();
                                      final finalReason =
                                          isOther && typed.isNotEmpty
                                              ? typed
                                              : selectedReason!;
                                      Navigator.pop(ctx, finalReason);
                                    },
                              icon: const Icon(Icons.fast_forward_rounded,
                                  size: 20),
                              label: const Text(
                                'Confirm Skip',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      customNotesController.dispose();
    }
  }
}
