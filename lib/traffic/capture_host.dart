import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/settings.dart';
import 'capture_session.dart';
import 'channel.dart';
import 'rate_meter.dart';
import 'traffic_source.dart';

/// Ce qui garde une capture en vie quand Flux n'est plus à l'écran, ou même
/// quand le système l'a fermé.
///
/// - Android : un service natif mesure lui-même, sauvegarde son état et
///   affiche la notification « En direct » ([AndroidCaptureHost]).
/// - iPhone : pas de mesure en arrière-plan possible, mais le point de départ
///   est sauvegardé ; au retour, la capture reprend avec des volumes justes
///   ([CheckpointCaptureHost]).
abstract class CaptureHost {
  /// Prévient l'app quand la capture s'arrête hors d'elle (notification, arrêt automatique).
  set onStopped(VoidCallback? callback);

  Future<void> start({required RateUnit unit, Duration? autoStop});

  /// La capture en cours (début, durée, volumes), ou `null`.
  Future<SessionSummary?> current();

  /// Termine la capture et renvoie son résumé (`null` s'il n'y en avait pas).
  Future<SessionSummary?> stop();

  /// Les captures terminées pas encore reprises par l'app, y compris celle
  /// que [stop] vient de terminer.
  Future<List<SessionSummary>> takeFinished();

  /// `true` si l'économie de batterie du téléphone peut fermer Flux.
  Future<bool> backgroundRestricted() async => false;

  Future<void> openBatterySettings() async {}
}

/// Aucune sauvegarde : pour les tests.
class NoopCaptureHost extends CaptureHost {
  NoopCaptureHost();

  @override
  set onStopped(VoidCallback? callback) {}

  @override
  Future<void> start({required RateUnit unit, Duration? autoStop}) async {}

  @override
  Future<SessionSummary?> current() async => null;

  @override
  Future<SessionSummary?> stop() async => null;

  @override
  Future<List<SessionSummary>> takeFinished() async => const [];
}

SessionSummary? _summaryFromMap(Object? raw) {
  if (raw is! Map) return null;
  Map<Channel, int> bytes(Object? m) => {
    for (final e in ((m as Map?) ?? const {}).entries)
      if (Channel.fromKey(e.key as String) != null && e.value is int) Channel.fromKey(e.key as String)!: e.value as int,
  };
  return SessionSummary(
    startedAt: DateTime.fromMillisecondsSinceEpoch(raw['startedAtMs'] as int),
    duration: Duration(seconds: raw['durationSec'] as int),
    rxBytes: bytes(raw['rx']),
    txBytes: bytes(raw['tx']),
  );
}

/// Android : le service natif `CaptureService` fait la mesure.
class AndroidCaptureHost extends CaptureHost {
  AndroidCaptureHost() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'captureStopped') _onStopped?.call();
    });
  }

  static const _channel = MethodChannel('com.oseeeb.flux/traffic');
  VoidCallback? _onStopped;

  @override
  set onStopped(VoidCallback? callback) => _onStopped = callback;

  @override
  Future<void> start({required RateUnit unit, Duration? autoStop}) =>
      _call('captureStart', {'unit': unit.name, 'autoStopSec': autoStop?.inSeconds ?? 0});

  @override
  Future<SessionSummary?> current() async => _summaryFromMap(await _call('captureState'));

  @override
  Future<SessionSummary?> stop() async => _summaryFromMap(await _call('captureStop'));

  @override
  Future<List<SessionSummary>> takeFinished() async {
    final raw = await _call('takeFinished');
    return [for (final m in (raw as List?) ?? const []) ?_summaryFromMap(m)];
  }

  @override
  Future<bool> backgroundRestricted() async => (await _call('backgroundRestricted')) == true;

  @override
  Future<void> openBatterySettings() => _call('openBatterySettings');

  Future<Object?> _call(String method, [Map<String, Object>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Flux: $method a échoué (${e.message})');
    } on MissingPluginException {
      debugPrint('Flux: $method indisponible');
    }
    return null;
  }
}

/// Sauvegarde du point de départ d'une capture (iPhone). Les compteurs du
/// système étant cumulés, « maintenant − départ » donne les volumes, même si
/// l'app a été suspendue ou fermée entre-temps.
///
/// Limites : un redémarrage du téléphone remet les compteurs à zéro (la
/// capture est alors close sur le dernier état connu), et les compteurs
/// 32 bits d'iOS bouclent tous les 4 Go (un seul bouclage est rattrapé).
class CheckpointCaptureHost extends CaptureHost {
  CheckpointCaptureHost(this._source, {Future<SharedPreferences> Function()? prefs, DateTime Function()? now})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      _now = now ?? DateTime.now;

