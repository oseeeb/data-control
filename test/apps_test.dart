import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/apps/app_usage.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_host.dart';
import 'package:flux/traffic/capture_session.dart';
import 'package:flux/traffic/channel.dart';

import 'fake_source.dart';

class FakeApps implements AppUsageSource {
  FakeApps({this.supported = true, this.access = true});

  @override
  final bool supported;
  bool access;
  int accessRequests = 0;
  final queries = <Duration>[];
  final opened = <String>[];

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<void> requestAccess() async => accessRequests++;

  @override
  Future<List<AppUsage>> query(DateTime start, DateTime end) async {
    queries.add(end.difference(start));
    return const [
      AppUsage(
        uid: 1,
        name: 'Vidéos',
        packageName: 'com.exemple.videos',
        wifiBackground: 900000000,
        wifiForeground: 2000000000,
      ),
      AppUsage(
        uid: 2,
        name: 'Messagerie',
        packageName: 'com.exemple.chat',
        mobileBackground: 120000000,
        wifiBackground: 30000000,
      ),
      AppUsage(uid: 3, name: 'Navigateur', packageName: 'com.exemple.web', wifiForeground: 500000000),
      AppUsage(uid: 1000, name: 'Système Android', system: true, wifiBackground: 400000000),
    ];
  }

  @override
  Future<void> openAppDetails(String packageName) async => opened.add(packageName);

  @override
  Future<Map<int, Uint8List>> icons(List<int> uids) async => const {};
}

/// Hôte qui connaît la part de chaque app pendant la capture.
class AppsHost extends CaptureHost {
  SessionSummary? running;
  final finished = <SessionSummary>[];

  static const breakdown = [
    AppUsage(
      uid: 1,
      name: 'Vidéos',
      packageName: 'com.exemple.videos',
      wifiForeground: 6000000000,
      wifiBackground: 100000000,
    ),
    AppUsage(uid: 2, name: 'Messagerie', packageName: 'com.exemple.chat', mobileBackground: 1500000000),
    AppUsage(uid: 1000, name: 'Système Android', system: true, wifiBackground: 400000000),
  ];

  @override
  set onStopped(VoidCallback? callback) {}

  @override
  Future<void> start({required RateUnit unit, Duration? autoStop}) async {
    running = SessionSummary(startedAt: DateTime.now(), duration: Duration.zero, rxBytes: const {}, txBytes: const {});
  }

  @override
  Future<SessionSummary?> current() async => running;

  @override
  Future<AppBreakdown?> captureApps() async =>
      running == null ? null : AppBreakdown(apps: breakdown, since: running!.startedAt);

  @override
  Future<SessionSummary?> stop() async {
    final r = running;
    running = null;
    if (r == null) return null;
    final s = SessionSummary(
      startedAt: r.startedAt,
      duration: const Duration(minutes: 130),
      rxBytes: const {Channel.wifi: 9000000000, Channel.mobile: 1000000000},
      txBytes: const {Channel.wifi: 500000000},
      apps: breakdown,
      appsSince: r.startedAt,
    );
    finished.add(s);
    return s;
  }

