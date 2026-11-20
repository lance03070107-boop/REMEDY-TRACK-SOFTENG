import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../services/alarm_scheduler.dart';
import '../../services/alarm_sound_service.dart';
import '../../viewmodels/medication_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';

/// Screen 2: Default Alarm Tone Selection.
/// Displays all built-in and custom alarm tones, allows previewing each tone,
/// importing custom audio files, and persisting + rescheduling active medication alarms.
class DefaultAlarmToneView extends StatefulWidget {
  const DefaultAlarmToneView({super.key});

  @override
  State<DefaultAlarmToneView> createState() => _DefaultAlarmToneViewState();
}

class _DefaultAlarmToneViewState extends State<DefaultAlarmToneView> {
  List<AlarmSoundItem> _availableSounds = AlarmSoundService.builtInSounds;
  String? _previewingSoundId;

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

  Future<void> _togglePreview(AlarmSoundItem sound) async {
    final soundService = AlarmSoundService();
    if (_previewingSoundId == sound.id) {
      await soundService.stopPreview();
      if (mounted) setState(() => _previewingSoundId = null);
    } else {
      if (mounted) setState(() => _previewingSoundId = sound.id);
      await soundService.playPreview(
        soundId: sound.id,
        customPath: sound.localFilePath,
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _previewingSoundId == sound.id) {
          setState(() => _previewingSoundId = null);
        }
      });
    }
  }

  Future<void> _selectSound(AlarmSoundItem sound) async {
    final settingsVm = context.read<SettingsViewModel>();
    await settingsVm.setAlarmSound(sound.id);

    if (!mounted) return;
    final medVm = context.read<MedicationViewModel?>();
    if (medVm != null) {
      unawaited(
        medVm.applyGlobalDefaultAlarmTone(
          soundId: sound.id,
          customSoundPath: sound.localFilePath,
        ),
      );
    } else {
      unawaited(AlarmScheduler.refillRollingWindowFromCache());
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Default alarm tone set to "${sound.displayName}".'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickAndImportAudio() async {
    final soundService = AlarmSoundService();
    final item = await soundService.pickAndImportCustomSound();
    if (item != null) {
      await _loadSounds();
      if (mounted) {
        await _selectSound(item);
      }
    }
  }

  Future<void> _deleteCustomSound(AlarmSoundItem sound) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${sound.displayName}"?'),
        content: const Text(
          'This custom audio file will be permanently removed from your device.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AlarmSoundService().deleteCustomSound(sound.id);
      await _loadSounds();
      if (mounted) {
        final settingsVm = context.read<SettingsViewModel>();
        if (settingsVm.alarmSound == sound.id) {
          final fallback = _availableSounds.firstWhere(
            (s) => s.id == AppConstants.defaultAlarmSound,
            orElse: () => AlarmSoundService.builtInSounds.first,
          );
          await _selectSound(fallback);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsVm = context.watch<SettingsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Default Alarm Tone'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.surfaceContainerLow
                      : const Color(0xFFDDF2FC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.55),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      color: theme.colorScheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Select the default tone played when your medication alarms ring. Tap the play button to preview any tone.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ..._availableSounds.map((sound) {
                final isSelected = settingsVm.alarmSound == sound.id;
                final isPlaying = _previewingSoundId == sound.id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.45)
                        : theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                      width: isSelected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      title: Text(
                        sound.displayName,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        sound.isCustom
                            ? 'Custom Imported Audio'
                            : 'Built-in Alarm Tone',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => _selectSound(sound),
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                                isPlaying ? 'Stop Preview' : 'Preview Tone',
                            icon: Icon(
                              isPlaying
                                  ? Icons.stop_circle_rounded
                                  : Icons.play_circle_outline_rounded,
                              color: isPlaying
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                            onPressed: () => _togglePreview(sound),
                          ),
                          if (sound.isCustom)
                            IconButton(
                              tooltip: 'Delete custom sound',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                              ),
                              onPressed: () => _deleteCustomSound(sound),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _pickAndImportAudio,
                icon: const Icon(Icons.file_upload_outlined, size: 20),
                label: const Text(
                  'Import Custom Audio File (.mp3, .wav, .m4a)',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
