import 'package:flutter/widgets.dart';

import '../apps/app_usage.dart';
import '../history/history_store.dart';
import '../traffic/capture_host.dart';
import '../traffic/capture_session.dart';
import 'settings.dart';

/// Donne accès aux réglages, à la session et à l'historique depuis
/// n'importe quel écran.
class FluxScope extends InheritedWidget {
  const FluxScope({
    super.key,
    required this.settings,
    required this.session,
    required this.history,
    required this.host,
    required this.apps,
    required super.child,
  });

  final FluxSettings settings;
  final CaptureSession session;
  final HistoryStore history;
  final CaptureHost host;
  final AppUsageSource apps;

  static FluxScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FluxScope>();
    assert(scope != null, 'FluxScope manquant au-dessus de ce widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(FluxScope oldWidget) =>
      settings != oldWidget.settings ||
      session != oldWidget.session ||
      history != oldWidget.history ||
      host != oldWidget.host ||
      apps != oldWidget.apps;
}
