package com.oseeeb.flux

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Consommation de chaque app, telle qu'Android la compte déjà (Réglages ›
 * Utilisation des données). Flux ne capte rien lui-même ici : il lit ces
 * chiffres à la demande, avec l'accès « Données d'utilisation » accordé par
 * l'utilisateur.
 *
 * Android sépare le premier plan (app à l'écran) de l'arrière-plan, et le
 * Wi-Fi du réseau mobile. Il range les chiffres par tranches d'environ deux
 * heures. Pour la part de chaque app pendant une capture, on ne lit donc pas
 * une période : on prend les totaux à GO et à STOP, et la différence est
 * exacte (chaque lecture force Android à relever ses compteurs).
 */
class AppUsageReader(private val context: Context) {

    companion object {
        /** Taille des tranches d'Android pour les chiffres par app. */
        const val BUCKET_MS = 2L * 60 * 60 * 1000

        /** Ordre des 8 compteurs d'une app dans un instantané. */
        val FIELDS = listOf("wifiFgRx", "wifiFgTx", "wifiBgRx", "wifiBgTx", "mobileFgRx", "mobileFgTx", "mobileBgRx", "mobileBgTx")

        /** Fin de tranche suivante : la tranche en cours compte alors en entier. */
        fun alignUp(ms: Long) = (ms / BUCKET_MS + 1) * BUCKET_MS
        fun alignDown(ms: Long) = ms / BUCKET_MS * BUCKET_MS
    }

    private val packages = context.packageManager

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

    /**
     * Les 8 compteurs de chaque uid, cumulés entre [startMs] et [endMs].
     * Avec [endMs] dans le futur, la tranche en cours compte en entier.
     */
    private fun counters(startMs: Long, endMs: Long): Map<Int, LongArray> {
        val stats = context.getSystemService(NetworkStatsManager::class.java) ?: return emptyMap()
        val byUid = mutableMapOf<Int, LongArray>()
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
                val c = byUid.getOrPut(bucket.uid) { LongArray(8) }
                val background = bucket.state != NetworkStats.Bucket.STATE_FOREGROUND
                val base = (if (type == ConnectivityManager.TYPE_WIFI) 0 else 4) + (if (background) 2 else 0)
                c[base] += bucket.rxBytes
                c[base + 1] += bucket.txBytes
            }
            result.close()
        }
        return byUid
    }

    /** Les [limit] apps qui ont le plus consommé sur la période (historique du système). */
    fun query(startMs: Long, endMs: Long, limit: Int = 60): List<Map<String, Any?>> {
        // Tranches entières : sinon Android ne compte qu'une fraction de la
        // tranche en cours, et les derniers chiffres semblent manquer.
        val all = counters(alignDown(startMs), alignUp(endMs))
        return all.entries
            .filter { it.value.sum() > 0 }
            .sortedByDescending { it.value.sum() }
            .take(limit)
            .map { (uid, c) -> describe(uid, withIcon = true) + usageMap(c) }
    }

    /**
     * Instantané des compteurs cumulés depuis [windowStartMs], pour une
     * différence plus tard ([delta]). Format JSON : { "uid": [8 nombres] }.
     */
    fun snapshot(windowStartMs: Long): JSONObject {
        val out = JSONObject()
        for ((uid, c) in counters(windowStartMs, System.currentTimeMillis() + 24 * 60 * 60 * 1000)) {
            out.put(uid.toString(), JSONArray(c.toList()))
        }
        return out
    }

    /** Ce qui a circulé depuis l'instantané [base], app par app, du plus gros au plus petit. */
    fun delta(base: JSONObject, windowStartMs: Long, withIcons: Boolean, limit: Int = 60): List<Map<String, Any?>> {
        val now = counters(windowStartMs, System.currentTimeMillis() + 24 * 60 * 60 * 1000)
        val rows = mutableListOf<Pair<Int, LongArray>>()
        for ((uid, c) in now) {
            val before = base.optJSONArray(uid.toString())
            val d = LongArray(8) { i -> (c[i] - (before?.optLong(i) ?: 0L)).coerceAtLeast(0) }
            if (d.sum() > 0) rows.add(uid to d)
        }
        return rows.sortedByDescending { it.second.sum() }
            .take(limit)
            .map { (uid, d) -> describe(uid, withIcon = withIcons) + usageMap(d) }
    }

    private fun usageMap(c: LongArray): Map<String, Any?> = FIELDS.withIndex().associate { (i, f) -> f to c[i] }

    /** Nom, paquet (et icône) d'un uid : une app, ou un groupe du système. */
    fun describe(uid: Int, withIcon: Boolean): Map<String, Any?> {
        val special = when (uid) {
            NetworkStats.Bucket.UID_REMOVED -> "Apps désinstallées"
            NetworkStats.Bucket.UID_TETHERING -> "Partage de connexion"
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
            val system = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                packages.getLaunchIntentForPackage(pkg) == null
            val label = info.loadLabel(packages).toString()
            val map = mutableMapOf<String, Any?>(
                "uid" to uid,
                "name" to if (names.size > 1) "$label (+${names.size - 1})" else label,
                "package" to pkg,
                "system" to system,
            )
            if (withIcon) map["icon"] = iconPng(info.loadIcon(packages))
            map
        } catch (_: PackageManager.NameNotFoundException) {
            mapOf("uid" to uid, "name" to pkg, "package" to pkg, "system" to true)
        }
    }

    /** Icônes de plusieurs apps, par uid (pour un résumé gardé sans icônes). */
    fun icons(uids: List<Int>): Map<String, ByteArray> {
        val out = mutableMapOf<String, ByteArray>()
        for (uid in uids) {
            val icon = describe(uid, withIcon = true)["icon"] as? ByteArray ?: continue
            out[uid.toString()] = icon
        }
        return out
    }

    private fun iconPng(drawable: Drawable): ByteArray? = try {
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
