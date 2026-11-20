import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';
import '../../core/validation/medication_validator.dart';
import '../../models/inventory_item.dart';
import '../../models/medication.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/inventory_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/state_views.dart';

/// Dedicated Medicine Inventory & Stock Manager view.
/// Never displays fabricated stock for medications lacking an inventory record;
/// instead provides an explicit "Set Up Stock Now" flow and validates all refills/steps.
class InventoryManagerView extends StatefulWidget {
  const InventoryManagerView({super.key});

  @override
  State<InventoryManagerView> createState() => _InventoryManagerViewState();
}

class _InventoryManagerViewState extends State<InventoryManagerView> {
  String _searchQuery = '';
  String _selectedFilter = 'All'; // 'All', 'Low Stock', 'Out of Stock'
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Uses [InventoryItem.calculateDailyPrescribedRate] and [InventoryItem.estimatedDaysRemainingForMedication]
  /// as the single source of truth across all schedule frequencies and dosage forms.
  String _formatDaysRemaining(Medication med, InventoryItem item) {
    if (item.currentStock <= 0) return '0 days (Out of stock!)';
    if (med.isPrn || med.schedule == null || med.schedule!.timesOfDay.isEmpty) {
      return 'As-needed (manual stock)';
    }
    if (!MedicationValidator.supportsAutoDecrement(med.form)) {
      return 'Manual stock tracking (${MedicationValidator.unitForForm(med.form)} do not auto-deduct)';
    }

    final dailyRate = InventoryItem.calculateDailyPrescribedRate(med);
    final days = item.estimatedDaysRemainingForMedication(med);
    if (dailyRate <= 0 || days == null) return 'Schedule rate N/A';

    if (days <= 0) return 'Depletes today!';
    final formattedRate = MedicationValidator.formatQuantity(dailyRate);
    if (days == 1) return '1 day remaining ($formattedRate/day)';
    return '~$days days remaining ($formattedRate/day)';
  }

