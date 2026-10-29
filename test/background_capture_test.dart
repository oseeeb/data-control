import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/history/history_store.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_host.dart';
import 'package:flux/traffic/capture_session.dart';
import 'package:flux/traffic/channel.dart';

import 'fake_source.dart';

/// Hôte simulé, comme le service Android : il garde sa propre capture.
class FakeHost extends CaptureHost {
  final calls = <String>[];
  VoidCallback? stopCallback;
  SessionSummary? running;
  final finished = <SessionSummary>[];

  @override
  set onStopped(VoidCallback? callback) => stopCallback = callback;

  @override
  Future<void> start({required RateUnit unit, Duration? autoStop}) async {
    calls.add('start');
    running = summary(DateTime.now(), wifi: 0);
  }

  @override
  Future<SessionSummary?> current() async => running;

  @override
  Future<SessionSummary?> stop() async {
    calls.add('stop');
    final s = running;
    running = null;
    if (s != null) finished.add(s);
    return s;
  }

  @override
  Future<List<SessionSummary>> takeFinished() async {
    final out = [...finished];
    finished.clear();
    return out;
  }

  /// Le service s'arrête de lui-même (STOP dans la notification).
  void stopFromNotification() {
    finished.add(running!);
    running = null;
    stopCallback?.call();
  }
}

SessionSummary summary(DateTime start, {int wifi = 300000000, Duration duration = const Duration(minutes: 25)}) =>
    SessionSummary(
      startedAt: start,
      duration: duration,
      rxBytes: {Channel.wifi: wifi, Channel.mobile: 1000000},
      txBytes: {Channel.wifi: wifi ~/ 10},
    );

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late FluxSettings settings;
  late CaptureSession session;
  late FakeHost host;
  late HistoryStore history;

  Future<void> launch(WidgetTester tester, {void Function(FakeHost)? before}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings = FluxSettings.inMemory()
      ..keepScreenOn = false
      ..keepHistory = true
      ..autoStop = Duration.zero;
    session = CaptureSession(FakeTrafficSource());
    host = FakeHost();
    before?.call(host);
    history = HistoryStore.inMemory();
    await tester.pumpWidget(FluxApp(settings: settings, session: session, host: host, history: history));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('quitter l’écran de capture ne l’arrête pas', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);
    expect(host.calls, ['start']);

    await tester.tap(find.byTooltip("Retour à l'accueil (la capture continue)"));
    await settle(tester);
    expect(session.running, isTrue);
    expect(find.text('STOP'), findsOneWidget);

    await tester.tap(find.text('STOP'));
    await settle(tester);
    expect(host.calls, ['start', 'stop']);
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);
    expect(history.entries.length, 1, reason: 'un seul résumé, celui du service');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('l’app rouverte après avoir été fermée reprend la capture', (tester) async {
    final start = DateTime.now().subtract(const Duration(minutes: 25));
    await launch(tester, before: (h) => h.running = summary(start));
    await settle(tester);

    expect(session.running, isTrue);
    expect(session.elapsed, greaterThanOrEqualTo(const Duration(minutes: 25)));
    expect(session.rxTotal(Channel.wifi), greaterThanOrEqualTo(300000000), reason: 'repart des volumes du service');
    expect(find.text('STOP'), findsOneWidget);
    expect(find.textContaining('EN DIRECT · 25:'), findsOneWidget);
    expect(host.calls, isEmpty, reason: 'pas de nouvelle capture');

    await tester.tap(find.text('STOP'));
    await settle(tester);
    expect(history.entries.single.startedAt, start);
    expect(history.entries.single.duration, const Duration(minutes: 25));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('une capture terminée pendant l’absence arrive dans l’historique', (tester) async {
    final start = DateTime.now().subtract(const Duration(hours: 2));
    await launch(tester, before: (h) => h.finished.add(summary(start)));
    await settle(tester);
    expect(session.running, isFalse);
    expect(history.entries.single.startedAt, start);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('STOP depuis la notification affiche le résumé', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);

    host.stopFromNotification();
    await settle(tester);
    expect(session.running, isFalse);
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);
    expect(history.entries.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrêtée hors de l’app pendant qu’elle était en arrière-plan', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);

    // Le service s'arrête sans pouvoir prévenir l'app (callback perdu).
    host
      ..finished.add(host.running!)
      ..running = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(session.running, isFalse);
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);
    expect(history.entries.length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
