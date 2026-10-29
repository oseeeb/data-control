package com.oseeeb.flux

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val reader = TrafficReader(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.oseeeb.flux/traffic")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> try {
                        result.success(reader.snapshot())
                    } catch (e: Exception) {
                        result.error("read_failed", e.message, null)
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
}
