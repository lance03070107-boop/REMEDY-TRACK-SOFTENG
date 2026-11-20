import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/alarm_sound_service.dart';
import '../../viewmodels/settings_viewmodel.dart';
import 'default_alarm_tone_view.dart';

/// Screen 1: Global Alarm Sound Manager.
/// Explains how the global default tone applies to medication reminders,
/// displays the navigable "Default Alarm Tone" row, provides a quick audio preview
/// action, and manages default snooze & escalation intervals.
class GlobalAlarmSoundManagerView extends StatefulWidget {
  const GlobalAlarmSoundManagerView({super.key});

  @override
  State<GlobalAlarmSoundManagerView> createState() =>
      _GlobalAlarmSoundManagerViewState();
}

class _GlobalAlarmSoundManagerViewState
    extends State<GlobalAlarmSoundManagerView> {
  List<AlarmSoundItem> _availableSounds = AlarmSoundService.builtInSounds;
  bool _isPreviewing = false;

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

  @override
  void dispose() {
    AlarmSoundService().stopPreview();
    super.dispose();
  }

  AlarmSoundItem _resolveSelectedSound(String soundId) {
    return _availableSounds.firstWhere(
      (s) => s.id == soundId,
      orElse: () => AlarmSoundService.builtInSounds.first,
    );
  }

  Future<void> _togglePreviewCurrent(AlarmSoundItem currentSound) async {
    final soundService = AlarmSoundService();
    if (_isPreviewing) {
      await soundService.stopPreview();
      if (mounted) setState(() => _isPreviewing = false);
    } else {
      if (mounted) setState(() => _isPreviewing = true);
      await soundService.playPreview(
        soundId: currentSound.id,
        customPath: currentSound.localFilePath,
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _isPreviewing) {
          setState(() => _isPreviewing = false);
        }
      });
    }
  }

  Future<void> _openDefaultAlarmToneScreen() async {
    await AlarmSoundService().stopPreview();
    if (!mounted) return;
    setState(() => _isPreviewing = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DefaultAlarmToneView(),
      ),
    );
    await _loadSounds();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsVm = context.watch<SettingsViewModel>();
    final selectedSound = _resolveSelectedSound(settingsVm.alarmSound);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Alarm Sound Manager'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Overview Card
              Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.surfaceContainerLow
                      : const Color(0xFFDDF2FC),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Medication Alarm Sounds',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your chosen alarm sound is used for all medication reminders and updates upcoming alarms automatically.',
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
              const SizedBox(height: 20),

              // Navigable Row: Default Alarm Tone -> Screen 2
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18.0,
                        vertical: 8.0,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
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
                        'Default Alarm Tone',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        selectedSound.displayName,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openDefaultAlarmToneScreen,
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () => _togglePreviewCurrent(selectedSound),
                        icon: Icon(
                          _isPreviewing
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_outline_rounded,
                          color: _isPreviewing
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                        label: Text(
                          _isPreviewing
                              ? 'Stop Tone Preview'
                              : 'Preview Current Tone (${selectedSound.displayName})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Snooze & Follow-Up Timing',
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
                      leading: const Icon(Icons.snooze_rounded),
                      title: const Text('Default Snooze Duration'),
                      subtitle: const Text(
                        'Minutes before a snoozed dose rings again',
                      ),
                      trailing: DropdownButton<int>(
                        value: settingsVm.snoozeMinutes,
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
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.add_alert_outlined),
                      title: const Text('Follow-Up Reminder'),
                      subtitle: const Text(
                        'Remind again if you miss the first alarm',
                      ),
                      trailing: DropdownButton<int>(
                        value: settingsVm.escalationMinutes,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Disabled')),
                          DropdownMenuItem(
                              value: 10, child: Text('After 10 mins')),
                          DropdownMenuItem(
                              value: 15, child: Text('After 15 mins')),
                          DropdownMenuItem(
                              value: 30, child: Text('After 30 mins')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            settingsVm.setEscalationMinutes(val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
