package com.oseeeb.flux

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val reader = TrafficReader(applicationContext)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.oseeeb.flux/traffic")
        CaptureService.onStopRequested = { channel.invokeMethod("stopRequested", null) }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> try {
                    result.success(reader.snapshot())
                } catch (e: Exception) {
                    result.error("read_failed", e.message, null)
                }
                "captureStarted" -> {
                    requestNotificationPermission()
                    CaptureService.start(applicationContext, call.argument("title") ?: "", call.argument("text") ?: "")
                    result.success(null)
                }
                "captureUpdate" -> {
                    CaptureService.update(applicationContext, call.argument("title") ?: "", call.argument("text") ?: "")
                    result.success(null)
                }
                "captureStopped" -> {
                    CaptureService.stop(applicationContext)
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
        CaptureService.onStopRequested = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // Sans l'app, plus personne ne mesure : on retire la notification.
        if (isFinishing) CaptureService.stop(applicationContext)
        super.onDestroy()
    }

    /** Android 13+ : la notification « En direct » demande l'accord de l'utilisateur. */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }
}
