import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../channel_text.dart';
import '../format.dart';
import '../widgets/background_hint.dart';
import '../widgets/common.dart';
import '../widgets/go_button.dart';
import 'apps_screen.dart';
import 'channel_screen.dart';
import 'history_screen.dart';
import 'live_screen.dart';
import 'settings_screen.dart';

/// Accueil : le bouton GO et l'état des quatre canaux. Pendant une capture,
/// il devient STOP et les cartes affichent les débits en direct.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _start(BuildContext context) {
    final scope = FluxScope.of(context);
    final limit = scope.settings.autoStop;
    scope.session.start(autoStop: limit == Duration.zero ? null : limit);
    Navigator.of(context).push(fadeRoute(const LiveScreen()));
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
            final running = s.running;
            final channels = scope.settings.visibleChannels;
            final total = formatRate(running ? s.totalRxPerSec : 0, unit);
            final sum = channels.fold(0.0, (a, c) => a + s.rate(c).rxPerSec);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    const _Logo(),
                    const SizedBox(width: 12),
                    const Spacer(),
                    Flexible(
                      flex: 4,
                      child: PrivacyPill(scope.settings.keepHistory ? "Rien n'est envoyé" : "Rien n'est enregistré"),
                    ),
                    const SizedBox(width: 8),
                    SquareIconButton(
                      icon: Icons.history_rounded,
                      label: 'Historique',
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
                    ),
                    const SizedBox(width: 8),
                    SquareIconButton(
                      icon: Icons.tune_rounded,
                      label: 'Réglages',
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Center(
                  child: Text(
                    running ? 'EN DIRECT · ${formatClock(s.elapsed)}' : 'PRÊT À CAPTER',
                    style: fluxText(13, weight: 700, color: running ? p.liveText : p.accentText, spacing: 0.08),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: GoButton(running: running, onPressed: () => running ? s.stop() : _start(context)),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(total.value, style: fluxText(34, weight: 700, numbers: true, color: p.text, spacing: -0.02)),
                    const SizedBox(width: 6),
                    Text('${total.unit} au total', style: fluxText(15, weight: 600, color: p.muted)),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      running
                          ? 'La capture continue même si vous changez d’écran ou d’app. Appuyez sur STOP pour l’arrêter.'
                          : 'Appuyez sur GO pour voir vos données circuler en direct, canal par canal.',
                      textAlign: TextAlign.center,
                      style: fluxText(13, color: p.muted, height: 1.45),
                    ),
                  ),
                ),
                if (running) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(fadeRoute(const LiveScreen())),
                      icon: const Icon(Icons.show_chart_rounded, size: 18),
                      label: Text('Voir la courbe en direct', style: fluxText(14, weight: 700)),
                      style: TextButton.styleFrom(foregroundColor: p.accentText, minimumSize: const Size(44, 44)),
                    ),
                  ),
                ],
                const BackgroundHint(),
                const SizedBox(height: 16),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Hauteur fixe plutôt qu'un ratio : la carte garde sa place
                  // sur les petits écrans comme sur les grands.
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 172 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
                  ),
                  children: [
                    for (final c in channels)
                      _ChannelCard(c, session: s, unit: unit, share: sum > 0 ? s.rate(c).rxPerSec / sum : 0),
                  ],
                ),
                const SizedBox(height: 16),
                FluxCard(
                  radius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppsScreen())),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: p.accentWash, borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.query_stats_rounded, size: 20, color: p.accentText),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Apps en arrière-plan', style: fluxText(15, weight: 700, color: p.text)),
                            const SizedBox(height: 2),
                            Text(
                              'Lesquelles consomment quand vous ne les utilisez pas ?',
                              style: fluxText(12, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.faint),
                    ],
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

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/brand/flux_icon.png', fit: BoxFit.cover, semanticLabel: 'Logo Flux'),
        ),
        const SizedBox(width: 10),
        Text('Flux', style: fluxText(22, weight: 700, numbers: true, color: p.text, spacing: -0.02)),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard(this.channel, {required this.session, required this.unit, required this.share});

  final Channel channel;
  final CaptureSession session;
  final RateUnit unit;
  final double share;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = p.of(channel);
    final reading = session.reading(channel);
    final active = channelActive(reading);
    final live = active && session.running;
    final rate = session.rate(channel);
    final down = formatRate(rate.rxPerSec, unit);
    return Semantics(
      container: true,
      button: live,
      label: live
          ? '${channel.label}, ${down.value} ${down.unit}. Voir le détail'
          : '${channel.label}, ${channelStatus(channel, reading)}',
      excludeSemantics: true,
      child: FluxCard(
        muted: !active,
        onTap: live
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelScreen(channel: channel)))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChannelIconTile(channel, dimmed: !active),
                const Spacer(),
                Flexible(
                  child: Text(
                    channelStatus(channel, reading),
                    overflow: TextOverflow.ellipsis,
                    style: fluxText(11, weight: 700, color: active ? colors.text : p.muted),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(channel.label, style: fluxText(14, weight: 700, color: p.text)),
            const SizedBox(height: 2),
            if (live)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '↓ ${down.value} '),
                    TextSpan(
                      text: down.unit,
                      style: fluxText(12, color: p.muted),
                    ),
                  ],
                ),
                maxLines: 1,
                style: fluxText(22, weight: 700, numbers: true, color: p.text),
              )
            else
              Text('—', style: fluxText(22, weight: 700, numbers: true, color: active ? p.text : p.faint)),
            Text(
              live
                  ? '↑ ${formatRate(rate.txPerSec, unit)}'
                  : active
                  ? 'En attente de GO'
                  : channelIdleHint(channel, reading),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fluxText(12, color: p.muted),
            ),
            const SizedBox(height: 10),
            LevelBar(fraction: live ? share : 0, color: colors.bar),
          ],
        ),
      ),
    );
  }
}

/// Transition douce entre écrans.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
