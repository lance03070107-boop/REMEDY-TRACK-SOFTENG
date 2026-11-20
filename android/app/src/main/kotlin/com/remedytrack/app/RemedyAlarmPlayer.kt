package com.remedytrack.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import java.io.File

/**
 * Hardware-level Android Alarm Audio & Vibration Engine.
 * Forces looping playback over STREAM_ALARM (AudioAttributes.USAGE_ALARM) so medication
 * alarms ring out loud even when the device is in Silent or Vibrate ringer mode,
 * or before the Flutter UI finishes mounting from a cold/background start.
 */
object RemedyAlarmPlayer {
    private const val TAG = "RemedyAlarmPlayer"

    private var mediaPlayer: MediaPlayer? = null
    private var fallbackRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isRinging: Boolean = false
    private var activeSoundId: String? = null
    private var activeCustomPath: String? = null

    @Synchronized
    fun start(
        context: Context,
        soundId: String? = null,
        customPath: String? = null,
        vibrate: Boolean = true
    ) {
        val normalizedSoundId = soundId?.trim()?.takeIf { it.isNotEmpty() } ?: "remedy_alarm_classic"
        val normalizedCustomPath = customPath?.trim()?.takeIf { it.isNotEmpty() }

        // If the exact same alarm sound is already actively playing on MediaPlayer or fallbackRingtone,
        // do not tear down and recreate the audio stream (prevents stutter/cutoff when
        // RemedyAlarmReceiver and AlarmRingingScreen both request playback).
        val alreadyPlaying = (mediaPlayer?.isPlaying == true) || (fallbackRingtone?.isPlaying == true)
        if (isRinging && alreadyPlaying &&
            activeSoundId == normalizedSoundId &&
            activeCustomPath == normalizedCustomPath
        ) {
            Log.d(TAG, "RemedyAlarmPlayer already ringing with soundId=$normalizedSoundId; continuing playback.")
            return
        }

        val appContext = context.applicationContext
        stop(appContext)
        isRinging = true
        activeSoundId = normalizedSoundId
        activeCustomPath = normalizedCustomPath

        val alarmAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // 1. Ensure STREAM_ALARM hardware volume is audible without hijacking active calls or headsets
        try {
            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                val isInCall = audioManager.mode == AudioManager.MODE_IN_CALL ||
                    audioManager.mode == AudioManager.MODE_IN_COMMUNICATION ||
                    audioManager.mode == AudioManager.MODE_RINGTONE
                val hasExternalAudioDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
                        device.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            device.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            device.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                            device.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            device.type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET ||
                            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                                device.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    (audioManager.isBluetoothA2dpOn || audioManager.isBluetoothScoOn || audioManager.isWiredHeadsetOn)
                }

                if (!isInCall && !hasExternalAudioDevice) {
                    audioManager.mode = AudioManager.MODE_NORMAL
                    audioManager.isSpeakerphoneOn = true
                }

                val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                val minTargetVol = (maxVol * 0.75).toInt().coerceAtLeast(1)
                if (currentVol < minTargetVol) {
                    try {
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, minTargetVol, 0)
                        Log.d(TAG, "Boosted STREAM_ALARM volume from $currentVol to $minTargetVol (max=$maxVol)")
                    } catch (se: SecurityException) {
                        Log.w(TAG, "DND restricted volume adjustment: ${se.message}")
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                        .setAudioAttributes(alarmAttributes)
                        .setAcceptsDelayedFocusGain(false)
                        .setOnAudioFocusChangeListener { }
                        .build()
                    audioFocusRequest = req
                    audioManager.requestAudioFocus(req)
                } else {
                    @Suppress("DEPRECATION")
                    audioManager.requestAudioFocus(
                        null,
                        AudioManager.STREAM_ALARM,
                        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
                    )
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "AudioManager setup notice: ${e.message}")
        }

