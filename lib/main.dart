import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'traffic/capture_host.dart';
import 'traffic/capture_session.dart';
import 'traffic/traffic_source.dart';
import 'ui/format.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/summary_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await FluxSettings.load();
  runApp(FluxApp(settings: settings, session: CaptureSession(PlatformTrafficSource()), host: PlatformCaptureHost()));
}

class FluxApp extends StatefulWidget {
  const FluxApp({super.key, required this.settings, required this.session, this.host = const NoopCaptureHost()});

  final FluxSettings settings;
  final CaptureSession session;
  final CaptureHost host;

  @override
  State<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends State<FluxApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.host.onStopRequested = () {
      if (widget.session.running) widget.session.stop();
    };
    widget.session
      ..addListener(_onSession)
      ..watch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.host.onStopRequested = null;
    widget.session.removeListener(_onSession);
    if (widget.session.running) widget.host.stopped();
    widget.session.dispose();
    super.dispose();
  }

  /// La capture vit au niveau de l'app, pas d'un écran : on peut changer
  /// d'écran ou d'app, elle continue jusqu'à STOP (bouton, notification ou
  /// arrêt automatique). À l'arrêt, on montre le résumé, d'où qu'on soit.
  void _onSession() {
    final s = widget.session;
    if (s.running) {
      final title = 'En direct · ${formatClock(s.elapsed)}';
      final text =
          '↓ ${formatRate(s.totalRxPerSec, widget.settings.unit)} · '
          '↑ ${formatRate(s.totalTxPerSec, widget.settings.unit)} · '
          '${formatVolume(s.totalBytes)} depuis GO';
      if (!_wasRunning) {
        _wasRunning = true;
        widget.host.started(title, text);
        if (widget.settings.keepScreenOn) WakelockPlus.enable().catchError((Object _) {});
      } else {
        widget.host.update(title, text);
      }
      return;
    }
    if (!_wasRunning) return;
    _wasRunning = false;
    widget.host.stopped();
    WakelockPlus.disable().catchError((Object _) {});
    final summary = s.takeSummary();
    final navigator = _navigator.currentState;
    if (summary == null || navigator == null) return;
    navigator
      ..popUntil((route) => route.isFirst)
      ..push(fadeRoute(SummaryScreen(summary: summary)));
  }

  /// Hors capture, inutile de lire les compteurs quand l'app n'est pas visible.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.watch();
    } else if (state == AppLifecycleState.paused) {
      widget.session.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FluxScope(
      settings: widget.settings,
      session: widget.session,
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
