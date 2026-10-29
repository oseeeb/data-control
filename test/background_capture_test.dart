import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_host.dart';
import 'package:flux/traffic/capture_session.dart';
import 'package:flux/traffic/channel.dart';

import 'fake_source.dart';

/// Enregistre ce que l'app demande au service natif.
class RecordingHost implements CaptureHost {
  final calls = <String>[];
  VoidCallback? stop;

  @override
  set onStopRequested(VoidCallback? callback) => stop = callback;

  @override
  Future<void> started(String title, String text) async => calls.add('started');

  @override
  Future<void> update(String title, String text) async => calls.add('update:$title');

  @override
  Future<void> stopped() async => calls.add('stopped');
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late FluxSettings settings;
  late CaptureSession session;
  late RecordingHost host;

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings = FluxSettings.inMemory()..keepScreenOn = false;
    session = CaptureSession(FakeTrafficSource());
    host = RecordingHost();
    await tester.pumpWidget(FluxApp(settings: settings, session: session, host: host));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('quitter l’écran de capture ne l’arrête pas', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(host.calls.first, 'started');

    await tester.tap(find.byTooltip("Retour à l'accueil (la capture continue)"));
    await settle(tester);

    expect(session.running, isTrue);
    expect(find.text('STOP'), findsOneWidget, reason: 'le bouton rond devient STOP');
    expect(find.textContaining('EN DIRECT'), findsOneWidget);
    expect(find.text('Voir la courbe en direct'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(session.running, isTrue);
    expect(host.calls.where((c) => c.startsWith('update:')), isNotEmpty);

    await tester.tap(find.text('STOP'));
    await settle(tester);
    expect(session.running, isFalse);
    expect(host.calls.last, 'stopped');
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la capture continue quand l’app passe en arrière-plan', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final before = session.elapsed;
    await tester.pump(const Duration(seconds: 5));
    expect(session.running, isTrue);
    expect(session.rxTotal(Channel.wifi), greaterThan(0));
    expect(session.elapsed, greaterThan(before));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('STOP'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('STOP depuis la notification affiche le résumé', (tester) async {
    await launch(tester);
    await tester.tap(find.text('GO'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));

    host.stop!();
    await settle(tester);

    expect(session.running, isFalse);
    expect(host.calls.last, 'stopped');
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
