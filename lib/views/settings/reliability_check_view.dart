import 'package:flutter/material.dart';

import '../../core/theme/status_colors.dart';
import '../../services/permission_service.dart';

/// Interactive diagnostic screen auditing system permissions and OEM power-saving
/// restrictions for reliable medication alarm delivery.
class ReliabilityCheckView extends StatefulWidget {
  const ReliabilityCheckView({super.key});

  @override
  State<ReliabilityCheckView> createState() => _ReliabilityCheckViewState();
}

class _ReliabilityCheckViewState extends State<ReliabilityCheckView> {
  final PermissionService _permissionService = PermissionService();

  ReliabilityStatus _notifStatus = ReliabilityStatus.granted;
  ReliabilityStatus _exactAlarmStatus = ReliabilityStatus.granted;
  ReliabilityStatus _batteryStatus = ReliabilityStatus.granted;
  ReliabilityStatus _dndStatus = ReliabilityStatus.granted;
  ReliabilityStatus _fullScreenStatus = ReliabilityStatus.granted;
  ReliabilityStatus _overlayStatus = ReliabilityStatus.granted;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    setState(() => _isLoading = true);
    final notif = await _permissionService.checkNotificationPermission();
    final exact = await _permissionService.checkExactAlarmPermission();
    final battery = await _permissionService.checkBatteryOptimizationStatus();
    final dnd = await _permissionService.checkDoNotDisturbStatus();
    final canFsi = await _permissionService.canUseFullScreenIntent();
    final canOverlay = await _permissionService.canDrawOverlays();

