import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/apps/app_usage.dart';
import 'package:flux/main.dart';
import 'package:flux/traffic/capture_session.dart';

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
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeApps apps;

  Future<void> openApps(WidgetTester tester, FakeApps source) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    apps = source;
    await tester.pumpWidget(
      FluxApp(
        settings: FluxSettings.inMemory()..keepScreenOn = false,
        session: CaptureSession(FakeTrafficSource()),
        apps: apps,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final entry = find.text('Apps en arrière-plan');
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

  testWidgets('classe les apps par consommation en arrière-plan', (tester) async {
    await openApps(tester, FakeApps());
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

    await tester.tap(find.text('7 jours'));
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