  static const _key = 'captureCheckpoint';

  final TrafficSource _source;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;

  @override
  set onStopped(VoidCallback? callback) {}

  @override
  Future<void> start({required RateUnit unit, Duration? autoStop}) async {
    final snapshot = await _source.read();
    final prefs = await _prefs();
    await prefs.setString(
      _key,
      jsonEncode({
        'startedAtMs': _now().millisecondsSinceEpoch,
        'autoStopSec': autoStop?.inSeconds ?? 0,
        'counterBits': snapshot.counterBits,
        'base': {
          for (final c in Channel.values)
            if (snapshot[c].measurable) c.key: [snapshot[c].rxBytes, snapshot[c].txBytes],
        },
        'last': <String, Object>{},
        'lastAtMs': _now().millisecondsSinceEpoch,
      }),
    );
  }

  Future<Map<String, Object?>?> _load() async {
    final raw = (await _prefs()).getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  /// Volumes depuis le départ. Si les compteurs sont repartis de zéro
  /// (redémarrage), on garde le dernier état connu.
  Future<SessionSummary?> _measure(Map<String, Object?> cp) async {
    final snapshot = await _source.read();
    final base = (cp['base'] as Map).cast<String, Object?>();
    final last = (cp['last'] as Map).cast<String, Object?>();
    final bits = cp['counterBits'] as int?;
    final rx = <Channel, int>{};
    final tx = <Channel, int>{};
    var reset = false;
    for (final c in Channel.values) {
      final b = base[c.key] as List?;
      final r = snapshot[c];
      if (b == null || !r.measurable) continue;
      final dRx = _delta(b[0] as int, r.rxBytes!, bits);
      final dTx = _delta(b[1] as int, r.txBytes!, bits);
      if (dRx == null || dTx == null) {
        reset = true;
        break;
      }
      rx[c] = dRx;
      tx[c] = dTx;
    }
    final startedAt = DateTime.fromMillisecondsSinceEpoch(cp['startedAtMs'] as int);
    if (reset) {
      final lastRx = (last['rx'] as Map?)?.cast<String, int>() ?? const {};
      final lastTx = (last['tx'] as Map?)?.cast<String, int>() ?? const {};
      return SessionSummary(
        startedAt: startedAt,
        duration: DateTime.fromMillisecondsSinceEpoch(cp['lastAtMs'] as int).difference(startedAt),
        rxBytes: {for (final e in lastRx.entries) Channel.fromKey(e.key)!: e.value},
        txBytes: {for (final e in lastTx.entries) Channel.fromKey(e.key)!: e.value},
      );
    }
    var duration = _now().difference(startedAt);
    final autoStop = Duration(seconds: cp['autoStopSec'] as int? ?? 0);
    if (autoStop > Duration.zero && duration > autoStop) duration = autoStop;
    // Dernier état connu, pour le cas d'un redémarrage plus tard.
    cp['last'] = {
      'rx': {for (final e in rx.entries) e.key.key: e.value},
      'tx': {for (final e in tx.entries) e.key.key: e.value},
    };
    cp['lastAtMs'] = _now().millisecondsSinceEpoch;
    await (await _prefs()).setString(_key, jsonEncode(cp));
    return SessionSummary(startedAt: startedAt, duration: duration, rxBytes: rx, txBytes: tx);
  }

  /// `null` si le compteur est reparti de zéro sans bouclage possible.
  static int? _delta(int base, int now, int? bits) {
    if (now >= base) return now - base;
    final d = counterDelta(base, now, wrapBits: bits);
    return d > 0 ? d : null;
  }

  @override
  Future<SessionSummary?> current() async {
    final cp = await _load();
    return cp == null ? null : _measure(cp);
  }

  @override
  Future<SessionSummary?> stop() async {
    final cp = await _load();
    if (cp == null) return null;
    final summary = await _measure(cp);
    await (await _prefs()).remove(_key);
    _finished.add(summary!);
    return summary;
  }

  final _finished = <SessionSummary>[];

  @override
  Future<List<SessionSummary>> takeFinished() async {
    final out = [..._finished];
    _finished.clear();
    return out;
  }
}

/// L'hôte qui convient au téléphone.
CaptureHost platformCaptureHost(TrafficSource source) =>
    Platform.isAndroid ? AndroidCaptureHost() : CheckpointCaptureHost(source);