  @override
  Future<List<SessionSummary>> takeFinished() async {
    final out = [...finished];
    finished.clear();
    return out;
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeApps apps;

  Future<void> openApps(WidgetTester tester, FakeApps source, {CaptureHost? host, bool go = false}) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    apps = source;
    await tester.pumpWidget(
      FluxApp(
        settings: FluxSettings.inMemory()
          ..keepScreenOn = false
          ..autoStop = Duration.zero,
        session: CaptureSession(FakeTrafficSource()),
        apps: apps,
        host: host,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    if (go) {
      await tester.tap(find.text('GO'));
      await settle(tester);
      await tester.tap(find.byTooltip("Retour à l'accueil (la capture continue)"));
      await settle(tester);
    }
    final entry = find.text('Quelles apps consomment ?');
    await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(entry);
    await settle(tester);
  }

  test('volumes par app', () {
    const a = AppUsage(uid: 1, name: 'A', wifiBackground: 10, mobileBackground: 5, wifiForeground: 100);
    expect(a.background, 15);
    expect(a.foreground, 100);
    expect(a.total, 115);
    final m = AppUsage.fromMap({'uid': 7, 'name': 'B', 'wifiBgRx': 3, 'wifiBgTx': 1, 'mobileFgRx': 8});
    expect(m.wifiBackground, 4);
    expect(m.mobileForeground, 8);
  });

  testWidgets('sans capture : invite à appuyer sur GO', (tester) async {
    await openApps(tester, FakeApps());
    expect(find.text('Aucune capture en cours'), findsOneWidget);
    expect(apps.queries, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pendant la capture : part de chaque app, puis dans le résumé', (tester) async {
    final host = AppsHost();
    await openApps(tester, FakeApps(), host: host, go: true);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Toutes les apps · Depuis GO'), findsOneWidget);
    expect(find.text('Vidéos'), findsOneWidget);
    expect(find.text('Messagerie'), findsOneWidget);
    expect(find.text('Système Android'), findsNothing);
    expect(find.text('80 %'), findsOneWidget, reason: '6,1 Go sur 7,6 Go attribués aux apps visibles');
    expect(find.text('20 %'), findsOneWidget);
    expect(find.textContaining('100 % en mobile'), findsOneWidget);

    await tester.tap(find.text('Arrière-plan'));
    await settle(tester);
    expect(
      tester.getTopLeft(find.text('Messagerie')).dy,
      lessThan(tester.getTopLeft(find.text('Vidéos')).dy),
      reason: 'en arrière-plan, Messagerie passe devant',
    );

    await tester.tap(find.byTooltip('Retour'));
    await settle(tester);
    await tester.tap(find.text('STOP'));
    await settle(tester);
    expect(find.text('SESSION TERMINÉE'), findsOneWidget);
    expect(find.text('Par app'), findsOneWidget);
    expect(find.text('Vidéos'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Voir toutes les apps'), 200);
    await tester.tap(find.text('Voir toutes les apps'));
    await settle(tester);
    expect(find.text('Consommation par app'), findsOneWidget);
    expect(find.textContaining('Depuis GO'), findsOneWidget);
    expect(
      find.textContaining('ne sont attribués à aucune app'),
      findsOneWidget,
      reason: '10,5 Go mesurés, 8 Go attribués',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('historique du téléphone : classe les apps par arrière-plan', (tester) async {
    await openApps(tester, FakeApps());
    await tester.tap(find.text('24 h'));
    await settle(tester);
    expect(apps.queries.single, const Duration(hours: 24));
    expect(find.text('En arrière-plan · 24 h'), findsOneWidget);
    expect(find.text('Vidéos'), findsOneWidget);
    expect(find.text('Messagerie'), findsOneWidget);
    expect(find.text('Navigateur'), findsNothing, reason: 'rien en arrière-plan');
    expect(find.text('Système Android'), findsNothing, reason: 'système masqué par défaut');
    expect(find.text('1 service du système masqué.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Vidéos')).dy,
      lessThan(tester.getTopLeft(find.text('Messagerie')).dy),
      reason: 'la plus gourmande en premier',
    );
    expect(find.textContaining('sur le réseau mobile'), findsOneWidget, reason: 'Messagerie surtout en mobile');

    await tester.tap(find.text('7 j'));
    await settle(tester);
    expect(apps.queries.last, const Duration(days: 7));

    await tester.tap(find.text('Vidéos'));
    await settle(tester);
    expect(find.text('com.exemple.videos'), findsOneWidget);
    await tester.tap(find.text('Ouvrir la page de l’app'));
    expect(apps.opened, ['com.exemple.videos']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demande l’accès « Données d’utilisation »', (tester) async {
    await openApps(tester, FakeApps(access: false));
    await tester.tap(find.text('24 h'));
    await settle(tester);
    expect(find.text('Un accès est nécessaire'), findsOneWidget);
    await tester.tap(find.text('Autoriser l’accès'));
    expect(apps.accessRequests, 1);

    apps.access = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.text('Vidéos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explique que l’iPhone ne le permet pas', (tester) async {
    await openApps(tester, FakeApps(supported: false));
    expect(find.text('Pas disponible sur iPhone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
