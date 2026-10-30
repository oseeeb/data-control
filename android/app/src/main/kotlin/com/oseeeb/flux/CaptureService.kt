package com.oseeeb.flux

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import java.util.Locale

/**
 * Service au premier plan qui mesure pendant une capture, que l'app soit
 * ouverte ou non. Il lit les compteurs toutes les 2 s ([CaptureState]),
 * affiche la notification « En direct » avec un bouton STOP, et applique
 * l'arrêt automatique.
 *
 * Si le système ferme Flux pour économiser la batterie, il relance ce service
 * ([START_STICKY]) : la capture reprend où elle en était, et le temps passé
 * sans lecture est rattrapé grâce aux compteurs cumulés.
 */
class CaptureService : Service() {

    companion object {
        private const val TAG = "FluxCapture"
        private const val CHANNEL_ID = "capture"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.oseeeb.flux.action.STOP"
        private const val POLL_MS = 2_000L

        // Garde-fou si STOP n'est jamais appuyé : le système récupère le verrou.
        private const val WAKE_LOCK_TIMEOUT_MS = 12L * 60 * 60 * 1000

        /** Prévient l'app (si elle est ouverte) que la capture vient de s'arrêter. */
        var onStopped: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var reader: TrafficReader
    private lateinit var apps: AppUsageReader
    private var wakeLock: PowerManager.WakeLock? = null
    private var looping = false

    private val tick = object : Runnable {
        override fun run() {
            val autoStop = try {
                CaptureState.poll(this@CaptureService, reader)
            } catch (e: Exception) {
                Log.w(TAG, "Lecture impossible", e)
                false
            }
            if (autoStop) {
                finishCapture()
                return
            }
            notificationManager()?.notify(NOTIFICATION_ID, buildNotification())
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        reader = TrafficReader(applicationContext)
        apps = AppUsageReader(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            finishCapture()
            return START_NOT_STICKY
        }
        // Lancé par GO, ou relancé par le système (intent nul) après une fermeture.
        if (!CaptureState.isRunning(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (e: Exception) {
            // Relance refusée par le système : l'état est sauvegardé, la capture
            // sera rattrapée à la prochaine ouverture de Flux.
            Log.w(TAG, "Service au premier plan refusé", e)
            stopSelf()
            return START_NOT_STICKY
        }
        if (wakeLock?.isHeld != true) {
            wakeLock = getSystemService(PowerManager::class.java)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "flux:capture")
                ?.apply {
                    setReferenceCounted(false)
                    acquire(WAKE_LOCK_TIMEOUT_MS)
                }
        }
        if (!looping) {
            looping = true
            handler.post(tick)
        }
        return START_STICKY
    }

    private fun finishCapture() {
        CaptureState.finish(this, reader, apps)
        handler.removeCallbacks(tick)
        looping = false
        onStopped?.invoke()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        looping = false
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    private fun notificationManager() = getSystemService(NotificationManager::class.java)

    private fun buildNotification(): Notification {
        ensureChannel()
        val unit = CaptureState.unit(this)
        val title = "En direct · ${formatClock(CaptureState.elapsedMs(this))}"
        val text = "↓ ${formatRate(CaptureState.rxPerSec, unit)} · ↑ ${formatRate(CaptureState.txPerSec, unit)} · " +
            "${formatVolume(CaptureState.totalBytes(this))} depuis GO"
        val open = packageManager.getLaunchIntentForPackage(packageName)?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openIntent = PendingIntent.getActivity(
            this, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, CaptureService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_flux)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(openIntent)
            .addAction(
                Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stat_flux), "STOP", stopIntent)
                    .build(),
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager() ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Capture en cours", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Affiche le débit pendant une capture Flux"
                setShowBadge(false)
            },
        )
    }

    // Mêmes formats que l'app (lib/ui/format.dart), en unités décimales.
    private fun decimal(v: Double) = String.format(Locale.FRANCE, "%.1f", v)

    private fun formatRate(bytesPerSec: Double, unit: String): String = when (unit) {
        "megabytes" -> "${decimal(bytesPerSec / 1e6)} Mo/s"
        "megabits" -> "${decimal(bytesPerSec * 8 / 1e6)} Mb/s"
        else -> when {
            bytesPerSec >= 1e9 -> "${decimal(bytesPerSec / 1e9)} Go/s"
            bytesPerSec >= 1e6 -> "${decimal(bytesPerSec / 1e6)} Mo/s"
            else -> "${Math.round(bytesPerSec / 1e3)} Ko/s"
        }
    }

    private fun formatVolume(bytes: Long): String = when {
        bytes >= 1e9 -> "${decimal(bytes / 1e9)} Go"
        bytes >= 1e7 -> "${Math.round(bytes / 1e6)} Mo"
        bytes >= 1e6 -> "${decimal(bytes / 1e6)} Mo"
        else -> "${Math.round(bytes / 1e3)} Ko"
    }

    private fun formatClock(ms: Long): String {
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format(Locale.FRANCE, "%d:%02d:%02d", h, m, sec)
        else String.format(Locale.FRANCE, "%02d:%02d", m, sec)
    }
}
