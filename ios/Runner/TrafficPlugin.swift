import Flutter
import UIKit

/// Canal de méthodes « com.oseeeb.flux/traffic », côté iOS.
final class TrafficPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.oseeeb.flux/traffic", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TrafficPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "snapshot":
      result(TrafficReader.snapshot())
    case "openAppSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Lit les compteurs d'octets des interfaces réseau (getifaddrs).
///
/// en0 = Wi-Fi, pdp_ip* = données mobiles, en2 et plus = adaptateurs USB.
/// iOS ne donne pas le trafic Bluetooth. Rien n'est conservé.
enum TrafficReader {
  private enum Kind { case wifi, mobile, usb }

  private struct Totals {
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var found = false
    var connected = false
  }

  private static func kind(of name: String) -> Kind? {
    if name == "en0" { return .wifi }
    if name.hasPrefix("pdp_ip") { return .mobile }
    if name.hasPrefix("en"), let n = Int(name.dropFirst(2)), n >= 2 { return .usb }
    return nil
  }

  static func snapshot() -> [String: Any] {
    var totals: [Kind: Totals] = [.wifi: Totals(), .mobile: Totals(), .usb: Totals()]

    var head: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&head) == 0 {
      var cursor = head
      while let ifa = cursor {
        defer { cursor = ifa.pointee.ifa_next }
        guard let addr = ifa.pointee.ifa_addr,
              let k = kind(of: String(cString: ifa.pointee.ifa_name)) else { continue }
        let flags = Int32(ifa.pointee.ifa_flags)
        let family = Int32(addr.pointee.sa_family)

        if family == AF_LINK, let raw = ifa.pointee.ifa_data {
          let data = raw.assumingMemoryBound(to: if_data.self).pointee
          totals[k]!.rx += UInt64(data.ifi_ibytes)
          totals[k]!.tx += UInt64(data.ifi_obytes)
          totals[k]!.found = true
        } else if family == AF_INET || family == AF_INET6,
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0 {
          totals[k]!.connected = true
        }
      }
      freeifaddrs(head)
    }

    func channel(_ k: Kind, detail: String? = nil) -> [String: Any] {
      let t = totals[k]!
      var map: [String: Any] = ["connected": t.connected, "measurable": t.found]
      if t.found {
        map["rx"] = Int(t.rx)
        map["tx"] = Int(t.tx)
      }
      if t.connected, let detail { map["detail"] = detail }
      return map
    }

    return [
      "timestampMs": Int(ProcessInfo.processInfo.systemUptime * 1000),
      // Les compteurs if_data sont sur 32 bits : ils repartent de 0 après 4 Go.
      "counterBits": 32,
      "channels": [
        "wifi": channel(.wifi),
        "mobile": channel(.mobile),
        "usb": channel(.usb, detail: "Adaptateur"),
        "bluetooth": ["connected": false, "measurable": false, "supported": false],
      ],
    ]
  }
}
