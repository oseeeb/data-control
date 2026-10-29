import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../traffic/capture_session.dart';

/// Historique des captures, sur ce téléphone uniquement.
///
/// Ne contient que des résumés (date, durée, volumes par canal), jamais le
/// contenu du trafic. Rien n'est ajouté tant que l'utilisateur n'a pas activé
/// l'historique dans les réglages.
class HistoryStore extends ChangeNotifier {
  HistoryStore._(this._prefs, this._entries);

  /// Au-delà, les plus anciennes captures sont oubliées.
  static const maxEntries = 500;
  static const _key = 'history';

  final SharedPreferences? _prefs;
  final List<SessionSummary> _entries;

  static Future<HistoryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <SessionSummary>[];
    for (final raw in prefs.getStringList(_key) ?? const <String>[]) {
      try {
        entries.add(SessionSummary.fromJson(jsonDecode(raw) as Map<String, Object?>));
      } catch (_) {
        // Entrée illisible (ancienne version) : on l'ignore.
      }
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return HistoryStore._(prefs, entries);
  }

  /// Historique vide, sans stockage (tests).
  factory HistoryStore.inMemory([List<SessionSummary> entries = const []]) => HistoryStore._(null, [...entries]);

  /// Les captures, la plus récente d'abord.
  List<SessionSummary> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  /// Ajoute une capture à sa place (la liste reste triée, la plus récente d'abord).
  void add(SessionSummary summary) {
    final index = _entries.indexWhere((e) => e.startedAt.isBefore(summary.startedAt));
    _entries.insert(index < 0 ? _entries.length : index, summary);
    if (_entries.length > maxEntries) _entries.removeRange(maxEntries, _entries.length);
    _save();
  }

  void remove(SessionSummary summary) {
    if (_entries.remove(summary)) _save();
  }

  void clear() {
    _entries.clear();
    _save();
  }

  void _save() {
    notifyListeners();
    _prefs?.setStringList(_key, [for (final e in _entries) jsonEncode(e.toJson())]);
  }
}
