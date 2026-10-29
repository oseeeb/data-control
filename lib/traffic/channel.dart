/// Les quatre canaux d'entrée que Flux distingue.
enum Channel {
  wifi('wifi', 'Wi-Fi'),
  mobile('mobile', 'Mobile'),
  usb('usb', 'USB'),
  bluetooth('bluetooth', 'Bluetooth');

  const Channel(this.key, this.label);

  /// Clé utilisée par le code natif et les réglages.
  final String key;
  final String label;

  static Channel? fromKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}
