import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/status_colors.dart';
import '../../services/alarm_sound_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../auth/reauth_dialog.dart';
import 'change_password_dialog.dart';
import 'global_alarm_sound_manager_view.dart';
import 'reliability_check_view.dart';

/// Reorganized Settings view structured into clear sections:
/// - General
/// - Medication Reminders & Alarm Sounds (navigating to GlobalAlarmSoundManagerView)
/// - Account & Profile
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  List<AlarmSoundItem> _availableSounds = AlarmSoundService.builtInSounds;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final sounds = await AlarmSoundService().getAllSounds();
    if (mounted) {
      setState(() => _availableSounds = sounds);
    }
  }

  String _resolveSoundDisplayName(String soundId) {
    final matched = _availableSounds.firstWhere(
      (s) => s.id == soundId,
      orElse: () => AlarmSoundService.builtInSounds.first,
    );
    return matched.displayName;
  }

  Future<void> _openAlarmSoundManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const GlobalAlarmSoundManagerView(),
      ),
    );
    await _loadSounds();
  }

  Future<void> _openReliabilityCheck() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReliabilityCheckView(),
      ),
    );
  }

  Future<void> _showDeleteAccountConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account & Health Data?'),
        content: const Text(
          'Under the Philippine Data Privacy Act (RA 10173), this permanently erases your account, medications, dose history, and emergency card. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue to Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final reauthSuccess = await ReauthDialog.show(
      context,
      title: 'Confirm Account Erasure',
      reason:
          'Under RA 10173, permanently deleting your health records and account requires re-authenticating.',
      allowEmailOtp: false,
    );

    if (!reauthSuccess || !context.mounted) return;

    final authVm = context.read<AuthViewModel>();
    final success = await authVm.deleteAccountAndData();
    if (success && context.mounted) {
      context.go('/login');
    } else if (context.mounted && authVm.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authVm.errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleOpenChangePassword(
    BuildContext context, {
    required bool isSetPasswordMode,
  }) async {
    final updated = await ChangePasswordDialog.show(
      context,
      isSetPasswordMode: isSetPasswordMode,
    );
    if (updated && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSetPasswordMode
                ? 'Password set successfully.'
                : 'Password updated successfully. Other devices may need to sign in again.',
          ),
        ),
      );
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final authVm = context.read<AuthViewModel>();
    final unsyncedCount = await authVm.flushAndCountUnsyncedIntakes();
    if (!context.mounted) return;

    if (unsyncedCount > 0) {
      final confirmSignOut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsynced Doses Found'),
          content: Text(
            'You have $unsyncedCount ${unsyncedCount == 1 ? 'dose' : 'doses'} not yet synced to the cloud. Signing out now will discard unsynced offline records. Sign out anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay Signed In'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out Anyway'),
            ),
          ],
        ),
      );
      if (confirmSignOut != true || !context.mounted) return;
    }

    await authVm.signOut(discardPendingIntakes: true);
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsVm = context.watch<SettingsViewModel>();
    final authVm = context.watch<AuthViewModel>();
    final currentToneName = _resolveSoundDisplayName(settingsVm.alarmSound);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Settings & Privacy'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Section 1: General
              Text(
                'General',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dark_mode_outlined),
                      title: const Text('Theme Mode'),
                      subtitle: Text(
                        settingsVm.themeMode == ThemeMode.light
                            ? 'Light (Baby Blue)'
                            : settingsVm.themeMode == ThemeMode.dark
                                ? 'Dark (Deep Blue)'
                                : 'System Default',
                      ),
                      trailing: DropdownButton<ThemeMode>(
                        value: settingsVm.themeMode,
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System Default'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light (Baby Blue)'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark (Deep Blue)'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) settingsVm.setThemeMode(mode);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.access_time_rounded),
                      title: const Text('24-Hour Time Format'),
                      subtitle: const Text(
                        'Show dose times in 24-hour clock format (e.g. 14:30)',
                      ),
                      value: settingsVm.is24HourFormat,
                      onChanged: (val) => settingsVm.set24HourFormat(val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.contrast_rounded,
                        color: StatusColors.of(context)?.lowStock ??
                            theme.colorScheme.tertiary,
                      ),
                      title: const Text('Senior High-Contrast Mode'),
                      subtitle: const Text(
                        'High-contrast outlines and maximum legibility',
                      ),
                      value: settingsVm.isHighContrast,
                      onChanged: (val) => settingsVm.setHighContrast(val),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Notification & Alarm Reliability'),
                      subtitle: const Text(
                        'Check device permissions for reliable alarm delivery',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openReliabilityCheck,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.family_restroom_rounded),
                      title: const Text('Caregiver & Family Sharing'),
                      subtitle: const Text(
                        'Share read-only schedule access or monitor a loved one',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/caregiver'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceLg),

              // Section 2: Medication Reminders & Alarm Sounds
              Text(
                'Medication Reminders & Alarm Sounds',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: const Text(
                        'Medication Alarm Sounds',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Default tone: $currentToneName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openAlarmSoundManager,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.snooze_rounded),
                      title: const Text('Default Snooze Duration'),
                      trailing: DropdownButton<int>(
                        value: const [5, 10, 15, 20, 30]
                                .contains(settingsVm.snoozeMinutes)
                            ? settingsVm.snoozeMinutes
                            : AppConstants.defaultSnoozeDurationMinutes,
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 minutes')),
                          DropdownMenuItem(
                              value: 10, child: Text('10 minutes')),
                          DropdownMenuItem(
                              value: 15, child: Text('15 minutes')),
                          DropdownMenuItem(
                              value: 20, child: Text('20 minutes')),
                          DropdownMenuItem(
                              value: 30, child: Text('30 minutes')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsVm.setSnoozeMinutes(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceLg),

              // Section 3: Account & Profile
              Text(
                'Account & Profile',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: theme.colorScheme.primary,
                            child: Text(
                              authVm.currentUserDisplayName.isNotEmpty
                                  ? authVm.currentUserDisplayName[0]
                                      .toUpperCase()
                                  : 'P',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  authVm.currentUserDisplayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  authVm.currentUserEmail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.g_mobiledata_rounded, size: 32),
                      title: const Text('Google Account'),
                      subtitle: Text(
                        authVm.isGoogleLinked ? 'Connected' : 'Not connected',
                        style: TextStyle(
                          color: authVm.isGoogleLinked
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: authVm.isGoogleLinked
                          ? OutlinedButton(
                              onPressed: authVm.isLoading
                                  ? null
                                  : () async {
                                      final success =
                                          await authVm.unlinkGoogleAccount();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              success
                                                  ? 'Google account unlinked.'
                                                  : authVm.errorMessage ??
                                                      'Failed to unlink.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: const Text('Unlink'),
                            )
                          : FilledButton.tonal(
                              onPressed: authVm.isLoading
                                  ? null
                                  : () async {
                                      final success =
                                          await authVm.linkGoogleAccount();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              success
                                                  ? 'Google account linked successfully.'
                                                  : authVm.errorMessage ??
                                                      'Failed to link.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              child: const Text('Link Google'),
                            ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_reset_rounded),
                      title: Text(
                        authVm.hasPasswordProvider
                            ? 'Change Password'
                            : 'Set a Password',
                      ),
                      subtitle: Text(
                        authVm.hasPasswordProvider
                            ? 'Update your account password'
                            : 'Add email & password sign-in to your account',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _handleOpenChangePassword(
                        context,
                        isSetPasswordMode: !authVm.hasPasswordProvider,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Sign Out'),
                      onTap: () => _handleSignOut(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Delete Account & All Data',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Permanently erase all personal & health data',
                      ),
                      onTap: () => _showDeleteAccountConfirmation(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Production App Information Footer
              Center(
                child: Column(
                  children: [
                    Text(
                      'RemedyTrack v1.0.0 (Production Build)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Private & Protected Health Data',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
