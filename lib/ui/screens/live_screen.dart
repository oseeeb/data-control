import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../channel_text.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/live_chart.dart';
import 'channel_screen.dart';

/// Capture en cours : débit total, courbe des 60 dernières secondes,
/// détail par canal et bouton STOP.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  /// STOP : l'app affiche le résumé (voir FluxApp), d'où qu'on soit.
  void _stop() {
    HapticFeedback.mediumImpact();
    final session = FluxScope.of(context).session;
    if (session.running) {
      session.stop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scope = FluxScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.session, scope.settings]),
          builder: (context, _) {
            final s = scope.session;
            final unit = scope.settings.unit;
            final channels = scope.settings.visibleChannels;
            final measured = channels.where((c) => channelActive(s.reading(c))).toList();
            final idle = channels.where((c) => !channelActive(s.reading(c))).toList();
            final total = formatRate(s.totalRxPerSec, unit);
            final up = formatRate(s.totalTxPerSec, unit);
            final volume = formatVolume(s.totalBytes);
            final sum = measured.fold(0.0, (a, c) => a + s.rate(c).rxPerSec);

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    children: [
                      Row(
                        children: [
                          SquareIconButton(
                            icon: Icons.arrow_back_rounded,
                            label: "Retour à l'accueil (la capture continue)",
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 10),
                          LiveBadge('En direct · ${formatClock(s.elapsed)}'),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: PrivacyPill('Aucun filtrage · aucune sauvegarde', framed: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Débit total entrant', style: fluxText(13, weight: 600, color: p.muted)),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            total.value,
                            style: fluxText(56, weight: 700, numbers: true, color: p.text, height: 1, spacing: -0.03),
                          ),
                          const SizedBox(width: 8),
                          Text(total.unit, style: fluxText(18, weight: 700, color: p.muted)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('↑ $up sortant · $volume depuis GO', style: fluxText(13, color: p.muted)),
                      if (Platform.isIOS) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Sur iPhone, les chiffres se mettent à jour quand vous revenez dans Flux. '
                          'Les volumes restent justes.',
                          style: fluxText(12, color: p.muted, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FluxCard(
                        radius: 22,
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('60 dernières secondes', style: fluxText(12, weight: 600, color: p.muted)),
                                const Spacer(),
                                Text(total.unit, style: fluxText(12, weight: 600, color: p.muted)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LiveChart(
                              gridColor: p.track,
                              capacity: CaptureSession.historyLength,
                              semanticLabel: 'Courbe du débit entrant par canal sur les 60 dernières secondes',
                              series: [
                                for (final c in measured)
                                  ChartSeries(
                                    values: s.rxHistory(c),
                                    color: p.of(c).bar,
                                    dashed: c == Channel.bluetooth,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                for (final c in measured) _Legend(label: c.label, color: p.of(c).bar),
                                for (final c in idle)
                                  _Legend(label: '${c.label} (inactif)', color: p.borderMuted, muted: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final c in measured) ...[
                        _ChannelRow(
                          channel: c,
                          rate: formatRate(s.rate(c).rxPerSec, unit),
                          share: sum > 0 ? s.rate(c).rxPerSec / sum : 0,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: BigActionButton(
                    label: 'STOP',
                    color: p.stop,
                    textColor: p.onAccent,
                    onPressed: _stop,
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: p.onAccent, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color, this.muted = false});

  final String label;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: fluxText(12, weight: 600, color: muted ? p.muted : p.textSoft)),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.rate, required this.share});

  final Channel channel;
  final Quantity rate;
  final double share;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: '${channel.label}, $rate. Voir le détail',
      excludeSemantics: true,
      child: FluxCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelScreen(channel: channel))),
        child: Row(
          children: [
            ChannelIconTile(channel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(channel.label, style: fluxText(14, weight: 700, color: p.text)),
                      const Spacer(),
                      Text(rate.toString(), style: fluxText(14, weight: 700, numbers: true, color: p.text)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LevelBar(fraction: share, color: p.of(channel).bar),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.faint),
          ],
        ),
      ),
    );
  }
}
