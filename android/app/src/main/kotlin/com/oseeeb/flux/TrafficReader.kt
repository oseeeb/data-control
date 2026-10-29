package com.oseeeb.flux

import android.bluetooth.BluetoothManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.Build
import android.os.SystemClock
import java.io.File
import java.net.NetworkInterface

/**
 * Lit les compteurs d'octets de chaque canal (Wi-Fi, mobile, USB, Bluetooth).
 *
 * Rien n'est conservé : chaque appel renvoie l'état instantané des compteurs
 * cumulés du système. Le calcul des débits se fait côté Dart.
 */
class TrafficReader(private val context: Context) {

    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    private data class Counters(val rx: Long, val tx: Long)

    fun snapshot(): Map<String, Any?> {
        val wifiIfaces = mutableSetOf<String>()
        val usbIfaces = mutableSetOf<String>()
        val btIfaces = mutableSetOf<String>()
        var wifiUp = false
        var mobileUp = false
        var usbUp = false
        var btNetworkUp = false

        // Réseaux que le téléphone utilise (en amont).
        @Suppress("DEPRECATION")
        for (network in connectivity?.allNetworks.orEmpty()) {
            val caps = connectivity?.getNetworkCapabilities(network) ?: continue
            val iface = connectivity.getLinkProperties(network)?.interfaceName
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> {
                    wifiUp = true
                    iface?.let(wifiIfaces::add)
                }
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> mobileUp = true
                caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> {
                    btNetworkUp = true
                    iface?.let(btIfaces::add)
                }
                isUsbTransport(caps) -> {
                    usbUp = true
                    iface?.let(usbIfaces::add)
                }
            }
        }

        // Interfaces de partage de connexion (en aval) : rndis0, ncm0, bt-pan…
        for (name in interfaceNames()) {
            when {
                name.startsWith("rndis") || name.startsWith("ncm") || name.startsWith("usb") -> {
                    usbIfaces.add(name)
                    if (isUp(name)) usbUp = true
                }
                name.startsWith("bt-pan") -> {
                    btIfaces.add(name)
                    if (isUp(name)) btNetworkUp = true
                }
                name.startsWith("wlan") && wifiIfaces.isEmpty() -> wifiIfaces.add(name)
            }
        }

        val mobile = mobileCounters()
        val usb = sumInterfaces(usbIfaces)
        val bluetooth = sumInterfaces(btIfaces)
        val wifi = sumInterfaces(wifiIfaces) ?: wifiByDifference(mobile, usb, bluetooth)
        val btOn = bluetoothEnabled()

        return mapOf(
            "timestampMs" to SystemClock.elapsedRealtime(),
            "channels" to mapOf(
                "wifi" to channel(wifiUp, wifi, null),
                "mobile" to channel(mobileUp, mobile, null),
                "usb" to channel(usbUp, usb, if (usbUp) "Partage par câble" else null),
                "bluetooth" to channel(
                    btOn || btNetworkUp,
                    if (btNetworkUp) bluetooth else null,
                    if (btNetworkUp) "Partage de connexion" else null,
                ),
            ),
        )
    }

    private fun channel(connected: Boolean, counters: Counters?, detail: String?): Map<String, Any?> = mapOf(
        "connected" to connected,
        "measurable" to (counters != null),
        "rx" to counters?.rx,
        "tx" to counters?.tx,
        "detail" to detail,
    )

    private fun isUsbTransport(caps: NetworkCapabilities): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            caps.hasTransport(NetworkCapabilities.TRANSPORT_USB)
        ) return true
        // Adaptateur Ethernet branché en USB-C.
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun mobileCounters(): Counters? {
        val rx = TrafficStats.getMobileRxBytes()
        val tx = TrafficStats.getMobileTxBytes()
        if (rx == TrafficStats.UNSUPPORTED.toLong() || tx == TrafficStats.UNSUPPORTED.toLong()) return null
        return Counters(rx, tx)
    }

    /**
     * Quand le Wi-Fi ne peut pas être lu directement, on le déduit :
     * total du téléphone moins les autres canaux connus.
     */
    private fun wifiByDifference(mobile: Counters?, usb: Counters?, bt: Counters?): Counters? {
        val totalRx = TrafficStats.getTotalRxBytes()
        val totalTx = TrafficStats.getTotalTxBytes()
        if (totalRx == TrafficStats.UNSUPPORTED.toLong() || totalTx == TrafficStats.UNSUPPORTED.toLong()) return null
        val others = listOfNotNull(mobile, usb, bt)
        val rx = totalRx - others.sumOf { it.rx }
        val tx = totalTx - others.sumOf { it.tx }
        return Counters(rx.coerceAtLeast(0), tx.coerceAtLeast(0))
    }

    private fun sumInterfaces(names: Set<String>): Counters? {
        var rx = 0L
        var tx = 0L
        var found = false
        for (name in names) {
            val c = interfaceCounters(name) ?: continue
            rx += c.rx
            tx += c.tx
            found = true
        }
        return if (found) Counters(rx, tx) else null
    }

    /** Compteurs d'une interface : sysfs d'abord, puis l'API système si elle répond. */
    private fun interfaceCounters(name: String): Counters? {
        val rx = readSys(name, "rx_bytes") ?: hiddenTrafficStat("getRxBytes", name)
        val tx = readSys(name, "tx_bytes") ?: hiddenTrafficStat("getTxBytes", name)
        return if (rx != null && tx != null) Counters(rx, tx) else null
    }

    private fun readSys(iface: String, file: String): Long? = try {
        File("/sys/class/net/$iface/statistics/$file").readText().trim().toLongOrNull()
    } catch (_: Exception) {
        null
    }

    private fun hiddenTrafficStat(method: String, iface: String): Long? = try {
        val value = TrafficStats::class.java.getMethod(method, String::class.java).invoke(null, iface) as Long
        if (value >= 0) value else null
    } catch (_: Throwable) {
        null
    }

    private fun isUp(iface: String): Boolean = try {
        NetworkInterface.getByName(iface)?.isUp == true
    } catch (_: Exception) {
        File("/sys/class/net/$iface/operstate").let { it.exists() && it.readText().trim() == "up" }
    }

    private fun interfaceNames(): Set<String> {
        val names = mutableSetOf<String>()
        try {
            NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { names.add(it.name) }
        } catch (_: Exception) {
        }
        try {
            File("/sys/class/net").list()?.let { names.addAll(it) }
        } catch (_: Exception) {
        }
        return names
    }

    private fun bluetoothEnabled(): Boolean = try {
        context.getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true
    } catch (_: SecurityException) {
        false
    }
}
