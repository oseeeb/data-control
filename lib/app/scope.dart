import 'package:flutter/widgets.dart';

import '../traffic/capture_session.dart';
import 'settings.dart';

/// Donne accès aux réglages et à la session depuis n'importe quel écran.
class FluxScope extends InheritedWidget {
  const FluxScope({super.key, required this.settings, required this.session, required super.child});

  final FluxSettings settings;
  final CaptureSession session;

  static FluxScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FluxScope>();
    assert(scope != null, 'FluxScope manquant au-dessus de ce widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(FluxScope oldWidget) => settings != oldWidget.settings || session != oldWidget.session;
}
