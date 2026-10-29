import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'apps/app_usage.dart';
import 'history/history_store.dart';
import 'traffic/capture_host.dart';
import 'traffic/capture_session.dart';
import 'traffic/traffic_source.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/summary_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await FluxSettings.load();
  final history = await HistoryStore.load();
  final source = PlatformTrafficSource();
  runApp(
    FluxApp(
      settings: settings,
      session: CaptureSession(source),
      history: history,
      host: platformCaptureHost(source),
      apps: PlatformAppUsageSource(),
    ),
  );
}

class FluxApp extends StatefulWidget {
  const FluxApp({super.key, required this.settings, required this.session, this.history, this.host, this.apps});

  final FluxSettings settings;
  final CaptureSession session;

  /// Sans historique fourni (tests), un historique en mémoire.
  final HistoryStore? history;

  /// Sans hôte fourni (tests), aucune sauvegarde de la capture.
  final CaptureHost? host;

  /// Consommation par app (analyse) ; sans source fournie, celle du téléphone.
  final AppUsageSource? apps;

  @override
  State<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends State<FluxApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late final HistoryStore _history = widget.history ?? HistoryStore.inMemory();
  late final CaptureHost _host = widget.host ?? NoopCaptureHost();
  late final AppUsageSource _apps = widget.apps ?? PlatformAppUsageSource();

  /// La session tournait au dernier changement (pour repérer GO et STOP).
  bool _wasRunning = false;
  bool _finishing = false;

  CaptureSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _host.onStopped = () {
      if (_session.running) _session.stop();
    };
    _session
      ..addListener(_onSession)
      ..watch();
    _restore();
  }

  @override
  void dispose() {
    // La capture n'est pas arrêtée ici : elle continue sans l'app (Android)
    // ou reprendra à la prochaine ouverture (iPhone).
    WidgetsBinding.instance.removeObserver(this);
    _host.onStopped = null;
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  Duration? get _autoStop {
    final limit = widget.settings.autoStop;
    return limit == Duration.zero ? null : limit;
  }

  /// À l'ouverture et au retour dans l'app : range les captures terminées
  /// pendant l'absence et reprend celle qui est en cours.
  Future<void> _restore() async {
    _store(await _host.takeFinished());
    final current = await _host.current();
    if (!mounted) return;
    if (current == null) {
      // Capture arrêtée hors de l'app (notification, arrêt automatique) alors
      // que la session la croyait encore en cours.
      if (_session.running && !_finishing) _session.stop();
      return;
    }
    if (_session.running) {
      _session.syncTotals(current);
    } else {
      _wasRunning = true;
      _session.resume(current, autoStop: _autoStop);
      if (widget.settings.keepScreenOn) WakelockPlus.enable().catchError((Object _) {});
    }
  }

  /// La capture vit au niveau de l'app, pas d'un écran : on peut changer
  /// d'écran ou d'app, elle continue jusqu'à STOP (bouton, notification ou
  /// arrêt automatique). À l'arrêt, on montre le résumé, d'où qu'on soit.
  void _onSession() {
    if (_session.running) {
      if (_wasRunning) return;
      _wasRunning = true;
      _host.start(unit: widget.settings.unit, autoStop: _autoStop);
      if (widget.settings.keepScreenOn) WakelockPlus.enable().catchError((Object _) {});
      return;
    }
    if (!_wasRunning) return;
    _wasRunning = false;
    _finish();
  }

  Future<void> _finish() async {
    _finishing = true;
    WakelockPlus.disable().catchError((Object _) {});
    final local = _session.takeSummary();
    // Le résumé de l'hôte fait foi : il a aussi compté le temps passé hors de l'app.
    final native = await _host.stop();
    final finished = await _host.takeFinished();
    _finishing = false;
    _store([...finished, if (native == null && finished.isEmpty && local != null) local]);
    final summary = native ?? (finished.isNotEmpty ? finished.last : local);
    final navigator = _navigator.currentState;
    if (summary == null || navigator == null || !mounted) return;
    navigator
      ..popUntil((route) => route.isFirst)
      ..push(fadeRoute(SummaryScreen(summary: summary)));
  }

  /// Seulement si l'utilisateur a activé l'historique, et pas pour un GO/STOP accidentel.
  void _store(List<SessionSummary> summaries) {
    if (!widget.settings.keepHistory) return;
    for (final s in summaries) {
      if (s.duration >= const Duration(seconds: 3)) _history.add(s);
    }
  }

  /// Hors capture, inutile de lire les compteurs quand l'app n'est pas visible.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _session.watch();
      _restore();
    } else if (state == AppLifecycleState.paused) {
      _session.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluxScope(
      settings: widget.settings,
      session: _session,
      history: _history,
      host: _host,
      apps: _apps,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          title: 'Flux',
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(FluxPalette.light, Brightness.light),
          darkTheme: buildTheme(FluxPalette.dark, Brightness.dark),
          themeMode: widget.settings.theme,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
