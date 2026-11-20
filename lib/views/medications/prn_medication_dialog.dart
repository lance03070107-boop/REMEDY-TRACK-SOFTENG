import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/theme/status_colors.dart';
import '../../models/medication.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';

/// Modal dialog for logging As-Needed doses with safety validation warnings.
class PrnMedicationDialog extends StatefulWidget {
  final List<Medication> prnMedications;

  const PrnMedicationDialog({super.key, required this.prnMedications});

  @override
  State<PrnMedicationDialog> createState() => _PrnMedicationDialogState();
}

class _PrnMedicationDialogState extends State<PrnMedicationDialog> {
  late Medication _selectedMedication;

  @override
  void initState() {
    super.initState();
    _selectedMedication = widget.prnMedications.first;
  }

  Future<void> _recordPrnDose() async {
    final medVm = context.read<MedicationViewModel>();
    final intakeVm = context.read<IntakeViewModel>();
    final invVm = context.read<InventoryViewModel>();

    // Run safety validation
    final validation = medVm.validatePrnIntake(
      _selectedMedication,
      intakeVm.allLogs,
    );

    if (!validation.isSafe) {
      final statusColors =
          Theme.of(context).extension<StatusColors>() ?? StatusColors.light;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: statusColors.lowStock),
              const SizedBox(width: 8),
              const Flexible(child: Text('Safety Limit Reached')),
            ],
          ),
          content:
              Text(validation.warningMessage ?? AppStrings.prnIntervalWarning),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      await intakeVm.logPrnDose(
        medication: _selectedMedication,
      );
      if (intakeVm.isEligibleForAutoDecrement(_selectedMedication) &&
          !intakeVm.hasError) {
        invVm.adjustLocalStock(
            _selectedMedication.id, -_selectedMedication.doseAmount);
      }
    } catch (e, s) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e, s).message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    if (intakeVm.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(intakeVm.errorMessage ??
              'Could not save this dose. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Logged dose for ${_selectedMedication.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.prnTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose a medicine:'),
          const SizedBox(height: 8),
          DropdownButtonFormField<Medication>(
            initialValue: _selectedMedication,
            isExpanded: true,
            items: widget.prnMedications.map((m) {
              return DropdownMenuItem(
                value: m,
                child: Text(
                  '${m.name} (${m.strength})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedMedication = val);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _recordPrnDose,
          child: const Text('Record Dose'),
        ),
      ],
    );
  }
}
