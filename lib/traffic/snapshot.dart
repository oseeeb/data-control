import 'channel.dart';

/// État d'un canal à un instant donné, tel que lu par le code natif.
///
/// [rxBytes] et [txBytes] sont des compteurs cumulés depuis le démarrage du
/// téléphone. Ils valent `null` quand le système ne permet pas de les lire
/// pour ce canal.
class ChannelReading {
  const ChannelReading({
    required this.connected,
    required this.measurable,
    this.rxBytes,
    this.txBytes,
    this.detail,
    this.supported = true,
  });

  /// `false` quand le système ne permet pas du tout de suivre ce canal
  /// (le Bluetooth sur iPhone).
  final bool supported;
  final bool connected;
  final bool measurable;
  final int? rxBytes;
  final int? txBytes;

  /// Précision affichable : « 4G · 5G », « 2 appareils »…
  final String? detail;

  factory ChannelReading.fromMap(Map<Object?, Object?> map) {
    final rx = map['rx'];
    final tx = map['tx'];
    return ChannelReading(
      connected: map['connected'] == true,
      measurable: map['measurable'] == true && rx is int && tx is int,
      rxBytes: rx is int ? rx : null,
      txBytes: tx is int ? tx : null,
      detail: map['detail'] as String?,
      supported: map['supported'] != false,
    );
  }

  static const unavailable = ChannelReading(connected: false, measurable: false);
}

/// Une lecture de tous les canaux à la fois.
class TrafficSnapshot {
  const TrafficSnapshot({required this.timestampMs, required this.channels, this.counterBits});

  /// Horloge monotone du téléphone, en millisecondes.
  final int timestampMs;
  final Map<Channel, ChannelReading> channels;

  /// Largeur des compteurs quand ils bouclent (32 sur iOS), sinon `null`.
  final int? counterBits;

  ChannelReading operator [](Channel c) => channels[c] ?? ChannelReading.unavailable;

  factory TrafficSnapshot.fromMap(Map<Object?, Object?> map) {
    final raw = (map['channels'] as Map?) ?? const {};
    final channels = <Channel, ChannelReading>{};
    for (final entry in raw.entries) {
      final c = Channel.fromKey(entry.key as String);
      if (c != null && entry.value is Map) {
        channels[c] = ChannelReading.fromMap(entry.value as Map<Object?, Object?>);
      }
    }
    return TrafficSnapshot(
      timestampMs: map['timestampMs'] as int,
      channels: channels,
      counterBits: map['counterBits'] as int?,
    );
  }
}
