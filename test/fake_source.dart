import 'package:flux/traffic/channel.dart';
import 'package:flux/traffic/snapshot.dart';
import 'package:flux/traffic/traffic_source.dart';

/// Source simulée : le Wi-Fi reçoit 2 Mo et envoie 200 Ko par lecture,
/// le mobile 500 Ko, l'USB n'est pas branché, le Bluetooth n'est pas mesurable.
class FakeTrafficSource implements TrafficSource {
  int reads = 0;

  TrafficSnapshot at(int n) => TrafficSnapshot(
    timestampMs: n * 1000,
    channels: {
      Channel.wifi: ChannelReading(connected: true, measurable: true, rxBytes: n * 2000000, txBytes: n * 200000),
      Channel.mobile: ChannelReading(
        connected: true,
        measurable: true,
        rxBytes: n * 500000,
        txBytes: n * 50000,
        detail: '4G',
      ),
      Channel.usb: const ChannelReading(connected: false, measurable: false),
      Channel.bluetooth: const ChannelReading(connected: true, measurable: false),
    },
  );

  @override
  Future<TrafficSnapshot> read() async => at(reads++);
}
