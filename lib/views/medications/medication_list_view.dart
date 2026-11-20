import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/scheduling/schedule_expander.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';
import '../../core/utils/time_formatter.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/inventory_item.dart';
import '../../models/medication.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/state_views.dart';
import 'prn_medication_dialog.dart';

/// Medication registry displaying user prescriptions, search, filters,
/// stock health gauge with projected refill date, and quick refills.
class MedicationListView extends StatefulWidget {
  const MedicationListView({super.key});

  @override
  State<MedicationListView> createState() => _MedicationListViewState();
}

class _MedicationListViewState extends State<MedicationListView> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authVm = context.read<AuthViewModel>();
      final caregiverVm = context.read<CaregiverViewModel>();
      if (authVm.isAuthenticated) {
        final uid = caregiverVm.activeProfileId ?? authVm.currentUserId;
        context.read<MedicationViewModel>().listenToMedications(
              uid,
              isOwnProfile: !caregiverVm.isCaregiverMode,
            );
        context.read<InventoryViewModel>().listenToInventory(
              uid,
              isOwnProfile: !caregiverVm.isCaregiverMode,
            );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getRefillProjectionText(Medication med, InventoryItem item) {
    if (med.isPrn) {
      return 'As-needed (manual stock tracking)';
    }
    if (!MedicationValidator.supportsAutoDecrement(med.form)) {
      return 'Manual stock tracking (${MedicationValidator.unitForForm(med.form)})';
    }
    final projected = item.calculateProjectedRefillDate(med);
    if (projected == null) {
      return 'No schedule rate';
    }
    final now = DateTime.now();
    final difference =
        projected.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (difference <= 0) {
      return 'Refill needed today!';
    }
    return 'Refill by ${DateFormat.yMMMd().format(projected)} (~$difference days)';
  }

  Future<void> _confirmAndDeleteMedication(
    BuildContext context,
    Medication med,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${med.name}?'),
        content: Text(
          'This will permanently delete ${med.name}, cancel its scheduled reminders, and remove its inventory record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final medVm = context.read<MedicationViewModel>();
      final ok = await medVm.deleteMedication(med.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Deleted ${med.name}.'
                  : (medVm.errorMessage ?? 'Failed to delete ${med.name}.'),
            ),
            backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleAddOne(
    BuildContext context,
    Medication med,
    InventoryItem item,
  ) async {
    final unit = MedicationValidator.unitForForm(med.form);
    if (item.currentStock + 1.0 > AppConstants.maxStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock cannot exceed ${AppConstants.maxStock.toInt()} $unit.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final result = await context
        .read<InventoryViewModel>()
        .refillItem(item.id, 1.0, form: med.form);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSuccess
                ? 'Added 1 ${MedicationValidator.singularUnitForForm(med.form)} to ${med.name}.'
                : (result.errorOrNull?.message ?? 'Refill failed.'),
          ),
          backgroundColor:
              result.isSuccess ? null : Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showTypableRefillDialog(
    BuildContext context,
    Medication med,
    InventoryItem item,
  ) async {
    final unit = MedicationValidator.unitForForm(med.form);
    final allowsDecimal = MedicationValidator.allowsDecimalStock(med.form);
    final controller = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.add_shopping_cart_rounded,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Refill ${med.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Stock: ${MedicationValidator.formatQuantity(item.currentStock)} / ${AppConstants.maxStock.toInt()} $unit',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: controller,
                label: 'Amount to Add *',
                hint: '1',
                suffixText: unit,
                helperText:
                    'Max total stock: ${AppConstants.maxStock.toInt()} $unit',
                prefixIcon: Icons.add_circle_outline,
                keyboardType:
                    TextInputType.numberWithOptions(decimal: allowsDecimal),
                inputFormatters:
                    MedicationValidator.stockFormattersForForm(med.form),
                validator: (val) => MedicationValidator.validateRefillAmount(
                  val,
                  form: med.form,
                  currentStock: item.currentStock,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Add Stock'),
          ),
        ],
      ),
    );

    final rawAmount = controller.text;
    controller.dispose();

    if (confirmed == true && context.mounted) {
      final amount =
          MedicationValidator.tryParseFiniteDouble(rawAmount) ?? 0.0;
      if (amount <= 0) return;
      final result = await context
          .read<InventoryViewModel>()
          .refillItem(item.id, amount, form: med.form);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isSuccess
                  ? 'Added ${MedicationValidator.formatQuantity(amount)} $unit to ${med.name}.'
                  : (result.errorOrNull?.message ?? 'Refill failed.'),
            ),
            backgroundColor:
                result.isSuccess ? null : Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildInventorySection(
    BuildContext context,
    ThemeData theme,
    Medication med,
    InventoryItem? item,
    bool isCaregiverMode,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final statusColors = theme.extension<StatusColors>();
    final lowStockColor =
        statusColors?.lowStock ?? theme.colorScheme.tertiary;

    if (item == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: InkWell(
                onTap: () => context.go('/inventory'),
                child: Text(
                  'Stock not tracked yet • Tap to track stock',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isLowStock = item.isLowStock;
    final alertColor = isLowStock ? lowStockColor : theme.colorScheme.primary;
    final unit = MedicationValidator.unitForForm(med.form);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLowStock
              ? lowStockColor
              : theme.colorScheme.outlineVariant,
          width: isLowStock ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLowStock
                    ? Icons.warning_amber_rounded
                    : Icons.inventory_2_outlined,
                size: 18,
                color: alertColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stock: ${MedicationValidator.formatQuantity(item.currentStock)} $unit',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isLowStock ? lowStockColor : null,
                  ),
                ),
              ),
              if (isLowStock)
                Semantics(
                  label: 'Low stock alert for ${med.name}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: lowStockColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'LOW STOCK',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: lowStockColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _getRefillProjectionText(med, item),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCaregiverMode)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DesignTokens.minTouchTarget,
                      ),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(
                            52,
                            DesignTokens.minTouchTarget,
                          ),
                        ),
                        onPressed: item.currentStock < AppConstants.maxStock
                            ? () => _handleAddOne(context, med, item)
                            : null,
                        child: const Text(
                          '+1',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DesignTokens.minTouchTarget,
                      ),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: const Size(
                            72,
                            DesignTokens.minTouchTarget,
                          ),
                        ),
                        onPressed: item.currentStock < AppConstants.maxStock
                            ? () => _showTypableRefillDialog(context, med, item)
                            : null,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Refill'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medVm = context.watch<MedicationViewModel>();
    final caregiverVm = context.watch<CaregiverViewModel>();
    final inventoryVm = context.watch<InventoryViewModel>();
    final use24h = context.watch<SettingsViewModel?>()?.is24HourFormat ?? false;

    final query = _searchController.text.trim().toLowerCase();
    final filtered = medVm.medications.where((m) {
      final matchesSearch = m.name.toLowerCase().contains(query);
      if (_filter == 'Scheduled') return matchesSearch && !m.isPrn;
      if (_filter == 'PRN') return matchesSearch && m.isPrn;
      return matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Medication Stock',
            onPressed: () => context.go('/inventory'),
          ),
          IconButton(
            icon: const Icon(Icons.local_hospital_outlined),
            tooltip: 'Log As-Needed Dose',
            onPressed: () {
              final prnMeds = medVm.medications.where((m) => m.isPrn).toList();
              if (prnMeds.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No as-needed medications registered.'),
                  ),
                );
              } else {
                showDialog<void>(
                  context: context,
                  builder: (ctx) =>
                      PrnMedicationDialog(prnMedications: prnMeds),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Search medication by name...',
                  leading: const Icon(Icons.search),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'All', label: Text('All')),
                    ButtonSegment(value: 'Scheduled', label: Text('Scheduled')),
                    ButtonSegment(value: 'PRN', label: Text('As-Needed')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (set) =>
                      setState(() => _filter = set.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: medVm.isLoading
                    ? const LoadingView(message: 'Loading your medications...')
                    : (medVm.errorMessage != null && medVm.medications.isEmpty)
                        ? ErrorStateView(
                            message: medVm.errorMessage!,
                            onRetry: () {
                              final authVm = context.read<AuthViewModel>();
                              if (authVm.isAuthenticated) {
                                medVm.clearError();
                                medVm.retry(authVm.currentUserId);
                              }
                            },
                          )
                        : filtered.isEmpty
                            ? const EmptyStateView(
                                icon: Icons.medication_outlined,
                                title: 'No Medications Found',
                                subtitle:
                                    'Add your prescribed or over-the-counter medications to start tracking.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16.0),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final med = filtered[index];
                                  final item = inventoryVm.inventoryItems
                                      .cast<InventoryItem?>()
                                      .firstWhere(
                                        (i) => i?.medicationId == med.id,
                                        orElse: () => null,
                                      );

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: caregiverVm.isCaregiverMode
                                          ? null
                                          : () => context.push(
                                                '/medications/edit/${med.id}',
                                              ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                PillAvatar.fromMedication(
                                                  medication: med,
                                                  size: 48,
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        med.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme.textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${med.strength} • ${MedicationValidator.displayNameForForm(med.form)}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme.bodySmall
                                                            ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (caregiverVm.isCaregiverMode)
                                                  SizedBox(
                                                    width: 48,
                                                    height: 48,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.lock_outline,
                                                        size: 20,
                                                        color: theme.colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  SizedBox(
                                                    width: 48,
                                                    height: 48,
                                                    child: Center(
                                                      child: PopupMenuButton<
                                                          String>(
                                                        tooltip:
                                                            'Medication options for ${med.name}',
                                                        onSelected: (action) {
                                                          if (action ==
                                                              'edit') {
                                                            context.push(
                                                              '/medications/edit/${med.id}',
                                                            );
                                                          } else if (action ==
                                                              'delete') {
                                                            _confirmAndDeleteMedication(
                                                              context,
                                                              med,
                                                            );
                                                          }
                                                        },
                                                        itemBuilder: (ctx) => [
                                                          const PopupMenuItem(
                                                            value: 'edit',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .edit_outlined,
                                                                  size: 20,
                                                                ),
                                                                SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Text('Edit'),
                                                              ],
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .delete_outline,
                                                                  size: 20,
                                                                  color: theme
                                                                      .colorScheme
                                                                      .error,
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Text(
                                                                  'Delete',
                                                                  style:
                                                                      TextStyle(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .error,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            // Schedule summary
                                            if (med.isPrn)
                                              Text(
                                                'As-Needed (Max ${med.dailyMaxDose != null ? MedicationValidator.formatQuantity(med.dailyMaxDose!) : 'N/A'} ${MedicationValidator.unitForForm(med.form)}/day)',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme
                                                      .colorScheme.tertiary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            else if (med.schedule != null)
                                              Text(
                                                () {
                                                  final formattedTimes =
                                                      ScheduleExpander
                                                          .effectiveTimesOfDay(
                                                              med.schedule!)
                                                          .map((t) =>
                                                              TimeFormatter
                                                                  .formatTimeString(
                                                                      t,
                                                                      is24Hour:
                                                                          use24h))
                                                          .join(', ');
                                                  final endSuffix = med
                                                              .schedule!
                                                              .endDate !=
                                                          null
                                                      ? ' · Until ${DateFormat('MMM d, yyyy').format(med.schedule!.endDate!)}'
                                                      : '';
                                                  return 'Scheduled at $formattedTimes$endSuffix';
                                                }(),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            _buildInventorySection(
                                              context,
                                              theme,
                                              med,
                                              item,
                                              caregiverVm.isCaregiverMode,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: caregiverVm.isCaregiverMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/medications/add'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.actionAddMedication),
            ),
    );
  }
}
