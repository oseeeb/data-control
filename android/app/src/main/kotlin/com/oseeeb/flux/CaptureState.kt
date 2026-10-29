package com.oseeeb.flux

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject

/**
 * La capture en cours, côté Android. Elle survit à la fermeture de l'app par
 * le système : l'état (début, totaux, derniers compteurs) est sauvegardé
 * pendant la capture, puis effacé à l'arrêt.
 *
 * Comme les compteurs du système sont cumulés depuis le démarrage du
 * téléphone, un temps sans lecture (app tuée, service relancé plus tard) est
 * rattrapé à la lecture suivante : rien n'est perdu, sauf après un redémarrage.
 *
 * Seuls des nombres d'octets par canal sont gardés, jamais le contenu du
 * trafic. Les captures terminées attendent dans [takeFinished] que l'app les
 * reprenne (et les mette dans l'historique si l'utilisateur l'a activé).
 */
object CaptureState {
    private const val PREFS = "flux_capture"
    private const val KEY_STATE = "state"
    private const val KEY_FINISHED = "finished"
    private val CHANNELS = listOf("wifi", "mobile", "usb", "bluetooth")

    /** Débit total entrant / sortant à la dernière lecture, pour la notification. */
    @Volatile var rxPerSec = 0.0
        private set
    @Volatile var txPerSec = 0.0
        private set

    private var state: JSONObject? = null
    private var lastSave = 0L

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Heure (murale) du dernier démarrage du téléphone, pour repérer un redémarrage. */
    private fun bootTime() = System.currentTimeMillis() - SystemClock.elapsedRealtime()

    @Synchronized
    private fun load(context: Context): JSONObject? {
        if (state == null) {
            state = prefs(context).getString(KEY_STATE, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
        }
        return state
    }

    @Synchronized
    private fun save(context: Context, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastSave < 10_000) return
        lastSave = now
        prefs(context).edit().putString(KEY_STATE, state?.toString()).apply()
    }

    @Synchronized
    fun isRunning(context: Context) = load(context) != null

    /** GO : nouvelle capture. [autoStopSec] = 0 pour jamais. */
    @Synchronized
    fun begin(context: Context, reader: TrafficReader, unit: String, autoStopSec: Long) {
        val counters = readCounters(reader)
        state = JSONObject()
            .put("startedAt", System.currentTimeMillis())
            .put("bootTime", bootTime())
            .put("unit", unit)
            .put("autoStopSec", autoStopSec)
            .put("rx", JSONObject())
            .put("tx", JSONObject())
            .put("last", counters)
            .put("lastPoll", SystemClock.elapsedRealtime())
        rxPerSec = 0.0
        txPerSec = 0.0
        save(context, force = true)
    }

    /**
     * Lit les compteurs et ajoute ce qui a circulé depuis la lecture
     * précédente. Renvoie `true` si l'arrêt automatique est atteint.
     */
    @Synchronized
    fun poll(context: Context, reader: TrafficReader): Boolean {
        val s = load(context) ?: return false
        val counters = readCounters(reader)
        val now = SystemClock.elapsedRealtime()
        val rebooted = Math.abs(s.getLong("bootTime") - bootTime()) > 60_000
        val last = s.getJSONObject("last")
        val rx = s.getJSONObject("rx")
        val tx = s.getJSONObject("tx")
        var rxDelta = 0L
        var txDelta = 0L
        if (!rebooted) {
            for (c in CHANNELS) {
                val cur = counters.optJSONObject(c) ?: continue
                val prev = last.optJSONObject(c) ?: continue
                // Compteur remis à zéro (interface reconnectée) : on ne compte rien.
                val dRx = (cur.getLong("rx") - prev.getLong("rx")).coerceAtLeast(0)
                val dTx = (cur.getLong("tx") - prev.getLong("tx")).coerceAtLeast(0)
                rx.put(c, rx.optLong(c) + dRx)
                tx.put(c, tx.optLong(c) + dTx)
                rxDelta += dRx
                txDelta += dTx
            }
        } else {
            s.put("bootTime", bootTime())
        }
        val seconds = (now - s.optLong("lastPoll", now)) / 1000.0
        // Après un long trou (app tuée), le débit moyen n'a pas de sens : 0.
        rxPerSec = if (seconds in 0.2..10.0) rxDelta / seconds else 0.0
        txPerSec = if (seconds in 0.2..10.0) txDelta / seconds else 0.0
        s.put("last", counters).put("lastPoll", now)
        save(context)
        val autoStop = s.optLong("autoStopSec")
        return autoStop > 0 && elapsedMs(s) >= autoStop * 1000
    }

    private fun elapsedMs(s: JSONObject) = System.currentTimeMillis() - s.getLong("startedAt")

    /** L'état pour l'app : début, totaux par canal. `null` s'il n'y a pas de capture. */
    @Synchronized
    fun current(context: Context): Map<String, Any>? {
        val s = load(context) ?: return null
        return summary(s, ended = false)
    }

    /** STOP : termine la capture, la range parmi les captures terminées et la renvoie. */
    @Synchronized
    fun finish(context: Context, reader: TrafficReader): Map<String, Any>? {
        if (load(context) == null) return null
        poll(context, reader)
        val s = state ?: return null
        val result = summary(s, ended = true)
        val finished = runCatching { JSONArray(prefs(context).getString(KEY_FINISHED, "[]")) }.getOrDefault(JSONArray())
        finished.put(JSONObject(result))
        state = null
        rxPerSec = 0.0
        txPerSec = 0.0
        prefs(context).edit().remove(KEY_STATE).putString(KEY_FINISHED, finished.toString()).commit()
        return result
    }

    /** Les captures terminées que l'app n'a pas encore reprises. */
    @Synchronized
    fun takeFinished(context: Context): List<Map<String, Any>> {
        val raw = prefs(context).getString(KEY_FINISHED, "[]")
        prefs(context).edit().remove(KEY_FINISHED).commit()
        val array = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return (0 until array.length()).map { toMap(array.getJSONObject(it)) }
    }

    fun unit(context: Context): String = load(context)?.optString("unit", "auto") ?: "auto"

    fun totalBytes(context: Context): Long {
        val s = load(context) ?: return 0
        return CHANNELS.sumOf { s.getJSONObject("rx").optLong(it) + s.getJSONObject("tx").optLong(it) }
    }

    fun elapsedMs(context: Context): Long = load(context)?.let { elapsedMs(it) } ?: 0

    private fun summary(s: JSONObject, ended: Boolean): Map<String, Any> {
        var duration = elapsedMs(s) / 1000
        val autoStop = s.optLong("autoStopSec")
        if (ended && autoStop > 0) duration = duration.coerceAtMost(autoStop)
        return mapOf(
            "startedAtMs" to s.getLong("startedAt"),
            "durationSec" to duration,
            "rx" to toMap(s.getJSONObject("rx")),
            "tx" to toMap(s.getJSONObject("tx")),
        )
    }

    private fun readCounters(reader: TrafficReader): JSONObject {
        val out = JSONObject()
        @Suppress("UNCHECKED_CAST")
        val channels = reader.snapshot()["channels"] as Map<String, Map<String, Any?>>
        for ((name, c) in channels) {
            val rx = c["rx"] as? Long ?: continue
            val tx = c["tx"] as? Long ?: continue
            out.put(name, JSONObject().put("rx", rx).put("tx", tx))
        }
        return out
    }

    private fun toMap(o: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        for (key in o.keys()) {
            val v = o.get(key)
            map[key] = when (v) {
                is JSONObject -> toMap(v)
                is Int -> v.toLong()
                else -> v
            }
        }
        return map
    }
}
