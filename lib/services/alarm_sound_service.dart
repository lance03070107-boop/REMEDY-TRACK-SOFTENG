import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';

/// Represents an alarm sound option (either built-in asset or user-imported local file).
class AlarmSoundItem {
  final String id;
  final String displayName;
  final String assetPath;
  final String? localFilePath;
  final bool isCustom;

  const AlarmSoundItem({
    required this.id,
    required this.displayName,
    this.assetPath = '',
    this.localFilePath,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'localFilePath': localFilePath,
        'isCustom': isCustom,
      };

  factory AlarmSoundItem.fromJson(Map<String, dynamic> json) => AlarmSoundItem(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        localFilePath: json['localFilePath'] as String?,
        isCustom: json['isCustom'] as bool? ?? true,
      );
}

/// Production multi-sound audio engine forcing playback over native hardware
/// alarm streams (STREAM_ALARM on Android, AVAudioSessionCategory.playback on iOS).
/// Supports built-in medical alarm tones, user-imported audio files, and synchronized haptics.
class AlarmSoundService {
  static final AlarmSoundService _instance = AlarmSoundService._internal();
  factory AlarmSoundService() => _instance;

  AlarmSoundService._internal();

  AudioPlayer? _alarmPlayerInstance;
  AudioPlayer? _previewPlayerInstance;

  AudioPlayer get _alarmPlayer => _alarmPlayerInstance ??= AudioPlayer();
  AudioPlayer get _previewPlayer => _previewPlayerInstance ??= AudioPlayer();

  Timer? _vibrationTimer;
  bool _isRinging = false;
  bool _isMuted = false;

  bool get isRinging => _isRinging;
  bool get isMuted => _isMuted;

  /// Built-in alarm sounds bundled within `assets/sounds/`.
  static const List<AlarmSoundItem> builtInSounds = [
    AlarmSoundItem(
      id: 'remedy_alarm_classic',
      displayName: 'Classic Medical Alarm',
      assetPath: 'sounds/remedy_alarm_classic.wav',
    ),
    AlarmSoundItem(
      id: 'remedy_alarm_gentle',
      displayName: 'Gentle Chime',
      assetPath: 'sounds/remedy_alarm_gentle.wav',
    ),
    AlarmSoundItem(
      id: 'remedy_alarm_beep',
      displayName: 'Urgent Clinical Beep',
      assetPath: 'sounds/remedy_alarm_beep.wav',
    ),
    AlarmSoundItem(
      id: 'remedy_alarm_bell',
      displayName: 'Soft Melody Bell',
      assetPath: 'sounds/remedy_alarm_bell.wav',
    ),
    AlarmSoundItem(
      id: 'remedy_alarm_digital',
      displayName: 'Digital Pulse',
      assetPath: 'sounds/remedy_alarm_digital.wav',
    ),
    AlarmSoundItem(
      id: 'remedy_alarm_harp',
      displayName: 'Morning Harp',
      assetPath: 'sounds/remedy_alarm_harp.wav',
    ),
  ];

  static const MethodChannel _nativeAlarmChannel =
      MethodChannel('com.remedytrack.app/alarm_window');

  /// Initializes hardware alarm audio routing for both players.
  Future<void> initialize() async {
    if (kIsWeb) {
      // On Web (especially iOS Safari/WebKit), AudioContext must only be created
      // upon user interaction; skip eager native AudioContext configuration.
      return;
    }
    final audioContext = AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransientExclusive,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {
          AVAudioSessionOptions.duckOthers,
        },
      ),
    );

    try {
      await _alarmPlayer.setAudioContext(audioContext);
      await _previewPlayer.setAudioContext(audioContext);
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _previewPlayer.setReleaseMode(ReleaseMode.stop);
    } catch (e, s) {
      AppLogger.w('AudioContext configuration notice: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
    }
  }

  /// Retrieves list of all built-in and user-imported custom sounds.
  Future<List<AlarmSoundItem>> getAllSounds() async {
    final list = <AlarmSoundItem>[...builtInSounds];
    final custom = await getCustomSounds();
    list.addAll(custom);
    return list;
  }

