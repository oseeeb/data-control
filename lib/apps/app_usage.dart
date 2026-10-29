import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Consommation d'une app sur une période, telle que le téléphone la compte.
class AppUsage {
  const AppUsage({
    required this.uid,
    required this.name,
    this.packageName,
    this.icon,
    this.system = false,
    this.wifiForeground = 0,
    this.wifiBackground = 0,
    this.mobileForeground = 0,
    this.mobileBackground = 0,
  });

  final int uid;
  final String name;
  final String? packageName;
  final Uint8List? icon;

  /// Service du système plutôt qu'une app que l'on a installée.
  final bool system;

  /// Octets reçus + envoyés, par réseau et par état (à l'écran ou en arrière-plan).
  final int wifiForeground;
  final int wifiBackground;
  final int mobileForeground;
  final int mobileBackground;

  int get background => wifiBackground + mobileBackground;
  int get foreground => wifiForeground + mobileForeground;
  int get total => background + foreground;

  factory AppUsage.fromMap(Map<Object?, Object?> m) {
    int n(String k) => (m[k] as int?) ?? 0;
    return AppUsage(
      uid: m['uid'] as int,
      name: m['name'] as String,
      packageName: m['package'] as String?,
      icon: m['icon'] as Uint8List?,
      system: m['system'] == true,
      wifiForeground: n('wifiFgRx') + n('wifiFgTx'),
      wifiBackground: n('wifiBgRx') + n('wifiBgTx'),
      mobileForeground: n('mobileFgRx') + n('mobileFgTx'),
      mobileBackground: n('mobileBgRx') + n('mobileBgTx'),
    );
  }
}

/// Où lire la consommation par app.
abstract class AppUsageSource {
  /// Le système permet-il cette analyse ? (Android oui, iPhone non.)
  bool get supported;

  /// L'utilisateur a-t-il donné l'accès « Données d'utilisation » ?
  Future<bool> hasAccess();

  Future<void> requestAccess();

  Future<List<AppUsage>> query(DateTime start, DateTime end);

  /// Ouvre la page de l'app dans les réglages (pour limiter ses données en arrière-plan).
  Future<void> openAppDetails(String packageName);
}

class PlatformAppUsageSource implements AppUsageSource {
  static const _channel = MethodChannel('com.oseeeb.flux/traffic');

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<bool> hasAccess() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('appUsageAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> requestAccess() => _channel.invokeMethod<void>('openUsageAccessSettings');

  @override
  Future<List<AppUsage>> query(DateTime start, DateTime end) async {
    final raw = await _channel.invokeListMethod<Object?>('appUsage', {
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
    });
    return [for (final m in raw ?? const []) AppUsage.fromMap(m as Map<Object?, Object?>)];
  }

  @override
  Future<void> openAppDetails(String packageName) =>
      _channel.invokeMethod<void>('openAppDetails', {'package': packageName});
}
