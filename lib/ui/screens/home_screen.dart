import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/channel.dart';
import '../channel_text.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/go_button.dart';
import 'live_screen.dart';
import 'settings_screen.dart';

/// Accueil : le bouton GO et l'état des quatre canaux.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _start(BuildContext context) {
    final scope = FluxScope.of(context);
    final limit = scope.settings.autoStop;
    scope.session.start(autoStop: limit == Duration.zero ? null : limit);
    if (scope.settings.keepScreenOn) WakelockPlus.enable().catchError((Object _) {});
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
            final channels = scope.settings.visibleChannels;
            final zero = formatRate(0, scope.settings.unit);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    const _Logo(),
                    const SizedBox(width: 12),
                    const Spacer(),
                    const Flexible(flex: 4, child: PrivacyPill("Rien n'est enregistré")),
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
                  child: Text('PRÊT À CAPTER', style: fluxText(13, weight: 700, color: p.accentText, spacing: 0.08)),
                ),
                const SizedBox(height: 14),
                Center(child: GoButton(onPressed: () => _start(context))),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(zero.value, style: fluxText(34, weight: 700, numbers: true, color: p.text, spacing: -0.02)),
                    const SizedBox(width: 6),
                    Text('${zero.unit} au total', style: fluxText(15, weight: 600, color: p.muted)),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      'Appuyez sur GO pour voir vos données circuler en direct, canal par canal.',
                      textAlign: TextAlign.center,
                      style: fluxText(13, color: p.muted, height: 1.45),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
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
                  children: [for (final c in channels) _ChannelCard(c)],
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
          decoration: BoxDecoration(color: p.logoGround, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.show_chart_rounded, size: 22, color: p.logoMark),
        ),
        const SizedBox(width: 10),
        Text('Flux', style: fluxText(22, weight: 700, numbers: true, color: p.text, spacing: -0.02)),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard(this.channel);
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = p.of(channel);
    final reading = FluxScope.of(context).session.reading(channel);
    final active = channelActive(reading);
    return Semantics(
      container: true,
      label: '${channel.label}, ${channelStatus(channel, reading)}',
      excludeSemantics: true,
      child: FluxCard(
        muted: !active,
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
            Text('—', style: fluxText(22, weight: 700, numbers: true, color: active ? p.text : p.faint)),
            Text(
              active ? 'En attente de GO' : channelIdleHint(channel, reading),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fluxText(12, color: p.muted),
            ),
            const SizedBox(height: 10),
            LevelBar(fraction: 0, color: colors.bar),
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
