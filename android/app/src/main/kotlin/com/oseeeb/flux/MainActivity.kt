package com.oseeeb.flux

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val reader = TrafficReader(applicationContext)
        val apps = AppUsageReader(applicationContext)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.oseeeb.flux/traffic")
        CaptureService.onStopped = { runOnUiThread { channel.invokeMethod("captureStopped", null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> try {
                    result.success(reader.snapshot())
                } catch (e: Exception) {
                    result.error("read_failed", e.message, null)
                }
                "captureStart" -> {
                    requestNotificationPermission()
                    CaptureState.begin(
                        applicationContext,
                        reader,
                        call.argument<String>("unit") ?: "auto",
                        (call.argument<Number>("autoStopSec") ?: 0).toLong(),
                    )
                    CaptureService.start(applicationContext)
                    result.success(null)
                }
                "captureState" -> {
                    val state = CaptureState.current(applicationContext)
                    // Capture en cours mais service arrêté par le système : on le relance
                    // (l'app est au premier plan, c'est permis).
                    if (state != null) CaptureService.start(applicationContext)
                    result.success(state)
                }
                "captureStop" -> {
                    val summary = CaptureState.finish(applicationContext, reader)
                    CaptureService.stop(applicationContext)
                    result.success(summary)
                }
                "takeFinished" -> result.success(CaptureState.takeFinished(applicationContext))
                "appUsageAccess" -> result.success(apps.hasAccess())
                "openUsageAccessSettings" -> {
                    openSettings(
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.fromParts("package", packageName, null)),
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
                    )
                    result.success(null)
                }
                "appUsage" -> {
                    val start = (call.argument<Number>("startMs") ?: 0).toLong()
                    val end = (call.argument<Number>("endMs") ?: System.currentTimeMillis()).toLong()
                    // Lecture et icônes : hors du fil de l'interface.
                    Thread {
                        val data = runCatching { apps.query(start, end) }
                        runOnUiThread {
                            data.fold(
                                { result.success(it) },
                                { result.error("app_usage_failed", it.message, null) },
                            )
                        }
                    }.start()
                }
                "openAppDetails" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg != null) {
                        openSettings(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null)),
                        )
                    }
                    result.success(null)
                }
                "backgroundRestricted" -> result.success(isBatteryOptimized())
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        CaptureService.onStopped = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Android 13+ : la notification « En direct » demande l'accord de l'utilisateur. */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    /** `true` si l'économie de batterie peut fermer Flux en arrière-plan. */
    private fun isBatteryOptimized(): Boolean {
        val power = getSystemService(PowerManager::class.java) ?: return false
        return !power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Ouvre la liste des optimisations de batterie, où l'utilisateur peut
     * choisir « Ne pas optimiser » pour Flux. Certains fabricants ajoutent
     * leur propre réglage ; à défaut, on ouvre la page de l'app.
     */
    private fun openBatterySettings() = openSettings(
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)),
    )

    /** Ouvre la première page de réglages qui existe sur ce téléphone. */
    private fun openSettings(vararg intents: Intent) {
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: android.content.ActivityNotFoundException) {
                // Page absente sur ce téléphone : on essaie la suivante.
            }
        }
    }
}
