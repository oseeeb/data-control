import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'summary_screen.dart';

/// Historique des captures : un bilan des 30 derniers jours, puis chaque
/// capture, groupée par jour. Uniquement si l'utilisateur l'a activé.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _period = Duration(days: 30);

  Future<void> _clearAll(BuildContext context) async {
    final history = FluxScope.of(context).history;
    final ok = await confirmDialog(
      context,
      title: 'Tout effacer ?',
      message: 'Tous les résumés de capture seront supprimés de ce téléphone.',
      action: 'Tout effacer',
    );
    if (ok) history.clear();
  }

  void _removeWithUndo(BuildContext context, SessionSummary entry) {
    final history = FluxScope.of(context).history;
    history.remove(entry);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Capture supprimée'),
          action: SnackBarAction(label: 'Annuler', onPressed: () => history.add(entry)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scope = FluxScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.history, scope.settings]),
          builder: (context, _) {
            final entries = scope.history.entries;
            final enabled = scope.settings.keepHistory;
            final now = DateTime.now();
            final recent = entries.where((e) => now.difference(e.startedAt) <= _period).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    SquareIconButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Retour',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Historique', style: fluxText(24, weight: 800, color: p.text, spacing: -0.01)),
                    ),
                    if (entries.isNotEmpty)
                      SquareIconButton(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Tout effacer',
                        onPressed: () => _clearAll(context),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                if (!enabled && entries.isEmpty)
                  _EmptyState(
                    icon: Icons.history_toggle_off_rounded,
                    title: "L'historique est désactivé",
                    text:
                        'Par défaut, Flux n’enregistre rien. Activez l’historique pour garder le résumé de chaque '
                        'capture : date, durée et volumes par canal. Sur ce téléphone uniquement, jamais envoyé, '
                        'effaçable à tout moment.',
                    action: 'Activer l’historique',
                    onAction: () => scope.settings.keepHistory = true,
                  )
                else if (entries.isEmpty)
                  const _EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Aucune capture pour l’instant',
                    text: 'Appuyez sur GO puis STOP : le résumé de la capture apparaîtra ici.',
                  )
                else ...[
                  _Overview(entries: recent),
                  for (final group in _byDay(entries)) ...[
                    const SizedBox(height: 22),
                    SectionLabel(formatDay(group.first.startedAt, now: now)),
                    const SizedBox(height: 10),
                    for (final entry in group) ...[
                      Dismissible(
                        key: ObjectKey(entry),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(color: p.liveWash, borderRadius: BorderRadius.circular(18)),
                          child: Icon(Icons.delete_outline_rounded, color: p.liveText),
                        ),
                        onDismissed: (_) => _removeWithUndo(context, entry),
                        child: _EntryRow(entry: entry),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (!enabled) ...[
                    const SizedBox(height: 16),
                    Text(
                      'L’historique est désactivé : les nouvelles captures ne sont plus ajoutées.',
                      style: fluxText(12, color: p.muted, height: 1.45),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Regroupe les captures (déjà triées, la plus récente d'abord) par jour.
  static List<List<SessionSummary>> _byDay(List<SessionSummary> entries) {
    final groups = <List<SessionSummary>>[];
    for (final e in entries) {
      final last = groups.isEmpty ? null : groups.last.first.startedAt;
      if (last != null &&
          last.year == e.startedAt.year &&
          last.month == e.startedAt.month &&
          last.day == e.startedAt.day) {
        groups.last.add(e);
      } else {
        groups.add([e]);
      }
    }
    return groups;
  }
}

/// Bilan des 30 derniers jours.
class _Overview extends StatelessWidget {
  const _Overview({required this.entries});

  final List<SessionSummary> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final perChannel = {for (final c in Channel.values) c: entries.fold(0, (a, e) => a + e.volumeOf(c))};
    final total = perChannel.values.fold(0, (a, b) => a + b);
    final duration = entries.fold(Duration.zero, (a, e) => a + e.duration);
    final volume = formatVolume(total);
    return FluxCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('30 derniers jours', style: fluxText(13, weight: 600, color: p.muted)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(volume.value, style: fluxText(40, weight: 700, numbers: true, color: p.text, spacing: -0.02)),
              const SizedBox(width: 6),
              Text(volume.unit, style: fluxText(16, weight: 700, color: p.muted)),
            ],
          ),
          Text(
            '${entries.length} capture${entries.length > 1 ? 's' : ''} · ${formatDuration(duration)} au total',
            style: fluxText(13, color: p.muted),
          ),
          const SizedBox(height: 16),
          VolumeBar(volumes: perChannel, height: 12),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final c in Channel.values)
                if (perChannel[c]! > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: p.of(c).bar, borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${c.label} ${formatVolume(perChannel[c]!)}',
                        style: fluxText(12, weight: 600, color: p.textSoft),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final SessionSummary entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final volume = formatVolume(entry.total);
    return Semantics(
      button: true,
      label: 'Capture à ${formatTime(entry.startedAt)}, ${formatDuration(entry.duration)}, $volume. Voir le détail',
      excludeSemantics: true,
      child: FluxCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => SummaryScreen(summary: entry, fromHistory: true))),
        child: Column(
          children: [
            Row(
              children: [
                Text(formatTime(entry.startedAt), style: fluxText(15, weight: 700, numbers: true, color: p.text)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    formatDuration(entry.duration),
                    overflow: TextOverflow.ellipsis,
                    style: fluxText(13, color: p.muted),
                  ),
                ),
                const Spacer(),
                Text(volume.toString(), style: fluxText(15, weight: 700, numbers: true, color: p.text)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: p.faint),
              ],
            ),
            const SizedBox(height: 10),
            VolumeBar(volumes: {for (final c in Channel.values) c: entry.volumeOf(c)}),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.text, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FluxCard(
      radius: 22,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: p.accentWash,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.accentLine),
            ),
            child: Icon(icon, size: 30, color: p.accentText),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: fluxText(18, weight: 800, color: p.text),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: fluxText(14, color: p.textSoft, height: 1.5),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            BigActionButton(label: action!, color: p.accent, textColor: p.onAccent, onPressed: onAction!),
          ],
        ],
      ),
    );
  }
}
