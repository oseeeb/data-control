import 'package:flutter/material.dart';

import '../traffic/channel.dart';

/// Couleurs d'un canal dans un thème.
class ChannelColors {
  const ChannelColors({required this.text, required this.bar, required this.tint});

  /// Texte et icônes (contraste ≥ 4,5:1 sur les cartes).
  final Color text;

  /// Barres et courbes.
  final Color bar;

  /// Fond de la pastille d'icône.
  final Color tint;
}

/// Palette Flux, reprise de la maquette (sombre et clair).
class FluxPalette extends ThemeExtension<FluxPalette> {
  const FluxPalette({
    required this.ground,
    required this.card,
    required this.cardMuted,
    required this.border,
    required this.borderMuted,
    required this.track,
    required this.text,
    required this.textSoft,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentWash,
    required this.accentLine,
    required this.stop,
    required this.liveText,
    required this.liveWash,
    required this.goShadow,
    required this.channels,
  });

  final Color ground;
  final Color card;
  final Color cardMuted;
  final Color border;
  final Color borderMuted;
  final Color track;
  final Color text;
  final Color textSoft;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color accentWash;
  final Color accentLine;
  final Color stop;
  final Color liveText;
  final Color liveWash;
  final Color goShadow;
  final Map<Channel, ChannelColors> channels;

  ChannelColors of(Channel c) => channels[c]!;

  static const dark = FluxPalette(
    ground: Color(0xFF0B0F1A),
    card: Color(0xFF151B2B),
    cardMuted: Color(0xFF121725),
    border: Color(0xFF232B40),
    borderMuted: Color(0xFF2A3350),
    track: Color(0xFF232B40),
    text: Color(0xFFF2F5FA),
    textSoft: Color(0xFFC5CCDA),
    muted: Color(0xFF9AA4B8),
    faint: Color(0xFF6E7891),
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0B0F1A),
    accentText: Color(0xFFC6F432),
    accentWash: Color(0x14C6F432),
    accentLine: Color(0x40C6F432),
    stop: Color(0xFFFF6B6B),
    liveText: Color(0xFFFF8A8A),
    liveWash: Color(0x24FF6B6B),
    goShadow: Color(0x73000000),
    channels: {
      Channel.wifi: ChannelColors(text: Color(0xFF5B9BFF), bar: Color(0xFF5B9BFF), tint: Color(0x295B9BFF)),
      Channel.mobile: ChannelColors(text: Color(0xFFFFA94D), bar: Color(0xFFFFA94D), tint: Color(0x29FFA94D)),
      Channel.usb: ChannelColors(text: Color(0xFF3DDC97), bar: Color(0xFF3DDC97), tint: Color(0x1A3DDC97)),
      Channel.bluetooth: ChannelColors(text: Color(0xFFB794FF), bar: Color(0xFFB794FF), tint: Color(0x29B794FF)),
    },
  );

  static const light = FluxPalette(
    ground: Color(0xFFF4F6FA),
    card: Color(0xFFFFFFFF),
    cardMuted: Color(0xFFF9FAFC),
    border: Color(0xFFE3E7EF),
    borderMuted: Color(0xFFC9D0DC),
    track: Color(0xFFEDF0F5),
    text: Color(0xFF0E1424),
    textSoft: Color(0xFF3B4458),
    muted: Color(0xFF5A6478),
    faint: Color(0xFF8A93A6),
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0E1424),
    accentText: Color(0xFF3F5C00),
    accentWash: Color(0xFFF1FBD6),
    accentLine: Color(0xFFD6EE8A),
    stop: Color(0xFFFF6B6B),
    liveText: Color(0xFFB42318),
    liveWash: Color(0xFFFDE8E8),
    goShadow: Color(0x290E1424),
    channels: {
      Channel.wifi: ChannelColors(text: Color(0xFF2563EB), bar: Color(0xFF2563EB), tint: Color(0xFFE6EEFF)),
      Channel.mobile: ChannelColors(text: Color(0xFFC2570C), bar: Color(0xFFE8761E), tint: Color(0xFFFFF0E3)),
      Channel.usb: ChannelColors(text: Color(0xFF0B7A53), bar: Color(0xFF0B7A53), tint: Color(0xFFE3F5EC)),
      Channel.bluetooth: ChannelColors(text: Color(0xFF7C3AED), bar: Color(0xFF7C3AED), tint: Color(0xFFF1EAFE)),
    },
  );

  @override
  FluxPalette copyWith() => this;

  @override
  FluxPalette lerp(FluxPalette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension FluxContext on BuildContext {
  FluxPalette get palette => Theme.of(this).extension<FluxPalette>()!;
}

/// Style de texte Flux. Les polices sont variables : on règle l'axe `wght`
/// en plus de la graisse pour que le rendu suive vraiment.
TextStyle fluxText(
  double size, {
  int weight = 500,
  Color? color,
  bool numbers = false,
  double? height,
  double? spacing,
}) {
  return TextStyle(
    fontFamily: numbers ? 'SpaceGrotesk' : 'Manrope',
    fontSize: size,
    fontWeight: FontWeight.values[((weight ~/ 100) - 1).clamp(0, 8)],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    letterSpacing: spacing == null ? null : spacing * size,
  );
}

ThemeData buildTheme(FluxPalette p, Brightness brightness) {
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: p.ground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      surface: p.ground,
      primary: p.accent,
      onPrimary: p.onAccent,
    ),
    splashFactory: InkSparkle.splashFactory,
    extensions: [p],
  );
}
