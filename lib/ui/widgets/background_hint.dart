import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/channel.dart';

/// Encart affiché pendant une capture quand l'économie de batterie du
/// téléphone peut fermer Flux en arrière-plan (Android). Il ouvre le réglage
/// où l'on choisit « Ne pas optimiser » pour Flux.
class BackgroundHint extends StatefulWidget {
  const BackgroundHint({super.key});

  @override
  State<BackgroundHint> createState() => _BackgroundHintState();
}

class _BackgroundHintState extends State<BackgroundHint> with WidgetsBindingObserver {
  bool _restricted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Au retour des réglages du téléphone, on vérifie à nouveau.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted) return;
    final restricted = await FluxScope.of(context).host.backgroundRestricted();
    if (mounted && restricted != _restricted) setState(() => _restricted = restricted);
  }

  @override
  Widget build(BuildContext context) {
    if (!_restricted) return const SizedBox.shrink();
    final p = context.palette;
    // L'orange du canal Mobile sert de couleur d'avertissement.
    final colors = p.of(Channel.mobile);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.tint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.bar.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.battery_alert_rounded, size: 20, color: colors.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Le téléphone peut couper la capture', style: fluxText(14, weight: 700, color: p.text)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Pour une capture longue en arrière-plan, choisissez « Ne pas optimiser » (ou « Sans restriction ») '
              'pour Flux dans la batterie. Sinon, Flux rattrape les volumes à votre retour, mais la notification '
              'peut disparaître.',
              style: fluxText(12.5, color: p.textSoft, height: 1.45),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: () => FluxScope.of(context).host.openBatterySettings(),
                style: FilledButton.styleFrom(
                  backgroundColor: p.card,
                  foregroundColor: p.text,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: p.borderMuted),
                ),
                child: Text('Ouvrir le réglage batterie', style: fluxText(14, weight: 700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