  /// Retrieves user-imported custom sounds from persistent storage.
  Future<List<AlarmSoundItem>> getCustomSounds() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(AppConstants.keyCustomSounds);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(jsonStr) as List<dynamic>;
      final items = <AlarmSoundItem>[];
      for (final raw in decoded) {
        final item = AlarmSoundItem.fromJson(raw as Map<String, dynamic>);
        if (kIsWeb ||
            (item.localFilePath != null &&
                File(item.localFilePath!).existsSync())) {
          items.add(item);
        }
      }
      return items;
    } catch (e, s) {
      AppLogger.w('Failed to parse custom sounds: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Opens the native device file picker and safely copies chosen audio file
  /// into permanent application documents storage.
  Future<AlarmSoundItem?> pickAndImportCustomSound() async {
    if (kIsWeb) return null;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'aac'],
      );

      if (file == null || file.path == null) return null;
      final pickedPath = file.path!;

      final sourceFile = File(pickedPath);
      if (!sourceFile.existsSync()) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory(p.join(appDir.path, 'custom_alarm_sounds'));
      if (!soundsDir.existsSync()) {
        await soundsDir.create(recursive: true);
      }

      final ext = p.extension(pickedPath);
      final rawName = p.basenameWithoutExtension(file.name);
      final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      final targetFilePath = p.join(soundsDir.path, '$id$ext');

      await sourceFile.copy(targetFilePath);

      final newItem = AlarmSoundItem(
        id: id,
        displayName: rawName,
        localFilePath: targetFilePath,
        isCustom: true,
      );

      // Persist in SharedPreferences
      final currentCustom = await getCustomSounds();
      currentCustom.add(newItem);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.keyCustomSounds,
        jsonEncode(currentCustom.map((e) => e.toJson()).toList()),
      );

      return newItem;
    } catch (e, s) {
      AppLogger.w('Error importing custom sound: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
      return null;
    }
  }

  /// Deletes a user custom sound and removes its local file.
  Future<void> deleteCustomSound(String id) async {
    final currentCustom = await getCustomSounds();
    final toRemove = currentCustom.firstWhere(
      (s) => s.id == id,
      orElse: () => const AlarmSoundItem(id: '', displayName: ''),
    );

    if (!kIsWeb && toRemove.localFilePath != null) {
      final file = File(toRemove.localFilePath!);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (e, s) {
          AppLogger.w('Error deleting sound file: $e',
              tag: 'AlarmSoundService', error: e, stackTrace: s);
        }
      }
    }

    currentCustom.removeWhere((s) => s.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.keyCustomSounds,
      jsonEncode(currentCustom.map((e) => e.toJson()).toList()),
    );
  }

  /// Starts persistent looping alarm sound with synchronized haptics.
  Future<void> startAlarm({
    String? soundId,
    String? customPath,
    bool vibration = true,
  }) async {
    _isRinging = true;
    _isMuted = false;

    // Stop any active preview
    await stopPreview();

    // On Android, prefer the hardware-level native RemedyAlarmPlayer (STREAM_ALARM + WakeLock + Vibrator)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeAlarmChannel.invokeMethod('startNativeAlarmSound', {
          'soundId': soundId ?? AppConstants.defaultAlarmSound,
          'customPath': customPath ?? '',
          'vibrate': vibration,
        });
        return;
      } catch (e) {
        AppLogger.w(
            'Native alarm player channel unavailable, using fallback player: $e',
            tag: 'AlarmSoundService');
      }
    }

    try {
      await _alarmPlayer.setVolume(1.0);
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);

      Source source;
      if (!kIsWeb &&
          customPath != null &&
          customPath.isNotEmpty &&
          File(customPath).existsSync()) {
        source = DeviceFileSource(customPath);
      } else {
        final matchCustom = (await getCustomSounds()).firstWhere(
          (s) => s.id == soundId,
          orElse: () => const AlarmSoundItem(id: '', displayName: ''),
        );

        if (!kIsWeb &&
            matchCustom.localFilePath != null &&
            File(matchCustom.localFilePath!).existsSync()) {
          source = DeviceFileSource(matchCustom.localFilePath!);
        } else {
          final matchedBuiltIn = builtInSounds.firstWhere(
            (s) => s.id == soundId,
            orElse: () => builtInSounds.first,
          );
          source = AssetSource(matchedBuiltIn.assetPath);
        }
      }

      await _alarmPlayer.play(source);
    } catch (e, s) {
      AppLogger.e('Play alarm failure: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
    }

    // Synchronized periodic vibration pulse
    if (vibration) {
      _startVibrationPulse();
    }
  }

  /// Silences current alarm audio and vibration without navigating away.
  void muteCurrentAlarm() {
    _isMuted = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        _nativeAlarmChannel
            .invokeMethod('stopNativeAlarmSound')
            .catchError((Object _) => null),
      );
    }
    _alarmPlayer.stop();
    _stopVibration();
  }

  /// Resumes current alarm audio and vibration.
  Future<void> unmuteCurrentAlarm({
    String? soundId,
    String? customPath,
    bool vibration = true,
  }) async {
    _isMuted = false;
    await startAlarm(
        soundId: soundId, customPath: customPath, vibration: vibration);
  }

  /// Toggles mute state of the current alarm.
  Future<void> toggleMute({
    String? soundId,
    String? customPath,
    bool vibration = true,
  }) async {
    if (_isMuted) {
      await unmuteCurrentAlarm(
          soundId: soundId, customPath: customPath, vibration: vibration);
    } else {
      muteCurrentAlarm();
    }
  }

  /// Fully terminates alarm ringing and haptics, stopping and disposing any active AudioPlayer.
  Future<void> stopAlarm() async {
    _isRinging = false;
    _isMuted = false;
    _stopVibration();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeAlarmChannel.invokeMethod('stopNativeAlarmSound');
      } catch (_) {}
    }
    final player = _alarmPlayerInstance;
    _alarmPlayerInstance = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (e, s) {
        AppLogger.w('Stop alarm notice: $e',
            tag: 'AlarmSoundService', error: e, stackTrace: s);
      }
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  /// Plays a one-shot preview of an alarm sound.
  Future<void> playPreview({
    String? soundId,
    String? customPath,
  }) async {
    await stopPreview();

    try {
      await _previewPlayer.setVolume(1.0);
      await _previewPlayer.setReleaseMode(ReleaseMode.stop);

      Source source;
      if (!kIsWeb &&
          customPath != null &&
          customPath.isNotEmpty &&
          File(customPath).existsSync()) {
        source = DeviceFileSource(customPath);
      } else {
        final matchCustom = (await getCustomSounds()).firstWhere(
          (s) => s.id == soundId,
          orElse: () => const AlarmSoundItem(id: '', displayName: ''),
        );

        if (!kIsWeb &&
            matchCustom.localFilePath != null &&
            File(matchCustom.localFilePath!).existsSync()) {
          source = DeviceFileSource(matchCustom.localFilePath!);
        } else {
          final matchedBuiltIn = builtInSounds.firstWhere(
            (s) => s.id == soundId,
            orElse: () => builtInSounds.first,
          );
          source = AssetSource(matchedBuiltIn.assetPath);
        }
      }

      await _previewPlayer.play(source);
    } catch (e, s) {
      AppLogger.w('Play preview failure: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
    }
  }

  /// Stops any currently playing audio preview.
  Future<void> stopPreview() async {
    try {
      await _previewPlayerInstance?.stop();
    } catch (e, s) {
      AppLogger.w('Stop preview notice: $e',
          tag: 'AlarmSoundService', error: e, stackTrace: s);
    }
  }

  void _startVibrationPulse() {
    _stopVibration();
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_isRinging || _isMuted) {
        _stopVibration();
        return;
      }
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  void dispose() {
    _stopVibration();
    _alarmPlayerInstance?.dispose();
    _previewPlayerInstance?.dispose();
  }
}
