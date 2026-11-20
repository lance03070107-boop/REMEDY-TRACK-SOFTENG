import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/scheduling/schedule_expander.dart';
import '../../core/utils/time_formatter.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/dose_schedule.dart';
import '../../models/medication.dart';
import '../../services/alarm_sound_service.dart';
import '../../services/permission_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/state_views.dart';

/// Unified screen for adding or editing a medication and its alarm schedule.
class AddEditMedicationView extends StatefulWidget {
  final String? medicationId;

  const AddEditMedicationView({super.key, this.medicationId});

  @override
  State<AddEditMedicationView> createState() => _AddEditMedicationViewState();
}

class _AddEditMedicationViewState extends State<AddEditMedicationView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _strengthController;
  late final TextEditingController _doseAmountController;
  late final TextEditingController _minIntervalController;
  late final TextEditingController _dailyMaxController;
  late final TextEditingController _intervalDaysController;
  late final TextEditingController _intervalHoursController;
  late final TextEditingController _cycleActiveController;
  late final TextEditingController _cycleRestController;
  late final TextEditingController _instructionsController;

  MedicationForm _form = MedicationForm.tablet;
  String _iconTag = 'pill';
  bool _isPrn = false;
  ScheduleFrequency _frequency = ScheduleFrequency.daily;
  List<String> _timesOfDay = ['08:00'];
  List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];
  DateTime? _endDate;

  String _selectedSoundId = AppConstants.defaultAlarmSound;
  String? _customSoundPath;
  bool _vibrationEnabled = true;
  List<AlarmSoundItem> _availableSounds = [];

  Medication? _existingMedication;
  bool _isEditing = false;
  bool _medicationNotFound = false;
  bool _isSaving = false;
  bool _isDirty = false;
  String? _scheduleInlineError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _strengthController = TextEditingController();
    _doseAmountController = TextEditingController(text: '1');
    _minIntervalController = TextEditingController(text: '4');
    _dailyMaxController = TextEditingController(text: '4');
    _intervalDaysController = TextEditingController(text: '2');
    _intervalHoursController = TextEditingController(text: '6');
    _cycleActiveController = TextEditingController(text: '21');
    _cycleRestController = TextEditingController(text: '7');
    _instructionsController = TextEditingController();

    _loadSounds();

    if (widget.medicationId != null) {
      _isEditing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingMedication();
      });
    }

    for (final ctrl in [
      _nameController,
      _strengthController,
      _doseAmountController,
      _minIntervalController,
      _dailyMaxController,
      _intervalDaysController,
      _intervalHoursController,
      _cycleActiveController,
      _cycleRestController,
      _instructionsController,
    ]) {
      ctrl.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty && mounted) {
      setState(() => _isDirty = true);
    }
  }

  Future<void> _loadSounds() async {
    final service = AlarmSoundService();
    await service.initialize();
    final sounds = await service.getAllSounds();
    if (mounted) {
      setState(() {
        _availableSounds = sounds;
      });
    }
  }

  void _loadExistingMedication() {
    final medVm = context.read<MedicationViewModel>();

    final med = medVm.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == widget.medicationId,
          orElse: () => null,
        );

    if (med == null) {
      setState(() {
        _medicationNotFound = true;
      });
      return;
    }

    _existingMedication = med;
    _nameController.text = med.name;
    _strengthController.text = med.strength;
    _doseAmountController.text =
        MedicationValidator.formatQuantity(med.doseAmount);
    _instructionsController.text = med.instructions;
    _form = med.form;
    _iconTag = med.iconTag;
    _isPrn = med.isPrn;
    _selectedSoundId = med.alarmSoundId;
    _customSoundPath = med.customSoundPath;
    _vibrationEnabled = med.vibrationEnabled;

    if (med.minIntervalHours != null) {
      _minIntervalController.text = med.minIntervalHours.toString();
    }
    if (med.dailyMaxDose != null) {
      _dailyMaxController.text =
          MedicationValidator.formatQuantity(med.dailyMaxDose!);
    }

    if (med.schedule != null) {
      final sched = med.schedule!;
      _frequency = sched.frequency;
      _endDate = sched.endDate;
      _timesOfDay =
          MedicationValidator.normalizeAndSortTimeSlots(sched.timesOfDay)
              .toList();
      if (_timesOfDay.isEmpty) {
        _timesOfDay = ['08:00'];
      }
      _weekdays = sched.weekdays.isNotEmpty
          ? (List<int>.from(sched.weekdays)..sort())
          : [1, 2, 3, 4, 5, 6, 7];
      if (sched.intervalValue != null) {
        if (sched.frequency == ScheduleFrequency.everyXHours) {
          _intervalHoursController.text = sched.intervalValue.toString();
        } else {
          _intervalDaysController.text = sched.intervalValue.toString();
        }
      }
      if (sched.cycleActiveDays != null) {
        _cycleActiveController.text = sched.cycleActiveDays.toString();
      }
      if (sched.cycleRestDays != null) {
        _cycleRestController.text = sched.cycleRestDays.toString();
      }
    }

    setState(() {
      _isDirty = false;
    });
  }

  @override
  void dispose() {
    AlarmSoundService().stopPreview();
    _nameController.dispose();
    _strengthController.dispose();
    _doseAmountController.dispose();
    _minIntervalController.dispose();
    _dailyMaxController.dispose();
    _intervalDaysController.dispose();
    _intervalHoursController.dispose();
    _cycleActiveController.dispose();
    _cycleRestController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty || _isSaving) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Unsaved Changes?'),
        content: const Text(
          'You have unsaved changes to this medication. Leaving now will discard them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _pickTime(int index) async {
    final parts = _timesOfDay[index].split(':');
    final initial = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked != null && mounted) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final existingIdx = _timesOfDay.indexOf(formatted);
      if (existingIdx != -1 && existingIdx != index) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dose time $formatted is already added.'),
          ),
        );
        return;
      }
      setState(() {
        _timesOfDay[index] = formatted;
        _timesOfDay.sort();
        _scheduleInlineError = null;
        _isDirty = true;
      });
    }
  }

  void _addTimeSlot() {
    if (_timesOfDay.length >= AppConstants.maxTimeSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maximum of ${AppConstants.maxTimeSlots} daily dose times reached.',
          ),
        ),
      );
      return;
    }

    const candidates = [
      '08:00',
      '12:00',
      '18:00',
      '20:00',
      '22:00',
      '06:00',
      '10:00',
      '14:00',
      '16:00',
      '09:00',
      '15:00',
      '21:00',
    ];
    String? nextSlot;
    for (final c in candidates) {
      if (!_timesOfDay.contains(c)) {
        nextSlot = c;
        break;
      }
    }
    if (nextSlot == null) {
      for (int h = 0; h < 24; h++) {
        final candidate = '${h.toString().padLeft(2, '0')}:00';
        if (!_timesOfDay.contains(candidate)) {
          nextSlot = candidate;
          break;
        }
      }
    }
    if (nextSlot == null) return;

    setState(() {
      _timesOfDay.add(nextSlot!);
      _timesOfDay.sort();
      _scheduleInlineError = null;
      _isDirty = true;
    });
  }

  void _applyTimePreset(List<String> presetTimes) {
    setState(() {
      _timesOfDay = List<String>.from(presetTimes)..sort();
      _scheduleInlineError = null;
      _isDirty = true;
    });
  }

  void _removeTimeSlot(int index) {
    if (_timesOfDay.length > AppConstants.minTimeSlots) {
      setState(() {
        _timesOfDay.removeAt(index);
        _scheduleInlineError = null;
        _isDirty = true;
      });
    }
  }

  Medication _buildDraftMedication({
    required String id,
    required String userId,
    required double doseAmount,
    required DateTime now,
  }) {
    final existingSched = _existingMedication?.schedule;
    DoseSchedule? schedule;
    if (!_isPrn) {
      int? intervalVal;
      if (_frequency == ScheduleFrequency.everyXDays) {
        intervalVal = int.tryParse(_intervalDaysController.text.trim());
      } else if (_frequency == ScheduleFrequency.everyXHours) {
        intervalVal = int.tryParse(_intervalHoursController.text.trim());
      }

      final sortedTimes =
          List<String>.unmodifiable(List<String>.from(_timesOfDay)..sort());
      final sortedWeekdays =
          List<int>.unmodifiable(List<int>.from(_weekdays)..sort());
      final cycleActive = _frequency == ScheduleFrequency.cycleBased
          ? int.tryParse(_cycleActiveController.text.trim())
          : null;
      final cycleRest = _frequency == ScheduleFrequency.cycleBased
          ? int.tryParse(_cycleRestController.text.trim())
          : null;
      final scheduleChanged = existingSched != null &&
          (existingSched.frequency != _frequency ||
              !listEquals(existingSched.timesOfDay, sortedTimes) ||
              !listEquals(existingSched.weekdays, sortedWeekdays) ||
              existingSched.intervalValue != intervalVal ||
              existingSched.cycleActiveDays != cycleActive ||
              existingSched.cycleRestDays != cycleRest ||
              existingSched.endDate != _endDate);

      schedule = DoseSchedule(
        frequency: _frequency,
        timesOfDay: sortedTimes,
        weekdays: sortedWeekdays,
        intervalValue: intervalVal,
        cycleActiveDays: cycleActive,
        cycleRestDays: cycleRest,
        startDate: existingSched?.startDate ?? now,
        endDate: _endDate,
        updatedAt: scheduleChanged ? now : existingSched?.updatedAt,
        alarmSoundId: _selectedSoundId,
        customSoundPath: _customSoundPath,
        vibrationEnabled: _vibrationEnabled,
      );
    }

    return Medication(
      id: id,
      userId: userId,
      name: _nameController.text.trim(),
      genericName: '',
      strength: _strengthController.text.trim(),
      form: _form,
      doseAmount: doseAmount,
      instructions: _instructionsController.text.trim(),
      notes: null,
      colorTag: _existingMedication?.colorTag ?? 0xFF1E66F5,
      iconTag: _existingMedication?.iconTag ?? _iconTag,
      isPrn: _isPrn,
      isActive: _existingMedication?.isActive ?? true,
      minIntervalHours:
          _isPrn ? int.tryParse(_minIntervalController.text.trim()) : null,
      dailyMaxDose: _isPrn
          ? MedicationValidator.tryParseFiniteDouble(_dailyMaxController.text)
          : null,
      schedule: schedule,
      alarmSoundId: _selectedSoundId,
      customSoundPath: _customSoundPath,
      vibrationEnabled: _vibrationEnabled,
      createdAt: _existingMedication?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _saveMedication() async {
    if (_isSaving) return;

    setState(() => _scheduleInlineError = null);
    final isFormValid = _formKey.currentState!.validate();

    if (!_isPrn) {
      final slotErr = MedicationValidator.validateTimeSlots(_timesOfDay);
      if (slotErr != null) {
        setState(() => _scheduleInlineError = slotErr);
        return;
      }
      if (_frequency == ScheduleFrequency.specificWeekdays) {
        final wdErr = MedicationValidator.validateWeekdays(_weekdays);
        if (wdErr != null) {
          setState(() => _scheduleInlineError = wdErr);
          return;
        }
      }
    }

    if (!isFormValid) return;

    final authVm = context.read<AuthViewModel>();
    final medVm = context.read<MedicationViewModel>();
    final userId = _existingMedication?.userId.isNotEmpty == true
        ? _existingMedication!.userId
        : authVm.currentUserId;

    final doseAmount =
        MedicationValidator.tryParseFiniteDouble(_doseAmountController.text)!;

    final now = DateTime.now();
    final medId = _isEditing ? widget.medicationId! : const Uuid().v4();

    final medication = _buildDraftMedication(
      id: medId,
      userId: userId,
      doseAmount: doseAmount,
      now: now,
    );

    setState(() => _isSaving = true);
    await AlarmSoundService().stopPreview();

    try {
      final result = await medVm.saveMedicationOnlyResult(
        medication: medication,
        isEditing: _isEditing,
      );

      if (result.isFailure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorOrNull?.message ?? 'Failed to save medication.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (mounted) {
        if (!kIsWeb && !_isPrn) {
          await PermissionService().ensureAlarmPermissions(context: context);
        }
      }

      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Medication & alarm schedule updated.'
                  : 'Medication & alarm schedule saved.',
            ),
          ),
        );
        context.pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleImportCustomSound() async {
    final service = AlarmSoundService();
    final imported = await service.pickAndImportCustomSound();
    if (imported != null && mounted) {
      final sounds = await service.getAllSounds();
      setState(() {
        _availableSounds = sounds;
        _selectedSoundId = imported.id;
        _customSoundPath = imported.localFilePath;
        _isDirty = true;
      });
      await service.playPreview(
        soundId: imported.id,
        customPath: imported.localFilePath,
      );
    }
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = MedicationValidator.unitForForm(_form);

    if (_medicationNotFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medication Not Found')),
        body: EmptyStateView(
          icon: Icons.medication_outlined,
          title: 'Medication Not Found',
          subtitle:
              'This medication may have been deleted or has not finished syncing.',
          action: FilledButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Go Back'),
          ),
        ),
      );
    }

    final soundExistsInOptions =
        _availableSounds.any((s) => s.id == _selectedSoundId);
    final effectiveDropdownSoundId = soundExistsInOptions
        ? _selectedSoundId
        : (_availableSounds.isNotEmpty
            ? _availableSounds.first.id
            : AppConstants.defaultAlarmSound);

    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscardIfNeeded();
        if (discard && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Medication' : 'Add Medication'),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _saveMedication,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // CARD 1: Medication Details
                    _buildSectionCard(
                      context: context,
                      icon: Icons.medication_rounded,
                      title: '1. Medication Details',
                      subtitle: 'Enter medication name, form, strength, and dose',
                      children: [
                        CustomTextField(
                          controller: _nameController,
                          label: 'Medication Name *',
                          hint: 'e.g., Lipitor, Biogesic',
                          prefixIcon: Icons.medication_outlined,
                          textInputAction: TextInputAction.next,
                          maxLength: AppConstants.maxMedicationNameLength,
                          helperText:
                              'Required (1–${AppConstants.maxMedicationNameLength} characters)',
                          validator: MedicationValidator.validateName,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<MedicationForm>(
                          key: ValueKey('form_dropdown_${_form.name}'),
                          initialValue: _form,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Dosage Form',
                          ),
                          selectedItemBuilder: (context) {
                            return MedicationForm.values
                                .map(_buildFormDropdownRow)
                                .toList();
                          },
                          items: MedicationForm.values.map((f) {
                            return DropdownMenuItem(
                              value: f,
                              child: _buildFormDropdownRow(f),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _form = val;
                                _isDirty = true;
                                if (!MedicationValidator.allowsDecimalDose(
                                    val)) {
                                  final parsedDose =
                                      MedicationValidator.tryParseFiniteDouble(
                                    _doseAmountController.text,
                                  );
                                  if (parsedDose != null &&
                                      parsedDose !=
                                          parsedDose.roundToDouble()) {
                                    _doseAmountController.text = parsedDose
                                        .round()
                                        .clamp(
                                            1,
                                            AppConstants.maxDoseAmount
                                                .toInt())
                                        .toString();
                                  }
                                }
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _strengthController,
                                label: 'Dosage Strength *',
                                hint: 'e.g., 500mg, 20mg/5mL',
                                textInputAction: TextInputAction.next,
                                maxLength: AppConstants.maxStrengthLength,
                                helperText:
                                    'e.g., 500mg or 20mg/5mL (1–${AppConstants.maxStrengthLength} chars)',
                                validator: MedicationValidator.validateStrength,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CustomTextField(
                                controller: _doseAmountController,
                                label: 'Amount per Dose *',
                                hint: '1',
                                suffixText: unitLabel,
                                helperText:
                                    MedicationValidator.allowsDecimalDose(_form)
                                        ? '0.01–${AppConstants.maxDoseAmount.toInt()} $unitLabel'
                                        : '1–${AppConstants.maxDoseAmount.toInt()} $unitLabel',
                                keyboardType: TextInputType.numberWithOptions(
                                  decimal:
                                      MedicationValidator.allowsDecimalDose(
                                          _form),
                                ),
                                inputFormatters:
                                    MedicationValidator.doseFormattersForForm(
                                        _form),
                                textInputAction: TextInputAction.next,
                                validator: (v) =>
                                    MedicationValidator.validateDoseAmount(
                                  v,
                                  form: _form,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        CustomTextField(
                          controller: _instructionsController,
                          label: 'Administration Instructions (Optional)',
                          hint: 'e.g., Take with food and a full glass of water',
                          prefixIcon: Icons.info_outline_rounded,
                          textInputAction: TextInputAction.done,
                          maxLength: AppConstants.maxInstructionsLength,
                          validator: MedicationValidator.validateInstructions,
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final preset in const [
                                'Take with food',
                                'On an empty stomach',
                                'After meals',
                                'Before bedtime',
                                'With plenty of water',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ActionChip(
                                    label: Text(preset),
                                    onPressed: () {
                                      setState(() {
                                        _instructionsController.text = preset;
                                        _isDirty = true;
                                      });
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // CARD 2: Reminder Schedule & Alarm Times
                    _buildSectionCard(
                      context: context,
                      icon: Icons.alarm_rounded,
                      title: '2. Alarm Schedule & Reminder Times',
                      subtitle:
                          'Set when RemedyTrack should ring for your doses',
                      children: [
                        Material(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile(
                            title: const Text(
                              'Take Only When Needed (As-Needed)',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Taken only for symptoms (no fixed daily alarm)',
                            ),
                            value: _isPrn,
                            onChanged: (v) {
                              setState(() {
                                _isPrn = v;
                                _scheduleInlineError = null;
                                _isDirty = true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_isPrn) ...[
                          Text(
                            'Safe Spacing & Daily Limit',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: CustomTextField(
                                  controller: _minIntervalController,
                                  label: 'Minimum Hours Between Doses *',
                                  hint: '4',
                                  suffixText: 'hours',
                                  helperText:
                                      '${AppConstants.minPrnIntervalHours}–${AppConstants.maxPrnIntervalHours} hours',
                                  keyboardType: TextInputType.number,
                                  inputFormatters:
                                      MedicationValidator.wholeNumberFormatters(
                                    maxLength: 2,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  validator: MedicationValidator
                                      .validatePrnMinInterval,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CustomTextField(
                                  controller: _dailyMaxController,
                                  label: 'Max Daily Dose *',
                                  hint: '4',
                                  suffixText: unitLabel,
                                  helperText:
                                      '≥ single dose, max ${AppConstants.maxPrnDailyDose.toInt()}',
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal:
                                        MedicationValidator.allowsDecimalDose(
                                            _form),
                                  ),
                                  inputFormatters:
                                      MedicationValidator.doseFormattersForForm(
                                    _form,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  validator: (v) {
                                    final dose = MedicationValidator
                                            .tryParseFiniteDouble(
                                          _doseAmountController.text,
                                        ) ??
                                        1.0;
                                    return MedicationValidator
                                        .validatePrnDailyMax(
                                      v,
                                      doseAmount: dose > 0 ? dose : 1.0,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          DropdownButtonFormField<ScheduleFrequency>(
                            key: ValueKey('freq_dropdown_${_frequency.name}'),
                            initialValue: _frequency,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Schedule Frequency',
                              prefixIcon: Icon(Icons.repeat_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: ScheduleFrequency.daily,
                                child: Text(
                                  'Every Day',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: ScheduleFrequency.specificWeekdays,
                                child: Text(
                                  'Specific Days of Week',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: ScheduleFrequency.everyXDays,
                                child: Text(
                                  'Every X Days (Interval)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: ScheduleFrequency.everyXHours,
                                child: Text(
                                  'Every X Hours',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: ScheduleFrequency.cycleBased,
                                child: Text(
                                  'Cycle-Based (Active / Rest Days)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _frequency = val;
                                  _scheduleInlineError = null;
                                  _isDirty = true;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Conditional Frequency Inputs
                          if (_frequency ==
                              ScheduleFrequency.specificWeekdays) ...[
                            Text(
                              'Select Days of Week',
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(7, (idx) {
                                final dayNum = idx + 1;
                                const dayLabels = [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ];
                                final selected = _weekdays.contains(dayNum);
                                return Semantics(
                                  label: '${dayLabels[idx]} weekday filter',
                                  selected: selected,
                                  child: FilterChip(
                                    label: Text(dayLabels[idx]),
                                    selected: selected,
                                    onSelected: (val) {
                                      setState(() {
                                        if (val) {
                                          if (!_weekdays.contains(dayNum)) {
                                            _weekdays = [..._weekdays, dayNum]
                                              ..sort();
                                          }
                                        } else if (_weekdays.length > 1) {
                                          _weekdays = _weekdays
                                              .where((d) => d != dayNum)
                                              .toList();
                                        }
                                        _scheduleInlineError = null;
                                        _isDirty = true;
                                      });
                                    },
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 16),
                          ] else if (_frequency ==
                              ScheduleFrequency.everyXDays) ...[
                            CustomTextField(
                              controller: _intervalDaysController,
                              label: 'Interval in Days (Every X Days) *',
                              hint: '2 (e.g. every other day)',
                              suffixText: 'days',
                              helperText:
                                  '${AppConstants.minScheduleIntervalDays}–${AppConstants.maxScheduleIntervalDays} days',
                              keyboardType: TextInputType.number,
                              inputFormatters:
                                  MedicationValidator.wholeNumberFormatters(
                                maxLength: 3,
                              ),
                              validator: MedicationValidator.validateEveryXDays,
                            ),
                            const SizedBox(height: 16),
                          ] else if (_frequency ==
                              ScheduleFrequency.everyXHours) ...[
                            CustomTextField(
                              controller: _intervalHoursController,
                              label: 'Interval in Hours (Every X Hours) *',
                              hint: '6',
                              suffixText: 'hours',
                              helperText:
                                  '${AppConstants.minScheduleIntervalHours}–${AppConstants.maxScheduleIntervalHours} hours',
                              keyboardType: TextInputType.number,
                              inputFormatters:
                                  MedicationValidator.wholeNumberFormatters(
                                maxLength: 2,
                              ),
                              validator:
                                  MedicationValidator.validateEveryXHours,
                              onChanged: (_) => setState(() => _isDirty = true),
                            ),
                            const SizedBox(height: 16),
                          ] else if (_frequency ==
                              ScheduleFrequency.cycleBased) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: CustomTextField(
                                    controller: _cycleActiveController,
                                    label: 'Active Days *',
                                    hint: '21',
                                    suffixText: 'days',
                                    helperText:
                                        '${AppConstants.minCycleDays}–${AppConstants.maxCycleDays} days',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: MedicationValidator
                                        .wholeNumberFormatters(
                                      maxLength: 3,
                                    ),
                                    validator: (v) =>
                                        MedicationValidator.validateCycleDays(
                                      v,
                                      label: 'Active days',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CustomTextField(
                                    controller: _cycleRestController,
                                    label: 'Rest Days *',
                                    hint: '7',
                                    suffixText: 'days',
                                    helperText:
                                        '${AppConstants.minCycleDays}–${AppConstants.maxCycleDays} days',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: MedicationValidator
                                        .wholeNumberFormatters(
                                      maxLength: 3,
                                    ),
                                    validator: (v) =>
                                        MedicationValidator.validateCycleDays(
                                      v,
                                      label: 'Rest days',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Quick Presets for Alarm Times
                          Text(
                            'Quick Alarm Presets',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ActionChip(
                                  avatar: const Icon(Icons.wb_sunny_outlined,
                                      size: 16),
                                  label: const Text('Once Daily (8 AM)'),
                                  onPressed: () => _applyTimePreset(['08:00']),
                                ),
                                const SizedBox(width: 8),
                                ActionChip(
                                  avatar:
                                      const Icon(Icons.sync_rounded, size: 16),
                                  label: const Text('Twice Daily (8 AM, 8 PM)'),
                                  onPressed: () =>
                                      _applyTimePreset(['08:00', '20:00']),
                                ),
                                const SizedBox(width: 8),
                                ActionChip(
                                  avatar: const Icon(Icons.schedule_rounded,
                                      size: 16),
                                  label:
                                      const Text('3x Daily (8 AM, 2 PM, 8 PM)'),
                                  onPressed: () => _applyTimePreset(
                                      ['08:00', '14:00', '20:00']),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Time Slots Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Daily Dose Times (${_timesOfDay.length}/${AppConstants.maxTimeSlots})',
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _timesOfDay.length >=
                                        AppConstants.maxTimeSlots
                                    ? null
                                    : _addTimeSlot,
                                icon: const Icon(Icons.add_alarm_rounded,
                                    size: 18),
                                label: const Text('Add Time'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_scheduleInlineError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                _scheduleInlineError!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ...List.generate(_timesOfDay.length, (idx) {
                            final settingsVm =
                                context.watch<SettingsViewModel?>();
                            final use24h = settingsVm?.is24HourFormat ?? false;
                            final formattedSlot =
                                TimeFormatter.formatTimeString(
                              _timesOfDay[idx],
                              is24Hour: use24h,
                            );
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Material(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(14),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onTap: () => _pickTime(idx),
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.access_time_filled_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  formattedSlot,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  'Dose #${idx + 1} • Tap to change alarm time',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Edit dose time $formattedSlot',
                                      onPressed: () => _pickTime(idx),
                                    ),
                                    if (_timesOfDay.length >
                                        AppConstants.minTimeSlots)
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: theme.colorScheme.error,
                                        ),
                                        tooltip:
                                            'Remove dose time $formattedSlot',
                                        onPressed: () => _removeTimeSlot(idx),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          }),
                          if (_frequency == ScheduleFrequency.everyXHours &&
                              _timesOfDay.length == 1) ...[
                            const SizedBox(height: 6),
                            Builder(
                              builder: (context) {
                                final settingsVm =
                                    context.watch<SettingsViewModel?>();
                                final use24h =
                                    settingsVm?.is24HourFormat ?? false;
                                final interval = int.tryParse(
                                        _intervalHoursController.text.trim()) ??
                                    6;
                                final previewSlots =
                                    ScheduleExpander.effectiveTimesOfDay(
                                  DoseSchedule(
                                    frequency: ScheduleFrequency.everyXHours,
                                    timesOfDay: _timesOfDay,
                                    intervalValue: interval,
                                    startDate: DateTime.now(),
                                  ),
                                );
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Generated 24-Hour Schedule (${previewSlots.length} doses/day):',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        previewSlots
                                            .map((t) =>
                                                TimeFormatter.formatTimeString(
                                                    t,
                                                    is24Hour: use24h))
                                            .join(' • '),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Course Duration / Optional End Date
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Course End Date (Optional)',
                                    style: theme.textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _endDate == null
                                        ? 'Ongoing (no end date)'
                                        : 'Ends ${DateFormat('MMM d, yyyy').format(_endDate!)}',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              if (_endDate != null)
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _endDate = null;
                                      _isDirty = true;
                                    });
                                  },
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 16),
                                  label: const Text('Clear'),
                                ),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final todayStart =
                                      DateTime(now.year, now.month, now.day);
                                  final initialDate = (_endDate != null &&
                                          !_endDate!.isBefore(todayStart))
                                      ? _endDate!
                                      : todayStart.add(const Duration(days: 7));
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: initialDate,
                                    firstDate: todayStart,
                                    lastDate:
                                        now.add(const Duration(days: 3650)),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() {
                                      _endDate = DateTime(
                                        picked.year,
                                        picked.month,
                                        picked.day,
                                        23,
                                        59,
                                        59,
                                      );
                                      _isDirty = true;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.event_rounded, size: 18),
                                label: Text(_endDate == null
                                    ? 'End Date'
                                    : 'Change'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('Ongoing'),
                                  selected: _endDate == null,
                                  onSelected: (_) {
                                    setState(() {
                                      _endDate = null;
                                      _isDirty = true;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                for (final days in const [5, 7, 14, 30])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ActionChip(
                                      label: Text('$days Days'),
                                      onPressed: () {
                                        final target = DateTime.now()
                                            .add(Duration(days: days));
                                        setState(() {
                                          _endDate = DateTime(
                                            target.year,
                                            target.month,
                                            target.day,
                                            23,
                                            59,
                                            59,
                                          );
                                          _isDirty = true;
                                        });
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // CARD 3: Alarm Sound & Vibration (for Scheduled medications)
                    if (!_isPrn)
                      _buildSectionCard(
                        context: context,
                        icon: Icons.notifications_active_rounded,
                        title: '3. Alarm Sound & Vibration',
                        subtitle:
                            'Choose the ringtone and vibration alert for this alarm',
                        children: [
                          if (_availableSounds.isNotEmpty)
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'sound_dropdown_${effectiveDropdownSoundId}_${_availableSounds.length}',
                              ),
                              initialValue: effectiveDropdownSoundId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Medication Alarm Tone',
                                prefixIcon: Icon(Icons.music_note_outlined),
                              ),
                              items: _availableSounds.map((sound) {
                                return DropdownMenuItem<String>(
                                  value: sound.id,
                                  child: Text(
                                    sound.isCustom
                                        ? 'Custom: ${sound.displayName}'
                                        : sound.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final option = _availableSounds
                                      .cast<AlarmSoundItem?>()
                                      .firstWhere(
                                        (s) => s?.id == val,
                                        orElse: () => null,
                                      );
                                  if (option == null) return;
                                  setState(() {
                                    _selectedSoundId = option.id;
                                    _customSoundPath = option.localFilePath;
                                    _isDirty = true;
                                  });
                                  AlarmSoundService().playPreview(
                                    soundId: option.id,
                                    customPath: option.localFilePath,
                                  );
                                }
                              },
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    AlarmSoundService().playPreview(
                                      soundId: _selectedSoundId,
                                      customPath: _customSoundPath,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.play_circle_outline,
                                    size: 20,
                                  ),
                                  label: const Text('Preview Tone'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _handleImportCustomSound,
                                  icon: const Icon(
                                    Icons.upload_file_outlined,
                                    size: 20,
                                  ),
                                  label: const Text('Upload Audio'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Vibrate on Alarm',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Vibrate device when alarm rings',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            value: _vibrationEnabled,
                            onChanged: (v) => setState(() {
                              _vibrationEnabled = v;
                              _isDirty = true;
                            }),
                          ),
                        ],
                      ),

                    const SizedBox(height: 8),

                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveMedication,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : (_isEditing
                                ? 'Update Medication'
                                : 'Save Medication'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormDropdownRow(MedicationForm form) {
    return Row(
      children: [
        Image.asset(
          PillAvatar.assetPathForForm(form),
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.medication_rounded, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${MedicationValidator.displayNameForForm(form)} (${MedicationValidator.unitForForm(form)})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
