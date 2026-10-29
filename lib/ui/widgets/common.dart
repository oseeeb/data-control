import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../traffic/channel.dart';

IconData channelIcon(Channel c) => switch (c) {
  Channel.wifi => Icons.wifi_rounded,
  Channel.mobile => Icons.signal_cellular_alt_rounded,
  Channel.usb => Icons.usb_rounded,
  Channel.bluetooth => Icons.bluetooth_rounded,
};

/// Carte de base : fond, bordure, coins arrondis.
class FluxCard extends StatelessWidget {
  const FluxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.muted = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: muted ? p.borderMuted : p.border),
    );
    return Material(
      color: muted ? p.cardMuted : p.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Pastille d'icône colorée d'un canal.
class ChannelIconTile extends StatelessWidget {
  const ChannelIconTile(this.channel, {super.key, this.size = 36, this.dimmed = false});

  final Channel channel;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.of(channel);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dimmed ? colors.tint.withValues(alpha: colors.tint.a * 0.6) : colors.tint,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(channelIcon(channel), size: size * 0.56, color: colors.text),
    );
  }
}

/// Barre de progression fine, animée.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.fraction, required this.color, this.height = 6});

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: p.track,
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
          ),
        ),
      ),
    );
  }
}

/// Bouton carré à icône (réglages, retour).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Tooltip(
              message: label,
              child: Icon(icon, size: 20, color: p.textSoft),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille « Rien n'est enregistré » / « Aucun filtrage ».
class PrivacyPill extends StatelessWidget {
  const PrivacyPill(this.text, {super.key, this.framed = true});

  final String text;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: framed ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : EdgeInsets.zero,
      decoration: framed
          ? BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.border),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: p.accentText),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fluxText(framed ? 11 : 12, weight: 600, color: framed ? p.textSoft : p.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille rouge « En direct · 01:24 ».
class LiveBadge extends StatelessWidget {
  const LiveBadge(this.text, {super.key, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(color: p.liveWash, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: p.stop, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fluxText(compact ? 12 : 13, weight: 700, color: p.liveText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gros bouton pleine largeur (STOP, Nouvelle capture).
class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onPressed,
    this.leading,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fluxText(20, weight: 700, numbers: true, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titre de section en petites capitales.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: fluxText(12, weight: 700, color: context.palette.muted, spacing: 0.08)),
      ),
    );
  }
}

/// Demande de confirmation avant une action qui efface quelque chose.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final p = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title, style: fluxText(18, weight: 800, color: p.text)),
      content: Text(message, style: fluxText(14, color: p.textSoft, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Annuler', style: fluxText(14, weight: 700, color: p.textSoft)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action, style: fluxText(14, weight: 700, color: p.liveText)),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Barre empilée : la part de chaque canal dans un volume.
class VolumeBar extends StatelessWidget {
  const VolumeBar({super.key, required this.volumes, this.height = 6});

  final Map<Channel, int> volumes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final used = Channel.values.where((c) => (volumes[c] ?? 0) > 0).toList();
    final total = used.fold(0, (a, c) => a + volumes[c]!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total == 0
            ? Container(color: p.track)
            : Row(
                children: [
                  for (var i = 0; i < used.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: (volumes[used[i]]! * 1000 ~/ total).clamp(12, 1000),
                      child: Container(color: p.of(used[i]).bar),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Sélecteur à pastilles (Mo/s · Mb/s · Auto, 24 h · 7 jours…).
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.ground, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final entry in options.entries) ...[
            if (entry.key != options.keys.first) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == value,
                child: GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == value ? p.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entry.value,
                      style: fluxText(13, weight: 700, color: entry.key == value ? p.onAccent : p.textSoft),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
