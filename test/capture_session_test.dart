import 'package:flutter_test/flutter_test.dart';
import 'package:flux/traffic/capture_session.dart';
import 'package:flux/traffic/channel.dart';

import 'fake_source.dart';

void main() {
  test('mesure les débits et les volumes, puis efface tout à l\'arrêt', () {
    final source = FakeTrafficSource();
    final session = CaptureSession(source);
    addTearDown(session.dispose);

    session.ingest(source.at(0));
    session.start();
    session.ingest(source.at(1));
    session.ingest(source.at(2));

    expect(session.running, isTrue);
    expect(session.rate(Channel.wifi).rxPerSec, 2000000);
    expect(session.rate(Channel.mobile).rxPerSec, 500000);
    expect(session.rate(Channel.bluetooth).rxPerSec, 0);
    expect(session.rxTotal(Channel.wifi), 4000000);
    expect(session.rxHistory(Channel.wifi), [2000000, 2000000]);
    expect(session.totalRxPerSec, 2500000);

    final summary = session.stop();
    expect(summary.rxBytes[Channel.wifi], 4000000);
    expect(summary.txBytes[Channel.wifi], 400000);
    expect(summary.volumeOf(Channel.mobile), 1100000);
    expect(summary.total, 5500000);

    expect(session.running, isFalse);
    expect(session.rxTotal(Channel.wifi), 0);
    expect(session.rxHistory(Channel.wifi), isEmpty);
    expect(session.takeSummary(), isNotNull);
    expect(session.takeSummary(), isNull, reason: 'le résumé ne se lit qu\'une fois');
  });

  test('historique limité aux 60 dernières secondes', () {
    final source = FakeTrafficSource();
    final session = CaptureSession(source);
    addTearDown(session.dispose);
    session.ingest(source.at(0));
    session.start();
    for (var i = 1; i <= 90; i++) {
      session.ingest(source.at(i));
    }
    expect(session.rxHistory(Channel.wifi).length, CaptureSession.historyLength);
  });

  test('arrêt automatique', () {
    final source = FakeTrafficSource();
    final clock = _FakeStopwatch();
    final session = CaptureSession(source, stopwatch: () => clock);
    addTearDown(session.dispose);
    session.ingest(source.at(0));
    session.start(autoStop: const Duration(minutes: 5));
    session.ingest(source.at(1));
    expect(session.running, isTrue);
    clock.fake = const Duration(minutes: 5);
    session.ingest(source.at(2));
    expect(session.running, isFalse);
    expect(session.takeSummary()!.rxBytes[Channel.wifi], 4000000);
  });
}

class _FakeStopwatch extends Stopwatch {
  Duration fake = Duration.zero;

  @override
  Duration get elapsed => fake;
}
