import 'package:flutter_test/flutter_test.dart';
import 'package:flux/traffic/channel.dart';
import 'package:flux/traffic/rate_meter.dart';
import 'package:flux/traffic/snapshot.dart';

TrafficSnapshot snap(int ms, Map<Channel, (int, int)?> values, {int? bits}) {
  return TrafficSnapshot(
    timestampMs: ms,
    counterBits: bits,
    channels: {
      for (final e in values.entries)
        e.key: e.value == null
            ? const ChannelReading(connected: true, measurable: false)
            : ChannelReading(connected: true, measurable: true, rxBytes: e.value!.$1, txBytes: e.value!.$2),
    },
  );
}

void main() {
  group('counterDelta', () {
    test('compteur qui avance', () => expect(counterDelta(100, 350), 250));
    test('valeur manquante', () => expect(counterDelta(null, 350), 0));
    test('compteur remis à zéro sans bouclage', () => expect(counterDelta(5000, 20), 0));
    test('compteur 32 bits qui boucle', () {
      const max = 1 << 32;
      expect(counterDelta(max - 100, 50, wrapBits: 32), 150);
    });
  });

  test('computeRates divise par le temps écoulé', () {
    final a = snap(1000, {Channel.wifi: (0, 0), Channel.mobile: (1000, 500)});
    final b = snap(3000, {Channel.wifi: (4000000, 400000), Channel.mobile: (3000, 500)});
    final rates = computeRates(a, b);
    expect(rates[Channel.wifi]!.rxPerSec, 2000000);
    expect(rates[Channel.wifi]!.txPerSec, 200000);
    expect(rates[Channel.wifi]!.rxBytes, 4000000);
    expect(rates[Channel.mobile]!.rxPerSec, 1000);
    expect(rates[Channel.usb]!.rxPerSec, 0);
  });

  test('canal non mesurable : débit nul', () {
    final a = snap(0, {Channel.bluetooth: null});
    final b = snap(1000, {Channel.bluetooth: null});
    expect(computeRates(a, b)[Channel.bluetooth]!.rxPerSec, 0);
  });

  test('lecture native décodée', () {
    final s = TrafficSnapshot.fromMap({
      'timestampMs': 42,
      'counterBits': 32,
      'channels': {
        'wifi': {'connected': true, 'measurable': true, 'rx': 10, 'tx': 5},
        'bluetooth': {'connected': false, 'measurable': false, 'supported': false},
        'inconnu': {'connected': true},
      },
    });
    expect(s.timestampMs, 42);
    expect(s.counterBits, 32);
    expect(s[Channel.wifi].rxBytes, 10);
    expect(s[Channel.bluetooth].supported, isFalse);
    expect(s[Channel.usb].measurable, isFalse);
  });
}
