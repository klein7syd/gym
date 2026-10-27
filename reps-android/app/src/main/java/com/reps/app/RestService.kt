package com.reps.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

/**
 * 组间计时：前台服务跑倒计时，息屏/切后台都不断；到点在通知栏 + 响铃 + 震动。
 */
class RestService : Service() {

    companion object {
        private const val CH = "rest_timer"
        private const val NID = 11
        const val ACTION_START = "com.reps.app.REST_START"
        const val ACTION_STOP = "com.reps.app.REST_STOP"
        const val EXTRA_SEC = "sec"

        @Volatile var remainingMs = 0L
        @Volatile var totalMs = 0L
        @Volatile var running = false

        var onTick: ((Long, Long) -> Unit)? = null
        var onDone: (() -> Unit)? = null

        fun start(c: Context, sec: Int) {
            val i = Intent(c, RestService::class.java).setAction(ACTION_START).putExtra(EXTRA_SEC, sec)
            c.startForegroundService(i)
        }

        fun stop(c: Context) {
            c.startService(Intent(c, RestService::class.java).setAction(ACTION_STOP))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var endAt = 0L
    private var total = 0
    private var wl: PowerManager.WakeLock? = null
    private var finished = false

    private val ticker = object : Runnable {
        override fun run() {
            val left = endAt - SystemClock.elapsedRealtime()
            remainingMs = if (left > 0) left else 0
            if (left <= 0) {
                done()
                return
            }
            pushNotification(left, total * 1000L, false)
            onTick?.invoke(remainingMs, totalMs)
            handler.postDelayed(this, 200)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val sec = intent.getIntExtra(EXTRA_SEC, 120).coerceIn(10, 3600)
                startTimer(sec)
            }
            ACTION_STOP -> shutdown()
        }
        return START_NOT_STICKY
    }

    private fun startTimer(sec: Int) {
        finished = false
        total = sec
        totalMs = sec * 1000L
        remainingMs = totalMs
        running = true
        endAt = SystemClock.elapsedRealtime() + totalMs

        startForeground(NID, buildNotification(totalMs, totalMs, false))

        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "reps:rest")
            wl?.acquire((sec + 120) * 1000L)
        } catch (e: Exception) {
        }

        handler.removeCallbacks(ticker)
        handler.post(ticker)
        onTick?.invoke(remainingMs, totalMs)
    }

    private fun done() {
        if (finished) return
        finished = true
        running = false
        remainingMs = 0
        handler.removeCallbacks(ticker)
        onTick?.invoke(0, totalMs)
        onDone?.invoke()

        alarm()

        pushNotification(0, totalMs, true)
        handler.postDelayed({ shutdown() }, 4000)
    }

    private fun shutdown() {
        running = false
        handler.removeCallbacksAndMessages(null)
        try { wl?.let { if (it.isHeld) it.release() } } catch (e: Exception) { }
        wl = null
        stopForeground(true)
        stopSelf()
    }

    private fun alarm() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val rt = RingtoneManager.getRingtone(applicationContext, uri)
            rt.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            rt.play()
        } catch (e: Exception) {
        }
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (android.os.Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 120, 90, 220), -1))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(longArrayOf(0, 120, 90, 220), -1)
            }
        } catch (e: Exception) {
        }
    }

    private fun createChannel() {
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CH) == null) {
                val ch = NotificationChannel(CH, "组间计时", NotificationManager.IMPORTANCE_HIGH)
                ch.setShowBadge(false)
                ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(leftMs: Long, totalMs: Long, done: Boolean): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopPi = PendingIntent.getService(
            this, 1, Intent(this, RestService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val s = (leftMs / 1000).coerceAtLeast(0)
        val text = if (done) "GO · 上组" else String.format("%d:%02d 后开始下一组", s / 60, s % 60)
        return NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("组间休息")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(!done)
            .setOnlyAlertOnce(!done)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "跳过", stopPi)
            .build()
    }

    private fun pushNotification(leftMs: Long, totalMs: Long, done: Boolean) {
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NID, buildNotification(leftMs, totalMs, done))
        } catch (e: Exception) {
        }
    }
}
