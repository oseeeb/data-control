import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../traffic/channel.dart';

enum RateUnit { megabytes, megabits, auto }

/// Préférences de l'app, gardées sur le téléphone. L'historique des
/// résumés est désactivé par défaut ([keepHistory]).
class FluxSettings extends ChangeNotifier {
  FluxSettings._(this._prefs);

  static const autoStopChoices = [Duration.zero, Duration(minutes: 5), Duration(minutes: 15), Duration(minutes: 30)];

  final SharedPreferences? _prefs;

  RateUnit _unit = RateUnit.auto;
  ThemeMode _theme = ThemeMode.dark;
  final Set<Channel> _hidden = {};
  Duration _autoStop = const Duration(minutes: 15);
  bool _keepScreenOn = true;
  bool _keepHistory = false;

  static Future<FluxSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FluxSettings._(prefs).._read();
  }

  /// Réglages par défaut, sans stockage (tests).
  factory FluxSettings.inMemory() => FluxSettings._(null);

  RateUnit get unit => _unit;
  ThemeMode get theme => _theme;
  Duration get autoStop => _autoStop;
  bool get keepScreenOn => _keepScreenOn;
  bool get keepHistory => _keepHistory;
  bool isVisible(Channel c) => !_hidden.contains(c);
  List<Channel> get visibleChannels => Channel.values.where(isVisible).toList();

  set unit(RateUnit value) => _update(() => _unit = value);
  set theme(ThemeMode value) => _update(() => _theme = value);
  set autoStop(Duration value) => _update(() => _autoStop = value);
  set keepScreenOn(bool value) => _update(() => _keepScreenOn = value);
  set keepHistory(bool value) => _update(() => _keepHistory = value);

  void setVisible(Channel c, bool visible) => _update(() => visible ? _hidden.remove(c) : _hidden.add(c));

  void _read() {
    final p = _prefs!;
    _unit = RateUnit.values.asNameMap()[p.getString('unit')] ?? _unit;
    _theme = ThemeMode.values.asNameMap()[p.getString('theme')] ?? _theme;
    _hidden
      ..clear()
      ..addAll((p.getStringList('hidden') ?? const []).map(Channel.fromKey).whereType<Channel>());
    final minutes = p.getInt('autoStopMinutes');
    if (minutes != null) _autoStop = Duration(minutes: minutes);
    _keepScreenOn = p.getBool('keepScreenOn') ?? _keepScreenOn;
    _keepHistory = p.getBool('keepHistory') ?? _keepHistory;
  }

  void _update(void Function() change) {
    change();
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    p.setString('unit', _unit.name);
    p.setString('theme', _theme.name);
    p.setStringList('hidden', _hidden.map((c) => c.key).toList());
    p.setInt('autoStopMinutes', _autoStop.inMinutes);
    p.setBool('keepScreenOn', _keepScreenOn);
    p.setBool('keepHistory', _keepHistory);
  }
}