        // 2. Start looping MediaPlayer on USAGE_ALARM
        var startedMediaPlayer = false
        try {
            val player = MediaPlayer()
            player.setAudioAttributes(alarmAttributes)
            player.setWakeMode(appContext, PowerManager.PARTIAL_WAKE_LOCK)

            var dataSourceSet = false
            if (!customPath.isNullOrBlank()) {
                val customFile = File(customPath)
                if (customFile.exists() && customFile.canRead()) {
                    player.setDataSource(customFile.absolutePath)
                    dataSourceSet = true
                }
            }

            if (!dataSourceSet) {
                val cleanTone = when (soundId?.trim()) {
                    "remedy_alarm_classic",
                    "remedy_alarm_gentle",
                    "remedy_alarm_beep",
                    "remedy_alarm_bell",
                    "remedy_alarm_digital",
                    "remedy_alarm_harp" -> soundId.trim()
                    else -> "remedy_alarm_classic"
                }
                val resId = appContext.resources.getIdentifier(
                    cleanTone,
                    "raw",
                    appContext.packageName
                ).let { id ->
                    if (id != 0) id else appContext.resources.getIdentifier(
                        "remedy_alarm_classic",
                        "raw",
                        appContext.packageName
                    )
                }

                if (resId != 0) {
                    appContext.resources.openRawResourceFd(resId)?.use { afd ->
                        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                        dataSourceSet = true
                    }
                }
            }

            if (!dataSourceSet) {
                val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                if (defaultUri != null) {
                    player.setDataSource(appContext, defaultUri)
                    dataSourceSet = true
                }
            }

            if (dataSourceSet) {
                player.isLooping = true
                player.setVolume(1.0f, 1.0f)
                player.prepare()
                player.start()
                mediaPlayer = player
                startedMediaPlayer = true
                Log.d(TAG, "Started looping native USAGE_ALARM MediaPlayer (soundId=$soundId)")
            } else {
                player.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MediaPlayer alarm start error, falling back to system Ringtone: ${e.message}")
        }

        // 3. Fallback to system Ringtone on USAGE_ALARM if MediaPlayer failed
        if (!startedMediaPlayer) {
            try {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                val ringtone = RingtoneManager.getRingtone(appContext, uri)
                if (ringtone != null) {
                    ringtone.audioAttributes = alarmAttributes
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        ringtone.isLooping = true
                    }
                    ringtone.play()
                    fallbackRingtone = ringtone
                    Log.d(TAG, "Started system fallback Ringtone on USAGE_ALARM")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Fallback Ringtone error: ${e.message}")
            }
        }

        // 4. Start continuous hardware vibration waveform if enabled
        if (vibrate) {
            startContinuousVibration(appContext, alarmAttributes)
        }
    }

    private fun startContinuousVibration(context: Context, alarmAttributes: AudioAttributes) {
        try {
            val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            vibrator = vib
            if (vib != null && vib.hasVibrator()) {
                val pattern = longArrayOf(0, 800, 400, 800, 400, 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, 0)
                    @Suppress("DEPRECATION")
                    vib.vibrate(effect, alarmAttributes)
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(pattern, 0)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Vibration start notice: ${e.message}")
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        isRinging = false
        activeSoundId = null
        activeCustomPath = null
        mainHandler.removeCallbacksAndMessages(null)

        try {
            mediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.reset()
                player.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer stop notice: ${e.message}")
        } finally {
            mediaPlayer = null
        }

        try {
            fallbackRingtone?.let { rt ->
                if (rt.isPlaying) {
                    rt.stop()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Fallback ringtone stop notice: ${e.message}")
        } finally {
            fallbackRingtone = null
        }

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Vibrator cancel notice: ${e.message}")
        } finally {
            vibrator = null
        }

        if (context != null) {
            try {
                val audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    audioFocusRequest?.let { req ->
                        audioManager.abandonAudioFocusRequest(req)
                    }
                }
                audioFocusRequest = null
            } catch (e: Exception) {
                Log.w(TAG, "Abandon audio focus notice: ${e.message}")
            }
        }
    }
}