    if (mounted) {
      setState(() {
        _notifStatus = notif;
        _exactAlarmStatus = exact;
        _batteryStatus = battery;
        _dndStatus = dnd;
        _fullScreenStatus =
            canFsi ? ReliabilityStatus.granted : ReliabilityStatus.denied;
        _overlayStatus =
            canOverlay ? ReliabilityStatus.granted : ReliabilityStatus.denied;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = StatusColors.of(context) ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);
    final okColor = statusColors.taken;
    final warnColor = statusColors.lowStock;
    final isAllHealthy = _notifStatus == ReliabilityStatus.granted &&
        _exactAlarmStatus == ReliabilityStatus.granted &&
        _batteryStatus == ReliabilityStatus.granted &&
        _fullScreenStatus == ReliabilityStatus.granted &&
        _overlayStatus == ReliabilityStatus.granted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder Reliability & Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recheck Diagnostics',
            onPressed: _refreshStatuses,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Top Health Banner
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: (isAllHealthy ? okColor : warnColor)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAllHealthy ? okColor : warnColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isAllHealthy
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: isAllHealthy ? okColor : warnColor,
                        size: 32,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAllHealthy
                                  ? 'All Alarm Settings Ready'
                                  : 'Reminders May Be Delayed',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isAllHealthy ? okColor : warnColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAllHealthy
                                  ? 'RemedyTrack can wake your screen and sound reminders at your scheduled times.'
                                  : 'Battery-saving settings may silence or delay alerts. Review the items below to allow alarms.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Diagnostic Items Header
                Text(
                  'Critical Android Permissions',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                // 0. Background Alarm Pop-up (Appear on top / SYSTEM_ALERT_WINDOW)
                _buildDiagnosticTile(
                  icon: Icons.open_in_new_rounded,
                  title: 'Background Alarm Pop-up (Appear on Top)',
                  description:
                      'Required so alarms pop up full-screen and ring like a real alarm clock over your home screen and other apps (instead of only showing a banner).',
                  status: _overlayStatus,
                  onFix: () async {
                    await _permissionService.openOverlaySettings();
                    await _refreshStatuses();
                  },
                ),

                // 1. Exact Alarm
                _buildDiagnosticTile(
                  icon: Icons.alarm_rounded,
                  title: 'Exact Alarm Scheduling',
                  description:
                      'Required by Android 12+ to ring at the exact minute rather than in opportunistic batches.',
                  status: _exactAlarmStatus,
                  onFix: () async {
                    await _permissionService.requestExactAlarmPermission();
                    await _refreshStatuses();
                  },
                ),

                // 2. Notifications
                _buildDiagnosticTile(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notification Alert Permission',
                  description:
                      'Required to display full-screen lock intents, banners, and Taken/Snooze/Skip buttons.',
                  status: _notifStatus,
                  onFix: () async {
                    await _permissionService.requestNotificationPermission();
                    await _refreshStatuses();
                  },
                ),

                // 3. Battery Optimization
                _buildDiagnosticTile(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Battery Optimization Exemption',
                  description:
                      'Exempts RemedyTrack from Android Doze mode so alarms ring when the device is idle.',
                  status: _batteryStatus,
                  onFix: () async {
                    await _permissionService.requestIgnoreBatteryOptimization();
                    await _refreshStatuses();
                  },
                ),

                // 4. Do Not Disturb
                _buildDiagnosticTile(
                  icon: Icons.do_not_disturb_on_rounded,
                  title: 'Do Not Disturb Policy Access',
                  description:
                      'Allows critical medication alerts to chime through silent or priority-only modes.',
                  status: _dndStatus,
                  onFix: () async {
                    await _permissionService.requestDoNotDisturbAccess();
                    await _refreshStatuses();
                  },
                ),

                // 5. Full-Screen Intent Alarm Clock Pop-ups (Android 14+)
                _buildDiagnosticTile(
                  icon: Icons.fullscreen_rounded,
                  title: 'Lock-Screen Alarm Pop-up (Alarm Clock Mode)',
                  description:
                      'Permits RemedyTrack to turn on the screen and present the alarm clock interface when the phone is locked (Android 14+).',
                  status: _fullScreenStatus,
                  onFix: () async {
                    await _permissionService.openFullScreenIntentSettings();
                    await _refreshStatuses();
                  },
                ),

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _permissionService.openAppSettings(),
                  icon: const Icon(Icons.settings_suggest_rounded),
                  label: const Text('Open System App Settings'),
                ),

                const SizedBox(height: 24),

                // OEM Brand Instructions
                Text(
                  'OEM Battery Saver Fixes (Philippines Devices)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildOEMGuide(
                  brand: 'Xiaomi / Redmi / POCO (MIUI / HyperOS)',
                  steps:
                      '1. Go to Settings > Apps > Manage Apps > RemedyTrack.\n2. Enable "Autostart".\n3. Set Battery Saver to "No restrictions".\n4. Lock the app in the Recent Apps carousel.',
                ),
                _buildOEMGuide(
                  brand: 'Oppo / Realme (ColorOS / RealmeUI)',
                  steps:
                      '1. Go to Settings > Battery > App Battery Management > RemedyTrack.\n2. Enable "Allow foreground & background activity" and "Allow auto-launch".\n3. Turn off "Sleep standby optimization".',
                ),
                _buildOEMGuide(
                  brand: 'Vivo / iQOO (FuntouchOS / OriginOS)',
                  steps:
                      '1. Go to Settings > Battery > High background power consumption > Toggle RemedyTrack ON.\n2. Go to Settings > Applications > Autostart > Enable RemedyTrack.',
                ),
                _buildOEMGuide(
                  brand: 'Samsung Galaxy (One UI)',
                  steps:
                      '1. Go to Settings > Apps > RemedyTrack > Battery > Select "Unrestricted".\n2. Go to Device Care > Battery > Background usage limits > Ensure RemedyTrack is NOT in "Deep sleeping apps".',
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _buildDiagnosticTile({
    required IconData icon,
    required String title,
    required String description,
    required ReliabilityStatus status,
    required VoidCallback onFix,
  }) {
    final isGranted = status == ReliabilityStatus.granted;
    final theme = Theme.of(context);
    final statusColors = theme.extension<StatusColors>() ??
        (theme.brightness == Brightness.dark
            ? StatusColors.dark
            : StatusColors.light);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(
          icon,
          color: isGranted ? statusColors.taken : statusColors.missed,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        trailing: isGranted
            ? Chip(
                label: Text('ACTIVE',
                    style: TextStyle(
                        color: statusColors.taken,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
                backgroundColor: statusColors.taken.withValues(alpha: 0.14),
                visualDensity: VisualDensity.compact,
              )
            : FilledButton.tonal(
                onPressed: onFix,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor:
                      statusColors.lowStock.withValues(alpha: 0.2),
                  foregroundColor: statusColors.lowStock,
                ),
                child: const Text('Fix',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  Widget _buildOEMGuide({required String brand, required String steps}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(brand,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        leading: const Icon(Icons.phone_android_rounded, size: 20),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child:
                Text(steps, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
