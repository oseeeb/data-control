import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_session.dart';

import 'fake_source.dart';

void main() {
  for (final size in const [Size(390, 844), Size(360, 640)]) {
    testWidgets('GO → capture en direct → STOP → résumé → nouvelle capture (${size.width.toInt()} px)', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final settings = FluxSettings.inMemory()..keepScreenOn = false;
      final session = CaptureSession(FakeTrafficSource());
      await tester.pumpWidget(FluxApp(settings: settings, session: session));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('GO'), findsOneWidget);
      expect(find.text('PRÊT À CAPTER'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Non branché'), findsOneWidget);

      await tester.tap(find.text('GO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('STOP'), findsOneWidget);
      expect(find.textContaining('En direct'), findsOneWidget);
      expect(find.text('2,0 Mo/s'), findsOneWidget, reason: 'débit Wi-Fi simulé en unité auto');

      await tester.tap(find.text('STOP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('SESSION TERMINÉE'), findsOneWidget);
      expect(find.text("Rien n'a été enregistré"), findsOneWidget);
      expect(find.text('Non utilisé'), findsNWidgets(2), reason: 'USB et Bluetooth');

      await tester.tap(find.text('Nouvelle capture'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('GO'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('les réglages changent le thème et masquent un canal', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settings = FluxSettings.inMemory();
    await tester.pumpWidget(FluxApp(settings: settings, session: CaptureSession(FakeTrafficSource())));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Réglages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Réglages'), findsOneWidget);

    await tester.tap(find.text('Clair'));
    await tester.pump();
    expect(settings.theme, ThemeMode.light);

    await tester.tap(find.bySemanticsLabel('Afficher USB'));
    await tester.pump();
    expect(settings.isVisible(settings.visibleChannels.first), isTrue);
    expect(settings.visibleChannels.map((c) => c.label), isNot(contains('USB')));

    await tester.pumpWidget(const SizedBox());
  });
}
