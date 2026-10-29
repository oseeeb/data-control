import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../channel_text.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/live_chart.dart';

/// Détail d'un canal pendant la capture.
class ChannelScreen extends StatelessWidget {
  const ChannelScreen({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scope = FluxScope.of(context);
    final colors = p.of(channel);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.session, scope.settings]),
          builder: (context, _) {
            final s = scope.session;
            final unit = scope.settings.unit;
            final reading = s.reading(channel);
            final rate = s.rate(channel);
            final down = formatRate(rate.rxPerSec, unit);
            final up = formatRate(rate.txPerSec, unit);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    SquareIconButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Retour',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    ChannelIconTile(channel),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(channel.label, style: fluxText(20, weight: 800, color: p.text)),
                          Text(channelStatus(channel, reading), style: fluxText(12, color: p.muted)),
                        ],
                      ),
                    ),
                    if (s.running) ...[const SizedBox(width: 8), LiveBadge(formatClock(s.elapsed), compact: true)],
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _BigRate(label: '↓ Entrant', labelColor: colors.text, value: down),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BigRate(label: '↑ Sortant', labelColor: p.textSoft, value: up),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FluxCard(
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Débit en direct · 60 dernières secondes', style: fluxText(13, weight: 700, color: p.text)),
                      const SizedBox(height: 10),
                      LiveChart(
                        height: 170,
                        gridColor: p.track,
                        capacity: CaptureSession.historyLength,
                        semanticLabel: 'Courbes des débits ${channel.label} entrant et sortant',
                        series: [
                          ChartSeries(values: s.rxHistory(channel), color: colors.bar, filled: true),
                          ChartSeries(values: s.txHistory(channel), color: p.textSoft, dashed: true),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(width: 14, height: 3, color: colors.bar),
                          const SizedBox(width: 6),
                          Text('Entrant', style: fluxText(12, weight: 600, color: p.textSoft)),
                          const SizedBox(width: 14),
                          Container(width: 14, height: 2, color: p.textSoft),
                          const SizedBox(width: 6),
                          Text('Sortant (pointillés)', style: fluxText(12, weight: 600, color: p.textSoft)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FluxCard(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _InfoRow('Reçu depuis GO', formatVolume(s.rxTotal(channel)).toString()),
                      _InfoRow('Envoyé depuis GO', formatVolume(s.txTotal(channel)).toString()),
                      _InfoRow(
                        'Pic entrant',
                        formatRate(s.rxPeak(channel), unit).toString(),
                        last: reading.detail == null,
                      ),
                      if (reading.detail != null) _InfoRow('Connexion', reading.detail!, last: true),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Flux lit seulement les compteurs du canal. Le contenu de vos données n'est ni lu, ni filtré, ni conservé.",
                  textAlign: TextAlign.center,
                  style: fluxText(12, color: p.muted, height: 1.5),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BigRate extends StatelessWidget {
  const _BigRate({required this.label, required this.labelColor, required this.value});

  final String label;
  final Color labelColor;
  final Quantity value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FluxCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fluxText(12, weight: 700, color: labelColor)),
          const SizedBox(height: 6),
          Text(value.value, style: fluxText(34, weight: 700, numbers: true, color: p.text, height: 1, spacing: -0.02)),
          const SizedBox(height: 6),
          Text(value.unit, style: fluxText(12, color: p.muted)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Text(label, style: fluxText(14, color: p.muted)),
          const Spacer(),
          Text(value, style: fluxText(14, weight: 700, color: p.text)),
        ],
      ),
    );
  }
}
