import 'package:flutter/material.dart';

import 'app/scope.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'traffic/capture_session.dart';
import 'traffic/traffic_source.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await FluxSettings.load();
  runApp(FluxApp(settings: settings, session: CaptureSession(PlatformTrafficSource())));
}

class FluxApp extends StatefulWidget {
  const FluxApp({super.key, required this.settings, required this.session});

  final FluxSettings settings;
  final CaptureSession session;

  @override
  State<FluxApp> createState() => _FluxAppState();
}

class _FluxAppState extends State<FluxApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.watch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.dispose();
    super.dispose();
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
