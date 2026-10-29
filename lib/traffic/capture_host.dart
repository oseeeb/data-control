import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ce que le système doit faire pendant une capture pour qu'elle continue
/// quand on quitte l'app : sur Android, un service au premier plan avec une
/// notification « En direct » et un bouton STOP.
abstract class CaptureHost {
  /// Appelé quand l'utilisateur appuie sur STOP dans la notification.
  set onStopRequested(VoidCallback? callback);

  Future<void> started(String title, String text);
  Future<void> update(String title, String text);
  Future<void> stopped();
}

/// Aucun service : pour les tests.
class NoopCaptureHost implements CaptureHost {
  const NoopCaptureHost();

  @override
  set onStopRequested(VoidCallback? callback) {}

  @override
  Future<void> started(String title, String text) async {}

  @override
  Future<void> update(String title, String text) async {}

  @override
  Future<void> stopped() async {}
}

/// Service natif, via le même canal que la lecture des compteurs.
class PlatformCaptureHost implements CaptureHost {
  PlatformCaptureHost() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') _onStop?.call();
    });
  }

  static const _channel = MethodChannel('com.oseeeb.flux/traffic');
  VoidCallback? _onStop;

  @override
  set onStopRequested(VoidCallback? callback) => _onStop = callback;

  @override
  Future<void> started(String title, String text) => _call('captureStarted', {'title': title, 'text': text});

  @override
  Future<void> update(String title, String text) => _call('captureUpdate', {'title': title, 'text': text});

  @override
  Future<void> stopped() => _call('captureStopped');

  Future<void> _call(String method, [Map<String, String>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Flux: $method a échoué (${e.message})');
    } on MissingPluginException {
      // Système sans service de capture : la capture reste au premier plan.
    }
  }
}
