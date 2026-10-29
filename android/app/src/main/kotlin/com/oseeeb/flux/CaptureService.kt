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
import android.os.IBinder
import android.os.PowerManager

/**
 * Service au premier plan qui garde Flux en vie pendant une capture, même
 * quand on utilise d'autres apps. Il affiche la notification « En direct »
 * (débit, volume) avec un bouton STOP. La mesure elle-même reste dans le
 * code Dart : le service ne lit ni ne garde aucune donnée.
 */
class CaptureService : Service() {

    companion object {
        private const val CHANNEL_ID = "capture"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "com.oseeeb.flux.action.STOP"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        // Garde-fou si STOP n'est jamais appuyé : le système récupère le verrou.
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000

        /** Appelé quand l'utilisateur appuie sur STOP dans la notification. */
        var onStopRequested: (() -> Unit)? = null

        @Volatile
        private var running = false

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, CaptureService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, text: String) {
            if (!running) return
            context.getSystemService(NotificationManager::class.java)
                ?.notify(NOTIFICATION_ID, buildNotification(context, title, text))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureService::class.java))
        }

        private fun buildNotification(context: Context, title: String, text: String): Notification {
            ensureChannel(context)
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val openIntent = PendingIntent.getActivity(
                context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val stopIntent = PendingIntent.getService(
                context, 1,
                Intent(context, CaptureService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
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
                    Notification.Action.Builder(
                        Icon.createWithResource(context, R.drawable.ic_stat_flux), "STOP", stopIntent,
                    ).build(),
                )
                .build()
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Capture en cours", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Affiche le débit pendant une capture Flux"
                    setShowBadge(false)
                },
            )
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            onStopRequested?.invoke() ?: stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "Flux · En direct",
            intent?.getStringExtra(EXTRA_TEXT) ?: "",
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        // Écran éteint, le processeur s'endormirait et la mesure s'arrêterait.
        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "flux:capture")
                ?.apply { acquire(WAKE_LOCK_TIMEOUT_MS) }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // L'app a été fermée depuis les apps récentes : la capture s'arrête avec elle.
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }
}
