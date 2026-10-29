import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/traffic/capture_host.dart';
import 'package:flux/traffic/channel.dart';
import 'package:flux/traffic/snapshot.dart';
import 'package:flux/traffic/traffic_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compteurs réglables à la main.
class ManualSource implements TrafficSource {
  int wifi = 1000;
  int? bits;

  @override
  Future<TrafficSnapshot> read() async => TrafficSnapshot(
    timestampMs: 0,
    counterBits: bits,
    channels: {Channel.wifi: ChannelReading(connected: true, measurable: true, rxBytes: wifi, txBytes: wifi ~/ 10)},
  );
}

void main() {
  late ManualSource source;
  var now = DateTime(2026, 10, 29, 10);

  CaptureHost newHost() => CheckpointCaptureHost(source, now: () => now);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = ManualSource();
    now = DateTime(2026, 10, 29, 10);
  });

  test('la capture survit à la fermeture de l’app', () async {
    await newHost().start(unit: RateUnit.auto);
    source.wifi += 50000000;
    now = now.add(const Duration(minutes: 20));

    // Nouvelle instance : l'app a été fermée puis rouverte.
    final reopened = newHost();
    final current = await reopened.current();
    expect(current!.rxBytes[Channel.wifi], 50000000);
    expect(current.duration, const Duration(minutes: 20));

    final done = await reopened.stop();
    expect(done!.rxBytes[Channel.wifi], 50000000);
    expect(await reopened.takeFinished(), [done]);
    expect(await reopened.current(), isNull);
  });

  test('compteur 32 bits qui boucle une fois', () async {
    source
      ..bits = 32
      ..wifi = (1 << 32) - 1000;
    final host = newHost();
    await host.start(unit: RateUnit.auto);
    source.wifi = 4000;
    expect((await host.current())!.rxBytes[Channel.wifi], 5000);
  });

  test('redémarrage du téléphone : on garde le dernier état connu', () async {
    final host = newHost();
    await host.start(unit: RateUnit.auto);
    source.wifi += 7000000;
    now = now.add(const Duration(minutes: 5));
    await host.current();

    source.wifi = 10; // compteurs repartis de zéro
    now = now.add(const Duration(hours: 1));
    final done = await host.stop();
    expect(done!.rxBytes[Channel.wifi], 7000000);
    expect(done.duration, const Duration(minutes: 5));
  });

  test('arrêt automatique : la durée est plafonnée', () async {
    final host = newHost();
    await host.start(unit: RateUnit.auto, autoStop: const Duration(minutes: 15));
    now = now.add(const Duration(hours: 2));
    expect((await host.stop())!.duration, const Duration(minutes: 15));
  });
}
