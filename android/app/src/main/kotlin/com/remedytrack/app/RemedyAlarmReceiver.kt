package com.remedytrack.app

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject

/**
 * Native Alarm BroadcastReceiver that catches exact alarm triggers from AlarmManager,
 * acquires a high-priority WakeLock to wake the screen/CPU, immediately starts looping
 * hardware STREAM_ALARM audio via RemedyAlarmPlayer, and launches MainActivity
 * full-screen over any app or lock screen.
 */
class RemedyAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "RemedyAlarmReceiver"
        const val ACTION_ALARM_TRIGGER = "com.remedytrack.app.ALARM_TRIGGER"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val payload = intent?.getStringExtra("payload") ?: ""
        val notifId = intent?.getIntExtra("notificationId", 0) ?: 0
        if (payload.isBlank()) {
            Log.w(TAG, "Ignoring native alarm broadcast with empty payload (notifId=$notifId)")
            return
        }

        Log.d(TAG, "RemedyAlarmReceiver triggered! Waking screen, starting alarm audio, and launching MainActivity...")

        // 1. Acquire WakeLock to turn on screen hardware and keep CPU alive while ringing
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            @Suppress("DEPRECATION")
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "RemedyTrack:AlarmWakeLock"
            )
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(3 * 60 * 1000L) // 3-minute safety timeout
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock: ${e.message}")
        }

        // 2. Immediately start hardware STREAM_ALARM audio + vibration in background before UI even mounts
        try {
            var soundId = "remedy_alarm_classic"
            var customPath = ""
            var vibrate = true
            if (payload.startsWith("{")) {
                val json = JSONObject(payload)
                val parsedSound = json.optString("soundId", "")
                if (parsedSound.isNotBlank()) {
                    soundId = parsedSound
                }
                customPath = json.optString("customPath", "")
                vibrate = json.optBoolean("vibrate", true)
            }
            RemedyAlarmPlayer.start(
                context = context,
                soundId = soundId,
                customPath = customPath,
                vibrate = vibrate
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start native alarm audio in receiver: ${e.message}")
            RemedyAlarmPlayer.start(context = context)
        }

        // 3. Launch MainActivity full-screen directly over the lock screen or active apps
        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_ALARM_TRIGGER
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
                putExtra("route", "/alarm-ring")
                putExtra("payload", payload)
                putExtra("notificationId", notifId)
            }

            val creatorOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ActivityOptions.makeBasic().apply {
                    setPendingIntentCreatorBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }.toBundle()
            } else {
                null
            }

            val senderOptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ActivityOptions.makeBasic().apply {
                    setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                }.toBundle()
            } else {
                null
            }

            var launchedDirect = false
            try {
                if (senderOptions != null) {
                    context.startActivity(launchIntent, senderOptions)
                } else {
                    context.startActivity(launchIntent)
                }
                launchedDirect = true
                Log.d(TAG, "MainActivity launched via context.startActivity()")
            } catch (eAct: Exception) {
                Log.w(TAG, "Direct startActivity notice: ${eAct.message}")
            }

            // Fallback PendingIntent dispatch only when direct startActivity did not succeed
            if (!launchedDirect) {
                try {
                    val pendingIntent = PendingIntent.getActivity(
                        context,
                        notifId,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        creatorOptions
                    )
                    if (senderOptions != null) {
                        pendingIntent.send(context, 0, null, null, null, null, senderOptions)
                    } else {
                        pendingIntent.send()
                    }
                    Log.d(TAG, "MainActivity dispatched via PendingIntent.send()")
                } catch (eSend: Exception) {
                    Log.w(TAG, "PendingIntent direct send notice: ${eSend.message}")
                }
            }

            Log.d(TAG, "MainActivity launch sequence completed from RemedyAlarmReceiver")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch MainActivity from receiver: ${e.message}")
        }
    }
}
