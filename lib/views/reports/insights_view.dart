import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/scheduling/schedule_expander.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/time_formatter.dart';
import '../../models/intake_log.dart';
import '../../models/medication.dart';
import '../../viewmodels/adherence_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/caregiver_viewmodel.dart';
import '../../viewmodels/intake_viewmodel.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../widgets/pill_avatar.dart';
import '../widgets/progress_ring.dart';
import '../widgets/state_views.dart';
import '../widgets/status_chip.dart';

/// Unified Insights Screen merging Adherence Analytics, Time-of-Day Pattern Insights,
/// 1-Tap Doctor PDF Export, and Chronological Intake History Logs.
class InsightsView extends StatefulWidget {
  final int initialTabIndex;

  const InsightsView({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handlePdfExport(
    AdherenceViewModel adherenceVm,
    AuthViewModel authVm,
    MedicationViewModel medVm,
    IntakeViewModel intakeVm,
  ) async {
    final caregiverVm = context.read<CaregiverViewModel?>();
    final isCaregiver = caregiverVm?.isCaregiverMode ?? false;
    final targetUserId = caregiverVm?.activeProfileId ?? authVm.currentUserId;
    final targetPatientName = isCaregiver
        ? (caregiverVm?.activeProfileName ?? 'Patient')
        : authVm.currentUserDisplayName;
    final targetPatientEmail = isCaregiver
        ? (caregiverVm?.activeProfileEmail ?? 'Caregiver Read-Only View')
        : authVm.currentUserEmail;

    setState(() => _isExportingPdf = true);
    try {
      List<IntakeLog> logsForReport = intakeVm.allLogs;
      if (authVm.isAuthenticated && targetUserId.isNotEmpty) {
        final now = DateTime.now();
        final thirtyDaysAgo = now.subtract(const Duration(days: 30));
        final rangeLogs = await adherenceVm.loadLogsForDateRange(
          targetUserId,
          thirtyDaysAgo,
          now,
        );
        logsForReport = rangeLogs;
      }

      await adherenceVm.exportReportPdf(
        patientName: targetPatientName,
        patientEmail: targetPatientEmail,
        medications: medVm.medications,
        logs: logsForReport,
      );
    } catch (e, s) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorMapper.map(e, s).message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adherenceVm = context.watch<AdherenceViewModel>();
    final intakeVm = context.watch<IntakeViewModel>();
    final medVm = context.watch<MedicationViewModel>();
    final authVm = context.watch<AuthViewModel>();
    final settingsVm = context.watch<SettingsViewModel?>();
    final is24h = settingsVm?.is24HourFormat ?? false;

    if (intakeVm.isLoading || medVm.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insights & Analytics')),
        body:
            const LoadingView(message: 'Loading health records & analytics...'),
      );
    }

    final hasData = intakeVm.allLogs.isNotEmpty || medVm.medications.isNotEmpty;
    if ((intakeVm.hasError || medVm.hasError) && !hasData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insights & Analytics')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ErrorStateView(
              message: intakeVm.errorMessage ??
                  medVm.errorMessage ??
                  'Failed to load records.',
              onRetry: () {
                if (authVm.isAuthenticated) {
                  final uid =
                      context.read<CaregiverViewModel?>()?.activeProfileId ??
                          authVm.currentUserId;
                  intakeVm.clearError();
                  medVm.clearError();
                  intakeVm.retry(uid);
                  medVm.retry(uid);
                }
              },
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights & Analytics'),
        actions: [
          IconButton(
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: AppStrings.actionExportPdf,
            onPressed: _isExportingPdf
                ? null
                : () => _handlePdfExport(
                      adherenceVm,
                      authVm,
                      medVm,
                      intakeVm,
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 1,
          tabs: const [
            Tab(
              icon: Icon(Icons.analytics_outlined),
              text: 'Progress & Stats',
            ),
            Tab(
              icon: Icon(Icons.history_rounded),
              text: 'Dose History',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (context.watch<CaregiverViewModel?>()?.isCaregiverMode ?? false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.secondaryContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    size: 18,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Caregiver Read-Only View — Viewing ${context.watch<CaregiverViewModel?>()?.activeProfileName ?? 'Patient'}\'s adherence analytics',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Progress & Stats
                _buildAnalyticsTab(
                    context, theme, adherenceVm, intakeVm, medVm, authVm),

                // Tab 2: Chronological Intake History Log
                _buildHistoryTab(context, theme, intakeVm, medVm, is24h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab(
    BuildContext context,
    ThemeData theme,
    AdherenceViewModel adherenceVm,
    IntakeViewModel intakeVm,
    MedicationViewModel medVm,
    AuthViewModel authVm,
  ) {
    if (intakeVm.allLogs.isEmpty) {
      return const Center(
        child: EmptyStateView(
          icon: Icons.bar_chart_rounded,
          title: 'No History Yet',
          subtitle:
              'Your scheduled and taken doses will appear here automatically.',
        ),
      );
    }

    final now = DateTime.now();
    final monthLogs = intakeVm.allLogs
        .where((l) =>
            !l.isPrn &&
            l.status != DoseStatus.snoozed &&
            l.scheduledTime.year == now.year &&
            l.scheduledTime.month == now.month)
        .toList();
    final hasMonthData = adherenceVm.hasScheduledAdherenceData(monthLogs);

    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    int todayExpectedCount = 0;
    for (final med in medVm.medications) {
      if (!med.isActive || med.isPrn || med.schedule == null) continue;
      final effectiveAnchor = (med.schedule!.updatedAt != null &&
              med.schedule!.updatedAt!.isAfter(med.createdAt))
          ? med.schedule!.updatedAt!
          : med.createdAt;
      todayExpectedCount += ScheduleExpander.expandOccurrences(
        medication: med,
        start: todayStart,
        end: todayEnd,
        createdAfter: effectiveAnchor,
      ).length;
    }

    final monthlyRate = adherenceVm.calculateMonthlyAdherence(intakeVm.allLogs);
    final streak = adherenceVm.calculateStreakDays(
      intakeVm.allLogs,
      todayExpectedCount: todayExpectedCount > 0 ? todayExpectedCount : null,
    );
    final weeklyPoints = adherenceVm.getPast7DaysBreakdown(intakeVm.allLogs);
    final pattern = adherenceVm.analyzeMissedDosePatterns(intakeVm.allLogs);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          children: [
            // Monthly Adherence Header Card
            Container(
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: DesignTokens.radiusContainer,
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ProgressRing(
                    progress: hasMonthData ? (monthlyRate / 100.0) : 0.0,
                    takenCount: hasMonthData ? (monthlyRate).round() : 0,
                    totalCount: hasMonthData ? 100 : 0,
                    size: 96,
                    strokeWidth: 9,
                  ),
                  const SizedBox(width: DesignTokens.spaceLg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('MMMM yyyy').format(now)} Progress',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          !hasMonthData
                              ? 'No scheduled doses recorded yet this month.'
                              : monthlyRate >= 80
                                  ? 'Great job! You are taking your medicines regularly and on time.'
                                  : 'Taking your daily doses regularly helps your treatment work best.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spaceMd),

            // Streak Metric Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: DesignTokens.radiusCard,
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: theme.colorScheme.tertiary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$streak Days Active Streak',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Days in a row with all scheduled doses taken on time.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXl),

            // Weekly Trend BarChart
            Text(
              'Past 7 Days Trend',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Container(
              height: 210,
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: DesignTokens.radiusCard,
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < weeklyPoints.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat('E').format(weeklyPoints[idx].date),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(weeklyPoints.length, (i) {
                    final p = weeklyPoints[i];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: p.percentage,
                          color: p.percentage >= 80
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          width: 18,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXl),

            // Time-of-Day Missed Pattern Analysis Card (Capstone Specific Requirement)
            Text(
              'Missed-Dose Pattern Analysis',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Container(
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: DesignTokens.radiusCard,
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.insights_rounded,
                        color: theme.colorScheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Time-of-Day Distribution',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pattern.insightSentence,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Slot Breakdown Chips
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSlotBadge('Morning', pattern.morningMissed, theme),
                      _buildSlotBadge(
                          'Afternoon', pattern.afternoonMissed, theme),
                      _buildSlotBadge('Evening', pattern.eveningMissed, theme),
                      _buildSlotBadge('Night', pattern.nightMissed, theme),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXl),

            // Export to PDF Action
            SizedBox(
              height: DesignTokens.minTouchTarget,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: DesignTokens.radiusCard),
                ),
                onPressed: _isExportingPdf
                    ? null
                    : () => _handlePdfExport(
                          adherenceVm,
                          authVm,
                          medVm,
                          intakeVm,
                        ),
                icon: const Icon(Icons.print_rounded),
                label: const Text('Export Doctor Report (PDF)'),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceHuge),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotBadge(String label, int missedCount, ThemeData theme) {
    final hasMissed = missedCount > 0;
    final color =
        hasMissed ? theme.colorScheme.error : theme.colorScheme.outline;

    return Column(
      children: [
        Text(
          '$missedCount',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    ThemeData theme,
    IntakeViewModel intakeVm,
    MedicationViewModel medVm,
    bool is24h,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final allLogs = intakeVm.allLogs;

    final filteredLogs = allLogs.where((log) {
      if (query.isNotEmpty &&
          !log.medicationName.toLowerCase().contains(query)) {
        return false;
      }
      if (_selectedFilter == 'Taken') {
        return log.status == DoseStatus.taken || log.status == DoseStatus.late;
      }
      if (_selectedFilter == 'Missed') return log.status == DoseStatus.missed;
      if (_selectedFilter == 'Skipped') return log.status == DoseStatus.skipped;
      if (_selectedFilter == 'As-Needed') return log.isPrn;
      return true;
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          children: [
            // Search Bar & Filter Chips
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    maxLength: AppConstants.maxMedicationNameLength,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Search medication history...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Taken', 'Missed', 'Skipped', 'As-Needed']
                          .map((f) {
                        final isSelected = _selectedFilter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(f),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) setState(() => _selectedFilter = f);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Log List
            Expanded(
              child: filteredLogs.isEmpty
                  ? const Center(
                      child: EmptyStateView(
                        icon: Icons.history_rounded,
                        title: 'No Logs Found',
                        subtitle:
                            'No intake records match the selected filter.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spaceLg),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        final med =
                            medVm.medications.cast<Medication?>().firstWhere(
                                  (m) => m?.id == log.medicationId,
                                  orElse: () => null,
                                );

                        return Container(
                          margin: const EdgeInsets.only(
                              bottom: DesignTokens.spaceMd),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLowest,
                            borderRadius: DesignTokens.radiusCard,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.all(DesignTokens.spaceMd),
                            leading: med != null
                                ? PillAvatar.fromMedication(
                                    medication: med, size: 44)
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.medication_rounded),
                                  ),
                            title: Text(
                              log.medicationName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  'Scheduled: ${TimeFormatter.formatFriendlyDate(log.scheduledTime, includeDayOfWeek: false)}, ${TimeFormatter.formatTime(log.scheduledTime, is24Hour: is24h)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (log.recordedTime != null)
                                  Text(
                                    'Recorded: ${TimeFormatter.formatTime(log.recordedTime!, is24Hour: is24h)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (log.notes != null &&
                                    log.notes!.isNotEmpty &&
                                    !log.notes!.startsWith('Recorded via ') &&
                                    !log.notes!.startsWith('Skipped via '))
                                  Text(
                                    'Note: ${log.notes}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                              ],
                            ),
                            trailing:
                                StatusChip(status: log.status, compact: true),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
