import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../traffic/traffic_source.dart';
import '../widgets/common.dart';

/// Ce que Flux fait (et ne fait pas) de vos données, et les permissions
/// réellement demandées sur ce téléphone.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final android = Platform.isAndroid;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                SquareIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Retour aux réglages',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Text('Confidentialité', style: fluxText(24, weight: 800, color: p.text, spacing: -0.01)),
              ],
            ),
            const SizedBox(height: 26),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.accentWash,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.accentLine),
                ),
                child: Icon(Icons.verified_user_outlined, size: 36, color: p.accentText),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Flux regarde passer vos données. Il ne les garde pas.',
              textAlign: TextAlign.center,
              style: fluxText(22, weight: 800, color: p.text, height: 1.2),
            ),
            const SizedBox(height: 10),
            Text(
              "L'app lit uniquement les compteurs de chaque canal : combien, et par où. Jamais ce que contiennent vos données.",
              textAlign: TextAlign.center,
              style: fluxText(14, color: p.textSoft, height: 1.5),
            ),
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: [
                if (FluxScope.of(context).settings.keepHistory)
                  const _Promise(
                    Icons.history_rounded,
                    'Résumés seulement',
                    'Historique activé : date, durée et volumes, sur ce téléphone.',
                  )
                else
                  const _Promise(
                    Icons.save_outlined,
                    'Aucun enregistrement',
                    "Tout s'efface à l'arrêt. Pas d'historique.",
                  ),
                const _Promise(Icons.cloud_off_outlined, 'Aucun envoi', 'Rien ne quitte votre téléphone.'),
                const _Promise(Icons.filter_alt_off_outlined, 'Aucun filtrage', 'Le trafic passe sans être touché.'),
                const _Promise(Icons.person_off_outlined, 'Aucun compte', 'Ni e-mail, ni inscription, ni pub.'),
              ],
            ),
            const SizedBox(height: 22),
            const SectionLabel('Permissions utilisées'),
            const SizedBox(height: 10),
            FluxCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  if (android) ...[
                    const _Permission(
                      icon: Icons.show_chart_rounded,
                      title: 'État du réseau',
                      status: 'Automatique',
                      text: 'Pour savoir quels canaux sont connectés et compter les octets reçus et envoyés.',
                    ),
                    const _Permission(
                      icon: Icons.bluetooth_rounded,
                      title: 'Bluetooth',
                      status: 'Automatique',
                      text: 'Pour savoir si le Bluetooth est allumé. Flux ne se connecte à aucun appareil.',
                    ),
                    const _Permission(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      status: 'Au premier GO',
                      text:
                          'Pour que la capture continue quand vous utilisez d’autres apps, avec le débit et un bouton STOP. '
                          'Si vous refusez, la capture continue mais sans notification visible.',
                    ),
                    const _Permission(
                      icon: Icons.query_stats_rounded,
                      title: 'Données d’utilisation',
                      status: 'Facultatif',
                      text:
                          'Seulement pour « Apps en arrière-plan » : lire la consommation de chaque app, qu’Android '
                          'compte déjà. Flux lit ces chiffres sur cet écran et ne les garde pas.',
                    ),
                    const _Permission(
                      icon: Icons.public_off_rounded,
                      title: 'Accès à Internet',
                      status: 'Non demandé',
                      text: "Flux n'a pas la permission d'utiliser Internet : il ne pourrait rien envoyer, même s'il le voulait.",
                      last: true,
                      off: true,
                    ),
                  ] else
                    const _Permission(
                      icon: Icons.show_chart_rounded,
                      title: 'Aucune permission',
                      status: 'Rien à autoriser',
                      text: 'Sur iPhone, Flux lit les compteurs réseau du système sans rien demander.',
                      last: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: PlatformTrafficSource.openAppSettings,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                iconAlignment: IconAlignment.end,
                label: Text('Gérer dans les réglages du téléphone', style: fluxText(15, weight: 700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.text,
                  backgroundColor: p.card,
                  side: BorderSide(color: p.borderMuted),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FluxCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: p.accentText),
          const SizedBox(height: 8),
          Text(title, style: fluxText(14, weight: 700, color: p.text)),
          const SizedBox(height: 4),
          Text(text, style: fluxText(12, color: p.muted, height: 1.4)),
        ],
      ),
    );
  }
}

class _Permission extends StatelessWidget {
  const _Permission({
    required this.icon,
    required this.title,
    required this.status,
    required this.text,
    this.last = false,
    this.off = false,
  });

  final IconData icon;
  final String title;
  final String status;
  final String text;
  final bool last;
  final bool off;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: p.textSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: fluxText(14, weight: 700, color: p.text)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: off ? p.track : p.accentWash,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(status, style: fluxText(11, weight: 700, color: off ? p.textSoft : p.accentText)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(text, style: fluxText(12, color: p.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
