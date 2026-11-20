package com.remedytrack.app

import android.app.ActivityOptions
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.remedytrack.app/alarm_window"
        private const val PREFS_NATIVE_ALARMS = "remedy_native_alarms"
        private const val KEY_SCHEDULED_IDS = "scheduled_ids"
    }

    private var methodChannel: MethodChannel? = null
    private val pendingAlarmPayloads = ArrayDeque<String>()
    private var isAlarmTriggeredLaunch = false

    @Synchronized
    private fun enqueuePendingPayload(payload: String) {
        if (payload.isNotBlank() && !pendingAlarmPayloads.contains(payload)) {
            pendingAlarmPayloads.addLast(payload)
        }
    }

    @Synchronized
    private fun pollNextPayload(): String? {
        return if (pendingAlarmPayloads.isEmpty()) null else pendingAlarmPayloads.removeFirst()
    }

    @Synchronized
    private fun clearPendingPayloads() {
        pendingAlarmPayloads.clear()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent)
        if (isAlarmTriggeredLaunch) {
            wakeAndShowOverLockscreen()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAlarmIntent(intent)
        if (isAlarmTriggeredLaunch) {
            wakeAndShowOverLockscreen()
        }
    }

    override fun onResume() {
        super.onResume()
        if (isAlarmTriggeredLaunch) {
            wakeAndShowOverLockscreen()
        }
    }

    private fun handleAlarmIntent(intent: Intent?) {
        val payload = intent?.getStringExtra("payload")
        if (!payload.isNullOrEmpty()) {
            isAlarmTriggeredLaunch = true
            Log.d(TAG, "handleAlarmIntent received alarm payload: $payload")
            val channel = methodChannel
            if (channel != null) {
                enqueuePendingPayload(payload)
                var next = pollNextPayload()
                while (next != null) {
                    channel.invokeMethod("onNativeAlarmTriggered", next)
                    next = pollNextPayload()
                }
            } else {
                enqueuePendingPayload(payload)
            }
            // Clear payload extra from intent so it's not reused on config/lifecycle changes
            intent.removeExtra("payload")
            intent.removeExtra("route")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        // If one or more alarm payloads were queued before engine attached, dispatch them in order
        var queuedPayload = pollNextPayload()
        while (queuedPayload != null) {
            channel.invokeMethod("onNativeAlarmTriggered", queuedPayload)
            queuedPayload = pollNextPayload()
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val triggerTimeMillis = (call.argument<Number>("triggerTimeMillis"))?.toLong() ?: 0L
                    val payload = call.argument<String>("payload") ?: ""
                    scheduleNativeAlarmClock(id, triggerTimeMillis, payload)
                    result.success(true)
                }
                "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelNativeAlarmClock(id)
                    result.success(true)
                }
                "cancelAllNativeAlarms" -> {
                    val stopActivePlayer = call.argument<Boolean>("stopActivePlayer") ?: false
                    cancelAllNativeAlarms(stopActivePlayer = stopActivePlayer)
                    result.success(true)
                }
                "getPendingAlarmLaunch" -> {
                    val p = pollNextPayload()
                    result.success(p)
                    var extra = pollNextPayload()
                    while (extra != null) {
                        channel.invokeMethod("onNativeAlarmTriggered", extra)
                        extra = pollNextPayload()
                    }
                }
                "dismissAlarmScreen" -> {
                    dismissAlarmScreen()
                    result.success(true)
                }
                "wakeUpScreen" -> {
                    wakeAndShowOverLockscreen()
                    result.success(true)
                }
                "canUseFullScreenIntent" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(android.app.NotificationManager::class.java)
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        val directIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(directIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            try {
                                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(fallback)
                                result.success(true)
                            } catch (e3: Exception) {
                                result.error("SETTINGS_ERROR", e3.message, null)
                            }
                        }
                    }
                }
                "canDrawOverlays" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(fallback)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("SETTINGS_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "startNativeAlarmSound" -> {
                    val soundId = call.argument<String>("soundId")
                    val customPath = call.argument<String>("customPath")
                    val vibrate = call.argument<Boolean>("vibrate") ?: true
                    RemedyAlarmPlayer.start(
                        context = this,
                        soundId = soundId,
                        customPath = customPath,
                        vibrate = vibrate
                    )
                    result.success(true)
                }
                "stopNativeAlarmSound" -> {
                    RemedyAlarmPlayer.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleNativeAlarmClock(id: Int, triggerTimeMillis: Long, payload: String) {
        if (payload.isBlank() || triggerTimeMillis <= System.currentTimeMillis()) {
            Log.d(TAG, "Skipping native alarm schedule for id=$id (empty payload or past timestamp=$triggerTimeMillis)")
            return
        }
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        // Persist native request ID so cancelAllNativeAlarms can guarantee full cleanup
        // even across app restarts, sign-out, or medication deletion.
        val prefs = getSharedPreferences(PREFS_NATIVE_ALARMS, Context.MODE_PRIVATE)
        val trackedIds = HashSet(prefs.getStringSet(KEY_SCHEDULED_IDS, emptySet()) ?: emptySet())
        trackedIds.add(id.toString())
        prefs.edit().putStringSet(KEY_SCHEDULED_IDS, trackedIds).apply()

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = RemedyAlarmReceiver.ACTION_ALARM_TRIGGER
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra("route", "/alarm-ring")
            putExtra("payload", payload)
            putExtra("notificationId", id)
        }

        val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ActivityOptions.makeBasic().apply {
                setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                )
            }.toBundle()
        } else {
            null
        }

        // 1. Show PendingIntent for system quick settings / lock screen alarm clock glyph
        val showPendingIntent = PendingIntent.getActivity(
            this,
            id + 100000,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            options
        )

        // 2. Broadcast PendingIntent to RemedyAlarmReceiver (starts hardware STREAM_ALARM audio + WakeLock + Activity)
        val broadcastIntent = Intent(this, RemedyAlarmReceiver::class.java).apply {
            action = RemedyAlarmReceiver.ACTION_ALARM_TRIGGER
            putExtra("payload", payload)
            putExtra("notificationId", id)
        }
        val broadcastPendingIntent = PendingIntent.getBroadcast(
            this,
            id + 200000,
            broadcastIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmClockInfo = AlarmManager.AlarmClockInfo(triggerTimeMillis, showPendingIntent)
        try {
            // Use broadcastPendingIntent as the single AlarmClock trigger so there is never
            // a delayed Doze-throttled duplicate launch a few minutes after the alarm.
            alarmManager.setAlarmClock(alarmClockInfo, broadcastPendingIntent)
            Log.d(TAG, "Native AlarmClock broadcast scheduled successfully for id: $id at $triggerTimeMillis")
        } catch (e: Exception) {
            Log.w(TAG, "Failed setAlarmClock, falling back to setExactAndAllowWhileIdle: ${e.message}")
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, broadcastPendingIntent)
            } catch (e2: Exception) {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTimeMillis, broadcastPendingIntent)
            }
        }
    }

    private fun cancelNativeAlarmClock(id: Int, removeFromPrefs: Boolean = true) {
        // NOTE: Do NOT call RemedyAlarmPlayer.stop(this) here!
        // cancelNativeAlarmClock is called for future/stale alarm IDs during rescheduleAll()
        // and during AlarmRingingScreen startup; stopping RemedyAlarmPlayer here would
        // prematurely cut off an actively ringing alarm. Audio is stopped explicitly via
        // stopNativeAlarmSound, dismissAlarmScreen, or cancelAllNativeAlarms.
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        // Cancel any legacy direct activity PendingIntent
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = RemedyAlarmReceiver.ACTION_ALARM_TRIGGER
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)

        // Cancel show PendingIntent
        val showPendingIntent = PendingIntent.getActivity(
            this,
            id + 100000,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(showPendingIntent)

        // Cancel broadcast PendingIntent
        val broadcastIntent = Intent(this, RemedyAlarmReceiver::class.java).apply {
            action = RemedyAlarmReceiver.ACTION_ALARM_TRIGGER
        }
        val broadcastPendingIntent = PendingIntent.getBroadcast(
            this,
            id + 200000,
            broadcastIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(broadcastPendingIntent)

        if (removeFromPrefs) {
            val prefs = getSharedPreferences(PREFS_NATIVE_ALARMS, Context.MODE_PRIVATE)
            val trackedIds = HashSet(prefs.getStringSet(KEY_SCHEDULED_IDS, emptySet()) ?: emptySet())
            if (trackedIds.remove(id.toString())) {
                prefs.edit().putStringSet(KEY_SCHEDULED_IDS, trackedIds).apply()
            }
        }

        Log.d(TAG, "Native AlarmClock cancelled for id: $id")
    }

    private fun cancelAllNativeAlarms(stopActivePlayer: Boolean = false) {
        if (stopActivePlayer) {
            RemedyAlarmPlayer.stop(this)
            releaseAlarmWakeLock()
            clearPendingPayloads()
            isAlarmTriggeredLaunch = false
        }

        val prefs = getSharedPreferences(PREFS_NATIVE_ALARMS, Context.MODE_PRIVATE)
        val trackedIds = HashSet(prefs.getStringSet(KEY_SCHEDULED_IDS, emptySet()) ?: emptySet())
        for (idStr in trackedIds) {
            val id = idStr.toIntOrNull() ?: continue
            cancelNativeAlarmClock(id, removeFromPrefs = false)
        }
        prefs.edit().remove(KEY_SCHEDULED_IDS).apply()
        Log.d(TAG, "Cancelled all ${trackedIds.size} tracked native AlarmClock entries")
    }

    private var alarmWakeLock: PowerManager.WakeLock? = null

    private fun releaseAlarmWakeLock() {
        try {
            alarmWakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            alarmWakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing WakeLock: ${e.message}")
        }
    }

    override fun onDestroy() {
        if (!isChangingConfigurations) {
            RemedyAlarmPlayer.stop(this)
            releaseAlarmWakeLock()
        }
        super.onDestroy()
    }

    private fun dismissAlarmScreen() {
        try {
            RemedyAlarmPlayer.stop(this)
            releaseAlarmWakeLock()
            clearPendingPayloads()
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }
            // Dismiss full screen alarm and move activity to back only if this activity was brought up by an alarm trigger
            if (isAlarmTriggeredLaunch) {
                isAlarmTriggeredLaunch = false
                moveTaskToBack(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in dismissAlarmScreen: ${e.message}")
        }
    }

    private fun wakeAndShowOverLockscreen() {
        try {
            if (alarmWakeLock?.isHeld != true) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                alarmWakeLock = powerManager?.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                    "RemedyTrack:MainActivityWakeLock"
                )
                alarmWakeLock?.setReferenceCounted(false)
                alarmWakeLock?.acquire(3 * 60 * 1000L)
            }
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock error: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguardManager?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
