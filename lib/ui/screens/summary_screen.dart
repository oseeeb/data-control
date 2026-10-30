import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'apps_screen.dart';

/// Résumé d'une capture : à la fin d'une session, ou rouvert depuis
/// l'historique ([fromHistory]).
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.summary, this.fromHistory = false});

  final SessionSummary summary;
  final bool fromHistory;

  Future<void> _delete(BuildContext context) async {
    final history = FluxScope.of(context).history;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer cette capture ?',
      message: 'Son résumé sera effacé de l’historique.',
      action: 'Supprimer',
    );
    if (!ok || !context.mounted) return;
    history.remove(summary);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = summary.total;
    final totalVolume = formatVolume(total);
    final used = Channel.values.where((c) => summary.volumeOf(c) > 0).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                children: [
                  if (fromHistory) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SquareIconButton(
                        icon: Icons.arrow_back_rounded,
                        label: "Retour à l'historique",
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    fromHistory
                        ? '${formatDay(summary.startedAt).toUpperCase()} · ${formatTime(summary.startedAt)}'
                        : 'SESSION TERMINÉE',
                    style: fluxText(13, weight: 700, color: p.accentText, spacing: 0.08),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatDuration(summary.duration)} de données en mouvement',
                    style: fluxText(30, weight: 800, color: p.text, height: 1.15, spacing: -0.02),
                  ),
                  const SizedBox(height: 20),
                  FluxCard(
                    radius: 22,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('Volume total', style: fluxText(13, weight: 600, color: p.muted)),
                            const Spacer(),
                            Text(
                              totalVolume.value,
                              style: fluxText(36, weight: 700, numbers: true, color: p.text, spacing: -0.02),
                            ),
                            const SizedBox(width: 6),
                            Text(totalVolume.unit, style: fluxText(15, weight: 700, color: p.muted)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          label:
                              'Répartition : ${[for (final c in Channel.values) '${c.label} ${formatShare(summary.volumeOf(c), total)}'].join(', ')}',
                          excludeSemantics: true,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: 14,
                              child: used.isEmpty
                                  ? Container(color: p.track)
                                  : Row(
                                      children: [
                                        for (var i = 0; i < used.length; i++) ...[
                                          if (i > 0) const SizedBox(width: 3),
                                          Expanded(
                                            flex: (summary.volumeOf(used[i]) * 1000 ~/ total).clamp(15, 1000),
                                            child: Container(color: p.of(used[i]).bar),
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (var row = 0; row < Channel.values.length; row += 2) ...[
                          if (row > 0) const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LegendCell(channel: Channel.values[row], summary: summary),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _LegendCell(channel: Channel.values[row + 1], summary: summary),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(label: '↓ Reçu', value: formatVolume(summary.totalRx).toString()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(label: '↑ Envoyé', value: formatVolume(summary.totalTx).toString()),
                      ),
                    ],
                  ),
                  if (summary.apps.isNotEmpty) ...[const SizedBox(height: 12), _AppsCard(summary: summary)],
                  if (!fromHistory) ...[const SizedBox(height: 20), const _PrivacyNotice()],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: fromHistory
                  ? BigActionButton(
                      label: 'Supprimer cette capture',
                      color: p.card,
                      textColor: p.liveText,
                      onPressed: () => _delete(context),
                    )
                  : BigActionButton(
                      label: 'Nouvelle capture',
                      color: p.accent,
                      textColor: p.onAccent,
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les apps qui ont le plus consommé pendant la capture.
class _AppsCard extends StatefulWidget {
  const _AppsCard({required this.summary});

  final SessionSummary summary;

  @override
  State<_AppsCard> createState() => _AppsCardState();
}

class _AppsCardState extends State<_AppsCard> {
  Map<int, Uint8List> _icons = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIcons());
  }

  Future<void> _loadIcons() async {
    final top = widget.summary.apps.take(5);
    final icons = await FluxScope.of(context).apps.icons([for (final a in top) a.uid]);
    if (mounted) setState(() => _icons = icons);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final apps = widget.summary.apps.where((a) => !a.system).toList();
    final shown = (apps.isEmpty ? widget.summary.apps : apps).take(5).toList();
    final total = widget.summary.apps.fold(0, (s, a) => s + a.total);
    return FluxCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Par app', style: fluxText(15, weight: 700, color: p.text)),
              ),
              Text(formatVolume(total).toString(), style: fluxText(13, weight: 600, color: p.muted)),
            ],
          ),
          const SizedBox(height: 10),
          for (final a in shown) ...[
            Row(
              children: [
                AppIcon(a.withIcon(_icons[a.uid]), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: fluxText(13, weight: 700, color: p.text),
                            ),
                          ),
                          Text(formatShare(a.total, total), style: fluxText(12, weight: 700, color: p.muted)),
                          const SizedBox(width: 8),
                          Text(formatVolume(a.total).toString(), style: fluxText(13, weight: 700, color: p.text)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LevelBar(
                        fraction: shown.first.total == 0 ? 0 : a.total / shown.first.total,
                        color: p.of(Channel.wifi).bar,
                        height: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => AppsScreen(summary: widget.summary))),
              style: TextButton.styleFrom(foregroundColor: p.accentText, minimumSize: const Size(44, 44)),
              child: Text('Voir toutes les apps', style: fluxText(13, weight: 700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ce qu'il advient de ce résumé : effacé, ou gardé dans l'historique.
class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kept = FluxScope.of(context).settings.keepHistory;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.accentWash,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.accentLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(kept ? Icons.history_rounded : Icons.verified_user_outlined, size: 22, color: p.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kept ? 'Résumé ajouté à l’historique' : "Rien n'a été enregistré",
                  style: fluxText(14, weight: 700, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  kept
                      ? 'Seulement la date, la durée et les volumes par canal, sur ce téléphone. Rien n’est envoyé.'
                      : "Ce résumé disparaît dès que vous quittez l'écran. Aucun historique, aucun envoi.",
                  style: fluxText(13, color: p.textSoft, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendCell extends StatelessWidget {
  const _LegendCell({required this.channel, required this.summary});

  final Channel channel;
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final volume = summary.volumeOf(channel);
    final used = volume > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: used ? p.of(channel).bar : null,
                border: used ? null : Border.all(color: p.borderMuted, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                channel.label,
                overflow: TextOverflow.ellipsis,
                style: fluxText(13, weight: 700, color: used ? p.text : p.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          used ? '${formatVolume(volume)} · ${formatShare(volume, summary.total)}' : 'Non utilisé',
          style: fluxText(13, color: p.muted),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FluxCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fluxText(12, color: p.muted)),
          const SizedBox(height: 4),
          Text(value, style: fluxText(24, weight: 700, numbers: true, color: p.text)),
        ],
      ),
    );
  }
}
