import '../traffic/channel.dart';
import '../traffic/snapshot.dart';

/// Libellé d'état d'un canal (« Connecté », « Non branché »…).
String channelStatus(Channel c, ChannelReading r) {
  if (!r.supported) return 'Non disponible';
  if (!r.connected) {
    return switch (c) {
      Channel.usb => 'Non branché',
      Channel.bluetooth => 'Désactivé',
      _ => 'Non connecté',
    };
  }
  if (!r.measurable) return 'Non mesurable';
  return r.detail ?? 'Connecté';
}

/// Phrase d'aide sous un canal inactif.
String channelIdleHint(Channel c, ChannelReading r) {
  if (!r.supported) return 'Non suivi par ce téléphone';
  if (r.connected && !r.measurable) return 'Le téléphone ne donne pas ce chiffre';
  return switch (c) {
    Channel.wifi => 'Aucun réseau Wi-Fi',
    Channel.mobile => 'Données mobiles coupées',
    Channel.usb => 'Branchez un câble',
    Channel.bluetooth => 'Bluetooth éteint',
  };
}

/// Un canal est « actif » quand il est connecté et que l'on peut le mesurer.
bool channelActive(ChannelReading r) => r.connected && r.measurable;
