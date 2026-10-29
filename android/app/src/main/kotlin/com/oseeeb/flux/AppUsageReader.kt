package com.oseeeb.flux

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * Consommation de chaque app, telle qu'Android la compte déjà (Réglages ›
 * Utilisation des données). Flux ne capte rien lui-même ici : il lit ces
 * chiffres à la demande, avec l'accès « Données d'utilisation » accordé par
 * l'utilisateur, et ne les garde pas.
 *
 * Android sépare le premier plan (app à l'écran) de l'arrière-plan, et le
 * Wi-Fi du réseau mobile. Il regroupe les chiffres par tranches d'environ
 * deux heures : une analyse sur 24 h est donc précise à ~2 h près.
 */
class AppUsageReader(private val context: Context) {

    private val packages = context.packageManager

    private class Usage {
        var wifiFgRx = 0L; var wifiFgTx = 0L; var wifiBgRx = 0L; var wifiBgTx = 0L
        var mobileFgRx = 0L; var mobileFgTx = 0L; var mobileBgRx = 0L; var mobileBgTx = 0L
        val total get() = wifiFgRx + wifiFgTx + wifiBgRx + wifiBgTx + mobileFgRx + mobileFgTx + mobileBgRx + mobileBgTx
    }

    /** L'utilisateur a-t-il donné l'accès « Données d'utilisation » ? */
    fun hasAccess(): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java) ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Les [limit] apps qui ont le plus consommé entre [startMs] et [endMs]. */
    fun query(startMs: Long, endMs: Long, limit: Int = 60): List<Map<String, Any?>> {
        val stats = context.getSystemService(NetworkStatsManager::class.java) ?: return emptyList()
        val byUid = mutableMapOf<Int, Usage>()
        for (type in listOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE)) {
            val result = try {
                stats.querySummary(type, null, startMs, endMs)
            } catch (e: Exception) {
                // Android 9 et avant : le détail mobile demande une permission
                // téléphone que Flux ne demande pas. On garde le Wi-Fi.
                Log.w("FluxApps", "Lecture impossible (type $type)", e)
                null
            } ?: continue
            val bucket = NetworkStats.Bucket()
            while (result.hasNextBucket()) {
                result.getNextBucket(bucket)
                val u = byUid.getOrPut(bucket.uid) { Usage() }
                val background = bucket.state != NetworkStats.Bucket.STATE_FOREGROUND
                val wifi = type == ConnectivityManager.TYPE_WIFI
                when {
                    wifi && background -> { u.wifiBgRx += bucket.rxBytes; u.wifiBgTx += bucket.txBytes }
                    wifi -> { u.wifiFgRx += bucket.rxBytes; u.wifiFgTx += bucket.txBytes }
                    background -> { u.mobileBgRx += bucket.rxBytes; u.mobileBgTx += bucket.txBytes }
                    else -> { u.mobileFgRx += bucket.rxBytes; u.mobileFgTx += bucket.txBytes }
                }
            }
            result.close()
        }
        return byUid.entries
            .filter { it.value.total > 0 }
            .sortedByDescending { it.value.total }
            .take(limit)
            .map { (uid, u) -> describe(uid) + usageMap(u) }
    }

    private fun usageMap(u: Usage): Map<String, Any?> = mapOf(
        "wifiFgRx" to u.wifiFgRx, "wifiFgTx" to u.wifiFgTx, "wifiBgRx" to u.wifiBgRx, "wifiBgTx" to u.wifiBgTx,
        "mobileFgRx" to u.mobileFgRx, "mobileFgTx" to u.mobileFgTx,
        "mobileBgRx" to u.mobileBgRx, "mobileBgTx" to u.mobileBgTx,
    )

    /** Nom, paquet et icône d'un uid (une app, ou un groupe système). */
    private fun describe(uid: Int): Map<String, Any?> {
        val special = when (uid) {
            TrafficStats.UID_REMOVED -> "Apps désinstallées"
            TrafficStats.UID_TETHERING -> "Partage de connexion"
            Process.SYSTEM_UID, 0 -> "Système Android"
            else -> null
        }
        if (special != null) return mapOf("uid" to uid, "name" to special, "system" to true)

        val names = packages.getPackagesForUid(uid)?.toList().orEmpty()
        // Plusieurs paquets peuvent partager un uid : on préfère celui qui a une icône d'accueil.
        val pkg = names.firstOrNull { packages.getLaunchIntentForPackage(it) != null } ?: names.firstOrNull()
            ?: return mapOf("uid" to uid, "name" to "Système (uid $uid)", "system" to true)
        return try {
            val info = packages.getApplicationInfo(pkg, 0)
            val system = (info.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0 &&
                packages.getLaunchIntentForPackage(pkg) == null
            val label = info.loadLabel(packages).toString()
            mapOf(
                "uid" to uid,
                "name" to if (names.size > 1) "$label (+${names.size - 1})" else label,
                "package" to pkg,
                "system" to system,
                "icon" to iconPng(info.loadIcon(packages)),
            )
        } catch (_: PackageManager.NameNotFoundException) {
            mapOf("uid" to uid, "name" to pkg, "package" to pkg, "system" to true)
        }
    }

    private fun iconPng(drawable: android.graphics.drawable.Drawable): ByteArray? = try {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    } catch (_: Exception) {
        null
    }
}
