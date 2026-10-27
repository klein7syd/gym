package com.reps.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

/**
 * 音乐播放：前台服务 + MediaSession，息屏/锁屏继续播，锁屏和通知栏可控。
 */
class MusicService : Service() {

    companion object {
        private const val CH = "music"
        private const val NID = 12
        const val A_INIT = "com.reps.app.M_INIT"
        const val A_TOGGLE = "com.reps.app.M_TOGGLE"
        const val A_NEXT = "com.reps.app.M_NEXT"
        const val A_PREV = "com.reps.app.M_PREV"
        const val A_STOP = "com.reps.app.M_STOP"

        var instance: MusicService? = null
        val list = mutableListOf<Uri>()
        var index = 0
        var playing = false
        var trackName = ""
        var onChange: (() -> Unit)? = null

        fun play(c: Context, uris: List<Uri>, startAt: Int) {
            list.clear()
            list.addAll(uris)
            index = startAt.coerceIn(0, (list.size - 1).coerceAtLeast(0))
            c.startForegroundService(Intent(c, MusicService::class.java).setAction(A_INIT))
        }

        fun toggle(c: Context) {
            if (instance == null) return
            c.startService(Intent(c, MusicService::class.java).setAction(A_TOGGLE))
        }

        fun next(c: Context) { c.startService(Intent(c, MusicService::class.java).setAction(A_NEXT)) }
        fun prev(c: Context) { c.startService(Intent(c, MusicService::class.java).setAction(A_PREV)) }

        fun position(): Int = instance?.mp?.currentPosition ?: 0
        fun seek(ms: Int) {
            instance?.let { s -> try { s.mp?.seekTo(ms) } catch (e: Exception) { } }
        }
        fun duration(): Int = instance?.mp?.duration ?: 0
    }

    private var mp: MediaPlayer? = null
    private lateinit var session: MediaSessionCompat

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        session = MediaSessionCompat(this, "REPS").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { resume() }
                override fun onPause() { pause() }
                override fun onSkipToNext() { playIndex(index + 1) }
                override fun onSkipToPrevious() { playIndex(index - 1) }
                override fun onStop() { stopSelf() }
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            A_INIT -> {
                startForeground(NID, buildNotif())
                if (list.isNotEmpty()) playIndex(index) else stopSelf()
            }
            A_TOGGLE -> if (playing) pause() else resume()
            A_NEXT -> playIndex(index + 1)
            A_PREV -> playIndex(index - 1)
            A_STOP -> { releaseAll(); stopSelf() }
        }
        return START_NOT_STICKY
    }

    private fun playIndex(i: Int) {
        if (list.isEmpty()) return
        index = ((i % list.size) + list.size) % list.size
        try {
            mp?.release()
            mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(applicationContext, list[index])
                prepare()
                start()
                setOnCompletionListener { playIndex(index + 1) }
            }
            playing = true
            trackName = list[index].lastPathSegment ?: "未知曲目"
            updateSession()
            startForeground(NID, buildNotif())
            onChange?.invoke()
        } catch (e: Exception) {
            playing = false
            onChange?.invoke()
        }
    }

    private fun pause() {
        try { mp?.pause() } catch (e: Exception) { }
        playing = false
        updateSession()
        startForeground(NID, buildNotif())
        onChange?.invoke()
    }

    private fun resume() {
        try {
            mp?.start()
            playing = true
            updateSession()
            startForeground(NID, buildNotif())
            onChange?.invoke()
        } catch (e: Exception) { }
    }

    private fun releaseAll() {
        try { mp?.stop(); mp?.release() } catch (e: Exception) { }
        mp = null
        playing = false
        onChange?.invoke()
    }

    private fun updateSession() {
        val state = if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED
        val pos = try { mp?.currentPosition?.toLong() ?: 0L } catch (e: Exception) { 0L }
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                )
                .setState(state, pos, 1f)
                .build()
        )
        session.setMetadata(
            android.support.v4.media.MediaMetadataCompat.Builder()
                .putString(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_TITLE, trackName)
                .putString(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_ARTIST, "REPS")
                .putLong(android.support.v4.media.MediaMetadataCompat.METADATA_KEY_DURATION, duration().toLong())
                .build()
        )
    }

    private fun action(code: String): PendingIntent = PendingIntent.getService(
        this, code.hashCode(), Intent(this, MusicService::class.java).setAction(code),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CH) == null) {
                val ch = NotificationChannel(CH, "音乐播放", NotificationManager.IMPORTANCE_LOW)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotif(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = NotificationCompat.Builder(this, CH)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(trackName.ifBlank { "REPS" })
            .setContentText(if (playing) "正在播放" else "已暂停")
            .setContentIntent(open)
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "上一首", action(A_PREV))
            .addAction(0, if (playing) "暂停" else "播放", action(A_TOGGLE))
            .addAction(0, "下一首", action(A_NEXT))
        b.setStyle(MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
        return b.build()
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseAll()
        try { session.release() } catch (e: Exception) { }
        instance = null
    }
}
