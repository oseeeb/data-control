import 'channel.dart';
import 'snapshot.dart';

/// Débit d'un canal entre deux lectures, en octets par seconde.
class ChannelRate {
  const ChannelRate({this.rxPerSec = 0, this.txPerSec = 0, this.rxBytes = 0, this.txBytes = 0});

  final double rxPerSec;
  final double txPerSec;

  /// Octets échangés pendant l'intervalle.
  final int rxBytes;
  final int txBytes;

  static const zero = ChannelRate();
}

/// Octets écoulés entre deux valeurs d'un compteur cumulé.
///
/// Gère le compteur qui boucle (iOS, 32 bits) et celui qui repart de zéro
/// (interface qui se reconnecte) : dans ce dernier cas on compte 0 plutôt
/// qu'un saut négatif ou aberrant.
int counterDelta(int? previous, int? current, {int? wrapBits}) {
  if (previous == null || current == null) return 0;
  if (current >= previous) return current - previous;
  if (wrapBits != null) {
    final span = 1 << wrapBits;
    if (previous < span && current < span) return current + span - previous;
  }
  return 0;
}

/// Débits de chaque canal entre deux lectures.
Map<Channel, ChannelRate> computeRates(TrafficSnapshot previous, TrafficSnapshot current) {
  final elapsedMs = current.timestampMs - previous.timestampMs;
  final result = <Channel, ChannelRate>{};
  for (final c in Channel.values) {
    final a = previous[c];
    final b = current[c];
    if (elapsedMs <= 0 || !a.measurable || !b.measurable) {
      result[c] = ChannelRate.zero;
      continue;
    }
    final rx = counterDelta(a.rxBytes, b.rxBytes, wrapBits: current.counterBits);
    final tx = counterDelta(a.txBytes, b.txBytes, wrapBits: current.counterBits);
    final seconds = elapsedMs / 1000;
    result[c] = ChannelRate(rxPerSec: rx / seconds, txPerSec: tx / seconds, rxBytes: rx, txBytes: tx);
  }
  return result;
}