  Future<void> _handleQuickAdd(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
    InventoryItem item,
    double amount,
  ) async {
    final result = await invVm.refillItem(item.id, amount, form: med.form);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Added ${MedicationValidator.formatQuantity(amount)} ${item.unit} to ${med.name}.'
              : (result.errorOrNull?.message ?? 'Failed to refill stock.'),
        ),
        backgroundColor:
            result.isSuccess ? null : Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleStepDecrement(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
    InventoryItem item,
    double step,
  ) async {
    if (item.currentStock - step < AppConstants.minStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Stock cannot be less than 0.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final newStock = item.currentStock - step;
    final result = await invVm.updateInventoryDetails(
      itemId: item.id,
      currentStock: newStock,
      lowStockThreshold: item.lowStockThreshold,
      form: med.form,
    );
    if (!context.mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorOrNull?.message ?? 'Failed to update stock.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleStepIncrement(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
    InventoryItem item,
    double step,
  ) async {
    if (item.currentStock + step > AppConstants.maxStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock cannot exceed ${AppConstants.maxStock.toInt()} ${item.unit}.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final newStock = item.currentStock + step;
    final result = await invVm.updateInventoryDetails(
      itemId: item.id,
      currentStock: newStock,
      lowStockThreshold: item.lowStockThreshold,
      form: med.form,
    );
    if (!context.mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorOrNull?.message ?? 'Failed to update stock.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showSetupStockDialog(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
  ) async {
    final unit = MedicationValidator.unitForForm(med.form);
    final allowsDecimal = MedicationValidator.allowsDecimalStock(med.form);
    final defaultThreshold = MedicationValidator.calculateDefaultThreshold(med);
    final stockCtrl = TextEditingController(text: '30');
    final thresholdCtrl = TextEditingController(
      text: MedicationValidator.formatQuantity(defaultThreshold),
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set Up Stock for ${med.name}'),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                controller: stockCtrl,
                label:
                    '${MedicationValidator.stockFieldLabelForForm(med.form)} *',
                hint: '30',
                suffixText: unit,
                helperText: '0–${AppConstants.maxStock.toInt()} $unit',
                keyboardType:
                    TextInputType.numberWithOptions(decimal: allowsDecimal),
                inputFormatters:
                    MedicationValidator.stockFormattersForForm(med.form),
                validator: (v) =>
                    MedicationValidator.validateStock(v, form: med.form),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: thresholdCtrl,
                label: 'Low-Stock Alert Threshold *',
                hint: MedicationValidator.formatQuantity(defaultThreshold),
                suffixText: unit,
                helperText: 'Default = 7 days of supply',
                keyboardType:
                    TextInputType.numberWithOptions(decimal: allowsDecimal),
                inputFormatters:
                    MedicationValidator.stockFormattersForForm(med.form),
                validator: (v) =>
                    MedicationValidator.validateThreshold(v, form: med.form),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Stock'),
          ),
        ],
      ),
    );

    final rawStock = stockCtrl.text;
    final rawThreshold = thresholdCtrl.text;
    stockCtrl.dispose();
    thresholdCtrl.dispose();

    if (confirmed == true && context.mounted) {
      final stock = MedicationValidator.tryParseFiniteDouble(rawStock)!;
      final threshold =
          MedicationValidator.tryParseFiniteDouble(rawThreshold)!;
      final newItem = InventoryItem(
        id: 'inv_${med.id}',
        userId: med.userId,
        medicationId: med.id,
        currentStock: stock,
        unit: unit,
        lowStockThreshold: threshold,
        refillQuantity: stock > 0 ? stock : 30.0,
        lastRefillDate: DateTime.now(),
        notes: med.name,
      );
      final result = await invVm.setupInventoryItem(newItem, form: med.form);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isSuccess
                  ? 'Stock configured for ${med.name}.'
                  : (result.errorOrNull?.message ?? 'Failed to set up stock.'),
            ),
            backgroundColor:
                result.isSuccess ? null : Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showCustomRefillDialog(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
    InventoryItem item,
  ) async {
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
                'Current Balance: ${MedicationValidator.formatQuantity(item.currentStock)} / ${AppConstants.maxStock.toInt()} ${item.unit}',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: controller,
                label: 'Amount to Add *',
                hint: '1',
                suffixText: item.unit,
                helperText:
                    'Max total stock: ${AppConstants.maxStock.toInt()} ${item.unit}',
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Confirm Refill'),
          ),
        ],
      ),
    );

    final rawAmount = controller.text;
    controller.dispose();

    if (confirmed == true && context.mounted) {
      final amount =
          MedicationValidator.tryParseFiniteDouble(rawAmount) ?? 0.0;
      if (amount > 0) {
        await _handleQuickAdd(context, invVm, med, item, amount);
      }
    }
  }

  Future<void> _showEditThresholdDialog(
    BuildContext context,
    InventoryViewModel invVm,
    Medication med,
    InventoryItem item,
  ) async {
    final allowsDecimal = MedicationValidator.allowsDecimalStock(med.form);
    final controller = TextEditingController(
      text: MedicationValidator.formatQuantity(item.lowStockThreshold),
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.tune_rounded,
              color: Theme.of(ctx).extension<StatusColors>()?.lowStock ??
                  Theme.of(ctx).colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Low Stock Alert Level')),
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
                'RemedyTrack alerts you when stock drops to or below this amount.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: controller,
                label: 'Threshold (${item.unit}) *',
                hint: '7',
                suffixText: item.unit,
                helperText:
                    '0–${AppConstants.maxLowStockThreshold.toInt()} ${item.unit}',
                prefixIcon: Icons.notifications_active_outlined,
                keyboardType:
                    TextInputType.numberWithOptions(decimal: allowsDecimal),
                inputFormatters:
                    MedicationValidator.stockFormattersForForm(med.form),
                validator: (val) => MedicationValidator.validateThreshold(
                  val,
                  form: med.form,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Alert Level'),
          ),
        ],
      ),
    );

    final rawThreshold = controller.text;
    controller.dispose();

    if (confirmed == true && context.mounted) {
      final newThreshold =
          MedicationValidator.tryParseFiniteDouble(rawThreshold)!;
      final result = await invVm.updateThreshold(
        item.id,
        newThreshold,
        form: med.form,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isSuccess
                  ? 'Low stock alert set to ${MedicationValidator.formatQuantity(newThreshold)} ${item.unit}.'
                  : (result.errorOrNull?.message ??
                      'Failed to update alert threshold.'),
            ),
            backgroundColor:
                result.isSuccess ? null : Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>();
    final medVm = context.watch<MedicationViewModel>();
    final invVm = context.watch<InventoryViewModel>();
    final caregiverVm = context.watch<CaregiverViewModel>();
    final authVm = context.watch<AuthViewModel>();

    final medications = medVm.medications;
    final inventoryItems = invVm.inventoryItems;

    // Build honest paired medication & optional inventory list (never fabricate stock!)
    final List<({Medication med, InventoryItem? item})> pairedList = [];
    for (final med in medications) {
      final existingItem = inventoryItems.cast<InventoryItem?>().firstWhere(
            (i) =>
                i != null &&
                (i.medicationId == med.id || i.id == 'inv_${med.id}'),
            orElse: () => null,
          );
      pairedList.add((med: med, item: existingItem));
    }

    // Filter by search query
    var filtered = pairedList.where((pair) {
      final q = _searchQuery.toLowerCase().trim();
      if (q.isEmpty) return true;
      final name = pair.med.name.toLowerCase();
      return name.contains(q);
    }).toList();

    // Filter by stock status
    if (_selectedFilter == 'Low Stock') {
      filtered = filtered
          .where(
            (pair) =>
                pair.item != null &&
                pair.item!.isLowStock &&
                pair.item!.currentStock > 0,
          )
          .toList();
    } else if (_selectedFilter == 'Out of Stock') {
      filtered = filtered
          .where((pair) => pair.item != null && pair.item!.currentStock <= 0)
          .toList();
    }

    final totalCount = pairedList.length;
    final lowStockCount =
        pairedList.where((p) => p.item != null && p.item!.isLowStock).length;
    final outOfStockCount = pairedList
        .where((p) => p.item != null && p.item!.currentStock <= 0)
        .length;

    final lowStockColor = statusColors?.lowStock ?? theme.colorScheme.tertiary;
    final takenColor = statusColors?.taken ?? theme.colorScheme.secondary;
    final missedColor = statusColors?.missed ?? theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication Stock'),
        actions: [
          if (!caregiverVm.isCaregiverMode)
            IconButton(
              tooltip: 'Add New Medication',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => context.push('/medications/add'),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final uid = caregiverVm.activeProfileId ?? authVm.currentUserId;
          if (uid.isNotEmpty) {
            medVm.retry(uid);
            invVm.retry(uid);
          }
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          children: [
            // KPI Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Total Medicines',
                    value: MedicationValidator.formatCompactStockCount(
                        totalCount.toDouble()),
                    icon: Icons.medication_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Low Stock',
                    value: MedicationValidator.formatCompactStockCount(
                        lowStockCount.toDouble()),
                    icon: Icons.warning_amber_rounded,
                    color: lowStockCount > 0 ? lowStockColor : takenColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Out of Stock',
                    value: MedicationValidator.formatCompactStockCount(
                        outOfStockCount.toDouble()),
                    icon: Icons.error_outline_rounded,
                    color: outOfStockCount > 0
                        ? missedColor
                        : theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              controller: _searchController,
              maxLength: AppConstants.maxMedicationNameLength,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Search medicine stocks by name...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    'All',
                    'All ($totalCount)',
                    theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Low Stock',
                    'Low Stock ($lowStockCount)',
                    lowStockColor,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Out of Stock',
                    'Out of Stock ($outOfStockCount)',
                    missedColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content Body
            if (medVm.isLoading || invVm.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: LoadingView(
                  message: 'Loading medicine inventory balances...',
                ),
              )
            else if ((medVm.hasError || invVm.hasError) && pairedList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: ErrorStateView(
                  message: invVm.errorMessage ??
                      medVm.errorMessage ??
                      'Failed to load inventory.',
                  onRetry: () {
                    final uid =
                        caregiverVm.activeProfileId ?? authVm.currentUserId;
                    if (uid.isNotEmpty) {
                      medVm.retry(uid);
                      invVm.retry(uid);
                    }
                  },
                ),
              )
            else if (pairedList.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: EmptyStateView(
                  icon: Icons.inventory_2_outlined,
                  title: 'No Medicines in Inventory',
                  subtitle:
                      'Tap the "+" button above to add a medication and establish its stock balance.',
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: EmptyStateView(
                  icon: Icons.search_off_rounded,
                  title: 'No Matching Stock Records',
                  subtitle:
                      'No medicines match the selected filter "$_selectedFilter".',
                ),
              )
            else
              ...filtered.map((pair) {
                final med = pair.med;
                final item = pair.item;

                if (item == null) {
                  return _buildUnconfiguredCard(
                    context,
                    theme: theme,
                    invVm: invVm,
                    med: med,
                    isCaregiverMode: caregiverVm.isCaregiverMode,
                  );
                }

                final isLow = item.isLowStock;
                final isOut = item.currentStock <= 0;
                final badgeColor = isOut
                    ? missedColor
                    : isLow
                        ? lowStockColor
                        : takenColor;
                final badgeIcon = isOut
                    ? Icons.error_outline_rounded
                    : isLow
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded;
                final badgeText = isOut
                    ? 'EMPTY'
                    : isLow
                        ? 'LOW STOCK'
                        : 'IN STOCK';

                return Card(
                  key: ValueKey('inv_card_${med.id}'),
                  margin: const EdgeInsets.only(bottom: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isOut
                          ? missedColor
                          : isLow
                              ? lowStockColor
                              : theme.colorScheme.outlineVariant,
                      width: (isLow || isOut) ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PillAvatar.fromMedication(
                              medication: med,
                              size: 46,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    med.name,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${med.strength} • ${MedicationValidator.displayNameForForm(med.form)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Semantics(
                              label: 'Stock status for ${med.name}: $badgeText',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      badgeIcon,
                                      size: 14,
                                      color: badgeColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      badgeText,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Stock Display & Days Forecast
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.inventory_2_rounded,
                                        size: 20,
                                        color: isOut
                                            ? missedColor
                                            : isLow
                                                ? lowStockColor
                                                : theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Stock Left:',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${MedicationValidator.formatQuantity(item.currentStock)} ${item.unit}',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isOut
                                          ? missedColor
                                          : isLow
                                              ? lowStockColor
                                              : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _formatDaysRemaining(med, item),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: (isLow || isOut)
                                            ? lowStockColor
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Action Buttons Bar
                        if (!caregiverVm.isCaregiverMode)
                          Row(
                            children: [
                              IconButton.outlined(
                                tooltip:
                                    'Deduct 1 ${MedicationValidator.singularUnitForForm(med.form)}',
                                icon: const Icon(Icons.remove, size: 18),
                                onPressed: item.currentStock > 0
                                    ? () => _handleStepDecrement(
                                          context,
                                          invVm,
                                          med,
                                          item,
                                          1.0,
                                        )
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: const Size(
                                    60,
                                    DesignTokens.minTouchTarget,
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text(
                                  '+1',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                onPressed:
                                    item.currentStock < AppConstants.maxStock
                                        ? () => _handleStepIncrement(
                                              context,
                                              invVm,
                                              med,
                                              item,
                                              1.0,
                                            )
                                        : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: DesignTokens.minTouchTarget,
                                  ),
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(
                                        64,
                                        DesignTokens.minTouchTarget,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Refill',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onPressed: item.currentStock <
                                            AppConstants.maxStock
                                        ? () => _showCustomRefillDialog(
                                              context,
                                              invVm,
                                              med,
                                              item,
                                            )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded),
                                tooltip: 'Inventory Actions for ${med.name}',
                                onSelected: (val) {
                                  if (val == 'custom') {
                                    _showCustomRefillDialog(
                                      context,
                                      invVm,
                                      med,
                                      item,
                                    );
                                  } else if (val == 'threshold') {
                                    _showEditThresholdDialog(
                                      context,
                                      invVm,
                                      med,
                                      item,
                                    );
                                  } else if (val == 'edit_med') {
                                    context.push('/medications/edit/${med.id}');
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                    value: 'custom',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_note_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Custom Refill Amount'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'threshold',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.notifications_outlined,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Edit Alert Threshold'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit_med',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.medication_outlined,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Edit Medication Details'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildUnconfiguredCard(
    BuildContext context, {
    required ThemeData theme,
    required InventoryViewModel invVm,
    required Medication med,
    required bool isCaregiverMode,
  }) {
    return Card(
      key: ValueKey('inv_unconfigured_${med.id}'),
      margin: const EdgeInsets.only(bottom: 14.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PillAvatar.fromMedication(medication: med, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${med.strength} • ${MedicationValidator.displayNameForForm(med.form)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Not Tracked',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Track your current ${MedicationValidator.unitForForm(med.form)} count to enable automatic deduction and low-stock alerts.',
              style: theme.textTheme.bodySmall,
            ),
            if (!isCaregiverMode) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _showSetupStockDialog(context, invVm, med),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Track Stock'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Semantics(
      label: '$title: $value',
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const Spacer(),
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, Color accentColor) {
    final isSelected = _selectedFilter == filterKey;
    final theme = Theme.of(context);

    return Semantics(
      label: '$label inventory filter',
      selected: isSelected,
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val) setState(() => _selectedFilter = filterKey);
        },
        selectedColor: accentColor.withValues(alpha: 0.2),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? accentColor : theme.colorScheme.onSurface,
        ),
        side: BorderSide(
          color: isSelected ? accentColor : theme.colorScheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
