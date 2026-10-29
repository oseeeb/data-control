import 'dart:async';

import 'package:flutter/foundation.dart';

import 'channel.dart';
import 'rate_meter.dart';
import 'snapshot.dart';
import 'traffic_source.dart';

/// Ce qui reste d'une capture une fois arrêtée : sa date, sa durée et les
/// volumes par canal. Jamais le contenu du trafic. Vit en mémoire le temps de
/// l'écran de fin, et dans l'historique seulement si l'utilisateur l'a activé.
class SessionSummary {
  const SessionSummary({required this.startedAt, required this.duration, required this.rxBytes, required this.txBytes});

  final DateTime startedAt;
  final Duration duration;
  final Map<Channel, int> rxBytes;
  final Map<Channel, int> txBytes;

  int get totalRx => rxBytes.values.fold(0, (a, b) => a + b);
  int get totalTx => txBytes.values.fold(0, (a, b) => a + b);
  int get total => totalRx + totalTx;
  int volumeOf(Channel c) => (rxBytes[c] ?? 0) + (txBytes[c] ?? 0);

  Map<String, Object> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationSec': duration.inSeconds,
    'rx': {for (final e in rxBytes.entries) e.key.key: e.value},
    'tx': {for (final e in txBytes.entries) e.key.key: e.value},
  };

  static SessionSummary fromJson(Map<String, Object?> json) {
    Map<Channel, int> bytes(Object? raw) => {
      for (final e in ((raw as Map?) ?? const {}).entries)
        if (Channel.fromKey(e.key as String) != null && e.value is int)
          Channel.fromKey(e.key as String)!: e.value as int,
    };
    return SessionSummary(
      startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
      duration: Duration(seconds: json['durationSec'] as int),
      rxBytes: bytes(json['rx']),
      txBytes: bytes(json['tx']),
    );
  }
}

/// Surveille les canaux et, après GO, mesure les débits en direct.
///
/// La session n'écrit rien sur le disque : la courbe se limite aux
/// [historyLength] dernières secondes et disparaît à l'arrêt. Seul le
/// résumé peut être gardé, par [HistoryStore], si l'utilisateur l'a choisi.
class CaptureSession extends ChangeNotifier {
  CaptureSession(this._source, {Stopwatch Function()? stopwatch, DateTime Function()? now})
    : _newStopwatch = stopwatch ?? Stopwatch.new,
      _now = now ?? DateTime.now;

  static const historyLength = 60;
  static const _idleInterval = Duration(seconds: 2);
  static const _liveInterval = Duration(seconds: 1);

  final TrafficSource _source;
  final Stopwatch Function() _newStopwatch;
  final DateTime Function() _now;
  DateTime? _startedAt;

  Timer? _timer;
  bool _reading = false;
  bool _disposed = false;

  TrafficSnapshot? _latest;
  TrafficSnapshot? _previous;

  bool _running = false;
  Stopwatch? _clock;
  Duration? _autoStop;
  SessionSummary? _lastSummary;

  Map<Channel, ChannelRate> _rates = {};
  final Map<Channel, List<double>> _rxHistory = {};
  final Map<Channel, List<double>> _txHistory = {};
  final Map<Channel, int> _rxTotal = {};
  final Map<Channel, int> _txTotal = {};
  final Map<Channel, double> _rxPeak = {};

  bool get running => _running;
  Duration get elapsed => _clock?.elapsed ?? Duration.zero;
  TrafficSnapshot? get latest => _latest;

  ChannelReading reading(Channel c) => _latest?[c] ?? ChannelReading.unavailable;
  ChannelRate rate(Channel c) => _rates[c] ?? ChannelRate.zero;
  List<double> rxHistory(Channel c) => List.unmodifiable(_rxHistory[c] ?? const <double>[]);
  List<double> txHistory(Channel c) => List.unmodifiable(_txHistory[c] ?? const <double>[]);
  int rxTotal(Channel c) => _rxTotal[c] ?? 0;
  int txTotal(Channel c) => _txTotal[c] ?? 0;
  double rxPeak(Channel c) => _rxPeak[c] ?? 0;

  double get totalRxPerSec => _rates.values.fold(0.0, (a, r) => a + r.rxPerSec);
  double get totalTxPerSec => _rates.values.fold(0.0, (a, r) => a + r.txPerSec);
  int get totalBytes => _rxTotal.values.fold(0, (a, b) => a + b) + _txTotal.values.fold(0, (a, b) => a + b);

  /// Résumé de la capture qui vient de s'arrêter (arrêt automatique compris).
  /// Consommé une seule fois par l'écran de fin.
  SessionSummary? takeSummary() {
    final s = _lastSummary;
    _lastSummary = null;
    return s;
  }

  /// Lecture des statuts de connexion, à faible fréquence, hors capture.
  void watch() {
    if (_timer != null) return;
    _schedule(_idleInterval);
    _tick();
  }

  /// Met en pause la lecture quand l'app passe en arrière-plan
  /// (sauf pendant une capture).
  void pause() {
    if (_running) return;
    _timer?.cancel();
    _timer = null;
  }

  void start({Duration? autoStop}) {
    if (_running) return;
    _running = true;
    _autoStop = autoStop;
    _clock = _newStopwatch()..start();
    _startedAt = _now();
    _previous = _latest;
    _lastSummary = null;
    _rates = {};
    _rxHistory.clear();
    _txHistory.clear();
    _rxTotal.clear();
    _txTotal.clear();
    _rxPeak.clear();
    _schedule(_liveInterval);
    notifyListeners();
  }

  SessionSummary stop() {
    final summary = SessionSummary(
      startedAt: _startedAt ?? _now(),
      duration: elapsed,
      rxBytes: Map.of(_rxTotal),
      txBytes: Map.of(_txTotal),
    );
    _running = false;
    _clock?.stop();
    _clock = null;
    _lastSummary = summary;
    // On efface tout ce qui a été mesuré : seul le résumé survit, en mémoire.
    _rates = {};
    _rxHistory.clear();
    _txHistory.clear();
    _rxTotal.clear();
    _txTotal.clear();
    _rxPeak.clear();
    _schedule(_idleInterval);
    notifyListeners();
    return summary;
  }

  void _schedule(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_reading || _disposed) return;
    _reading = true;
    try {
      final snapshot = await _source.read();
      if (_disposed) return;
      ingest(snapshot);
    } catch (_) {
      // Lecture impossible ce tour-ci : on garde l'état précédent.
    } finally {
      _reading = false;
    }
  }

  /// Intègre une nouvelle lecture. Public pour les tests.
  @visibleForTesting
  void ingest(TrafficSnapshot snapshot) {
    _latest = snapshot;
    if (_running) {
      final prev = _previous;
      if (prev != null) {
        _rates = computeRates(prev, snapshot);
        for (final c in Channel.values) {
          final r = rate(c);
          _push(_rxHistory, c, r.rxPerSec);
          _push(_txHistory, c, r.txPerSec);
          _rxTotal[c] = rxTotal(c) + r.rxBytes;
          _txTotal[c] = txTotal(c) + r.txBytes;
          if (r.rxPerSec > rxPeak(c)) _rxPeak[c] = r.rxPerSec;
        }
      }
      _previous = snapshot;
      final limit = _autoStop;
      if (limit != null && elapsed >= limit) {
        stop();
        return;
      }
    }
    notifyListeners();
  }

  void _push(Map<Channel, List<double>> history, Channel c, double value) {
    final list = history.putIfAbsent(c, () => <double>[]);
    list.add(value);
    if (list.length > historyLength) list.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
