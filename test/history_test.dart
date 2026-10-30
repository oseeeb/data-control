import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/apps/app_usage.dart';
import 'package:flux/history/history_store.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_session.dart';
import 'package:flux/traffic/channel.dart';
import 'package:flux/ui/format.dart';

import 'fake_source.dart';

SessionSummary summaryAt(DateTime t, {int wifi = 1000000}) => SessionSummary(
  startedAt: t,
  duration: const Duration(minutes: 2),
  rxBytes: {Channel.wifi: wifi, Channel.mobile: 200000},
  txBytes: {Channel.wifi: wifi ~/ 10},
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('HistoryStore', () {
    test('garde les captures triées, la plus récente d’abord', () {
      final store = HistoryStore.inMemory();
      final a = summaryAt(DateTime(2026, 10, 27, 9));
      final b = summaryAt(DateTime(2026, 10, 29, 14));
      final c = summaryAt(DateTime(2026, 10, 28, 18));
      store
        ..add(a)
        ..add(b)
        ..add(c);
      expect(store.entries, [b, c, a]);
      store.remove(c);
      expect(store.entries, [b, a]);
      store.clear();
      expect(store.isEmpty, isTrue);
    });

    test('limite le nombre de captures gardées', () {
      final store = HistoryStore.inMemory();
      final start = DateTime(2026, 1, 1);
      for (var i = 0; i < HistoryStore.maxEntries + 20; i++) {
        store.add(summaryAt(start.add(Duration(hours: i))));
      }
      expect(store.entries.length, HistoryStore.maxEntries);
      expect(store.entries.last.startedAt, start.add(const Duration(hours: 20)), reason: 'les plus anciennes partent');
    });

    test('un résumé se relit à l’identique, part par app comprise', () {
      final base = summaryAt(DateTime(2026, 10, 29, 14, 5));
      final s = SessionSummary(
        startedAt: base.startedAt,
        duration: base.duration,
        rxBytes: base.rxBytes,
        txBytes: base.txBytes,
        apps: const [
          AppUsage(uid: 7, name: 'Vidéos', packageName: 'com.exemple.videos', wifiForeground: 5, mobileBackground: 3),
        ],
        appsSince: base.startedAt,
      );
      final back = SessionSummary.fromJson(s.toJson());
      expect(back.apps.single.name, 'Vidéos');
      expect(back.apps.single.packageName, 'com.exemple.videos');
      expect(back.apps.single.total, 8);
      expect(back.appsSince, s.appsSince);
      expect(back.startedAt, s.startedAt);
      expect(back.duration, s.duration);
      expect(back.rxBytes, s.rxBytes);
      expect(back.txBytes, s.txBytes);
      expect(back.total, s.total);
    });
  });

  test('dates en français', () {
    final now = DateTime(2026, 10, 29, 20);
    expect(formatDay(DateTime(2026, 10, 29, 8), now: now), "Aujourd'hui");
    expect(formatDay(DateTime(2026, 10, 28, 23), now: now), 'Hier');
    expect(formatDay(DateTime(2026, 10, 26, 10), now: now), 'Lundi 26 oct.');
    expect(formatDay(DateTime(2025, 2, 3), now: now), 'Lundi 3 févr. 2025');
    expect(formatTime(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });

  group('écran', () {
    late FluxSettings settings;
    late HistoryStore history;

    Future<void> launch(WidgetTester tester, {bool keep = false}) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      settings = FluxSettings.inMemory()
        ..keepScreenOn = false
        ..keepHistory = keep;
      history = HistoryStore.inMemory();
      await tester.pumpWidget(
        FluxApp(
          settings: settings,
          // Chronomètre lié au temps simulé du test.
          session: CaptureSession(FakeTrafficSource(), stopwatch: clock.stopwatch),
          history: history,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> capture(WidgetTester tester) async {
      await tester.tap(find.text('GO'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.text('STOP'));
      await settle(tester);
    }

    testWidgets('désactivé par défaut : rien n’est gardé', (tester) async {
      await launch(tester);
      expect(find.text("Rien n'est enregistré"), findsOneWidget);
      await capture(tester);
      expect(find.text("Rien n'a été enregistré"), findsOneWidget);
      expect(history.isEmpty, isTrue);

      await tester.tap(find.text('Nouvelle capture'));
      await settle(tester);
      await tester.tap(find.byTooltip('Historique'));
      await settle(tester);
      expect(find.text("L'historique est désactivé"), findsOneWidget);
      await tester.tap(find.text('Activer l’historique'));
      await settle(tester);
      expect(settings.keepHistory, isTrue);
      expect(find.text('Aucune capture pour l’instant'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('activé : la capture apparaît, se rouvre et se supprime', (tester) async {
      await launch(tester, keep: true);
      expect(find.text("Rien n'est envoyé"), findsOneWidget);
      await capture(tester);
      expect(find.text('Résumé ajouté à l’historique'), findsOneWidget);
      expect(history.entries.length, 1);

      await tester.tap(find.text('Nouvelle capture'));
      await settle(tester);
      await tester.tap(find.byTooltip('Historique'));
      await settle(tester);
      expect(find.text('30 derniers jours'), findsOneWidget);
      expect(find.text('AUJOURD’HUI'.replaceAll('’', "'")), findsOneWidget);
      expect(find.text('1 capture · 4 s au total'), findsOneWidget);

      await tester.tap(find.textContaining('4 s').last);
      await settle(tester);
      expect(find.textContaining("AUJOURD'HUI ·"), findsOneWidget);
      await tester.tap(find.text('Supprimer cette capture'));
      await settle(tester);
      await tester.tap(find.text('Supprimer'));
      await settle(tester);
      expect(history.isEmpty, isTrue);
      expect(find.text('Aucune capture pour l’instant'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('désactiver l’historique efface les résumés après accord', (tester) async {
      await launch(tester, keep: true);
      history.add(summaryAt(DateTime.now()));
      await tester.tap(find.byTooltip('Réglages'));
      await settle(tester);
      final toggle = find.bySemanticsLabel("Garder l'historique");
      await tester.scrollUntilVisible(toggle, 200);
      await tester.tap(toggle);
      await settle(tester);
      expect(find.text("Désactiver l'historique ?"), findsOneWidget);
      await tester.tap(find.text('Désactiver et effacer'));
      await settle(tester);
      expect(settings.keepHistory, isFalse);
      expect(history.isEmpty, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
