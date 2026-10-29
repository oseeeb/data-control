import 'package:flutter/services.dart';

import 'snapshot.dart';

/// D'où viennent les lectures de compteurs. Abstrait pour pouvoir tester
/// la session sans téléphone.
abstract class TrafficSource {
  Future<TrafficSnapshot> read();
}

/// Lit les compteurs via le code natif (Kotlin sur Android, Swift sur iOS).
class PlatformTrafficSource implements TrafficSource {
  static const _channel = MethodChannel('com.oseeeb.flux/traffic');

  @override
  Future<TrafficSnapshot> read() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('snapshot');
    return TrafficSnapshot.fromMap(map ?? const {'timestampMs': 0});
  }

  /// Ouvre la page de l'app dans les réglages du téléphone.
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // Rien à faire : la page n'existe pas sur ce système.
    }
  }
}
