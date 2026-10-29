import '../app/settings.dart';

/// Un nombre et son unité, affichés séparément (« 8,4 » + « Mo/s »).
class Quantity {
  const Quantity(this.value, this.unit);
  final String value;
  final String unit;

  @override
  String toString() => '$value $unit';
}

String _decimal(double v, {int digits = 1}) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Formate un débit (octets/seconde) selon l'unité choisie dans les réglages.
/// Unités décimales, comme les opérateurs : 1 Mo = 1 000 000 octets.
Quantity formatRate(double bytesPerSec, RateUnit unit) {
  switch (unit) {
    case RateUnit.megabytes:
      return Quantity(_decimal(bytesPerSec / 1e6), 'Mo/s');
    case RateUnit.megabits:
      return Quantity(_decimal(bytesPerSec * 8 / 1e6), 'Mb/s');
    case RateUnit.auto:
      if (bytesPerSec >= 1e9) return Quantity(_decimal(bytesPerSec / 1e9), 'Go/s');
      if (bytesPerSec >= 1e6) return Quantity(_decimal(bytesPerSec / 1e6), 'Mo/s');
      return Quantity((bytesPerSec / 1e3).round().toString(), 'Ko/s');
  }
}

/// Formate un volume en octets (Ko, Mo, Go).
Quantity formatVolume(int bytes) {
  if (bytes >= 1e9) return Quantity(_decimal(bytes / 1e9), 'Go');
  if (bytes >= 1e7) return Quantity((bytes / 1e6).round().toString(), 'Mo');
  if (bytes >= 1e6) return Quantity(_decimal(bytes / 1e6), 'Mo');
  return Quantity((bytes / 1e3).round().toString(), 'Ko');
}

/// « 01:24 » pour le chrono en direct.
String formatClock(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// « 1 min 24 s » pour le résumé.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
  if (m > 0) return '$m min $s s';
  return '$s s';
}

/// Part en pourcentage, arrondie (« 86 % »).
String formatShare(int part, int total) {
  if (total <= 0) return '0 %';
  return '${(part * 100 / total).round()} %';
}

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// « 14:05 ».
String formatTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// « 29 oct. » ou « 29 oct. 2025 » si ce n'est pas l'année en cours.
String formatDate(DateTime t, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final year = t.year == today.year ? '' : ' ${t.year}';
  return '${t.day} ${_months[t.month - 1]}$year';
}

/// Titre d'un groupe de jour : « Aujourd'hui », « Hier », « Lundi 27 oct. ».
String formatDay(DateTime t, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final diff = DateTime(today.year, today.month, today.day).difference(d).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Hier';
  final weekday = _weekdays[t.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)} ${formatDate(t, now: today)}';
}
