import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../traffic/channel.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'privacy_screen.dart';

/// Réglages : unités, thème, canaux affichés, arrêt automatique,
/// écran allumé, historique, confidentialité.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _channelHints = {
    Channel.wifi: 'Réseaux sans fil',
    Channel.mobile: '4G · 5G',
    Channel.usb: 'Partage par câble',
    Channel.bluetooth: 'Appareils connectés',
  };

  /// Désactiver l'historique efface aussi ce qui a été gardé (après accord).
  Future<void> _setKeepHistory(BuildContext context, bool keep) async {
    final scope = FluxScope.of(context);
    if (keep || scope.history.isEmpty) {
      scope.settings.keepHistory = keep;
      return;
    }
    final ok = await confirmDialog(
      context,
      title: "Désactiver l'historique ?",
      message: 'Les résumés déjà gardés seront effacés de ce téléphone.',
      action: 'Désactiver et effacer',
    );
    if (!ok) return;
    scope.history.clear();
    scope.settings.keepHistory = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = FluxScope.of(context).settings;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                children: [
                  SquareIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: "Retour à l'accueil",
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Text('Réglages', style: fluxText(24, weight: 800, color: p.text, spacing: -0.01)),
                ],
              ),
              const SizedBox(height: 22),
              const SectionLabel('Affichage'),
              const SizedBox(height: 10),
              FluxCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title('Unités', sub: "Mb/s est l'unité utilisée par les opérateurs"),
                    const SizedBox(height: 10),
                    Segmented<RateUnit>(
                      value: settings.unit,
                      options: const {RateUnit.megabytes: 'Mo/s', RateUnit.megabits: 'Mb/s', RateUnit.auto: 'Auto'},
                      onChanged: (v) => settings.unit = v,
                    ),
                    const SizedBox(height: 18),
                    const _Title('Thème'),
                    const SizedBox(height: 10),
                    Segmented<ThemeMode>(
                      value: settings.theme,
                      options: const {ThemeMode.dark: 'Sombre', ThemeMode.light: 'Clair', ThemeMode.system: 'Système'},
                      onChanged: (v) => settings.theme = v,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SectionLabel('Canaux affichés'),
              const SizedBox(height: 10),
              FluxCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    for (final c in Channel.values)
                      Container(
                        constraints: const BoxConstraints(minHeight: 60),
                        decoration: BoxDecoration(
                          border: c == Channel.values.last ? null : Border(bottom: BorderSide(color: p.border)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: p.of(c).bar, borderRadius: BorderRadius.circular(4)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _Title(c.label, sub: _channelHints[c])),
                            _FluxSwitch(
                              value: settings.isVisible(c),
                              label: 'Afficher ${c.label}',
                              onChanged: (v) => settings.setVisible(c, v),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  "Masquer un canal le retire de l'écran. Il n'est jamais coupé ni filtré.",
                  style: fluxText(12, color: p.muted, height: 1.45),
                ),
              ),
              const SizedBox(height: 22),
              const SectionLabel('Capture'),
              const SizedBox(height: 10),
              FluxCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Title('Arrêt automatique', sub: 'Évite de vider la batterie si on oublie STOP'),
                    const SizedBox(height: 10),
                    Segmented<Duration>(
                      value: settings.autoStop,
                      options: {
                        for (final d in FluxSettings.autoStopChoices)
                          d: d == Duration.zero ? 'Jamais' : '${d.inMinutes} min',
                      },
                      onChanged: (v) => settings.autoStop = v,
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: p.border),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: _Title("Garder l'écran allumé", sub: 'Pendant la capture uniquement')),
                        _FluxSwitch(
                          value: settings.keepScreenOn,
                          label: "Garder l'écran allumé",
                          onChanged: (v) => settings.keepScreenOn = v,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SectionLabel('Historique'),
              const SizedBox(height: 10),
              FluxCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: _Title(
                            "Garder l'historique",
                            sub: 'Le résumé de chaque capture (date, durée, volumes), sur ce téléphone uniquement',
                          ),
                        ),
                        _FluxSwitch(
                          value: settings.keepHistory,
                          label: "Garder l'historique",
                          onChanged: (v) => _setKeepHistory(context, v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: p.border),
                    InkWell(
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Icon(Icons.history_rounded, size: 20, color: p.textSoft),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text("Voir l'historique", style: fluxText(15, weight: 700, color: p.text)),
                            ),
                            Icon(Icons.chevron_right_rounded, color: p.muted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SectionLabel('Confidentialité'),
              const SizedBox(height: 10),
              Material(
                color: p.accentWash,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: p.accentLine),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 22, color: p.accentText),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Vos données restent à vous', style: fluxText(15, weight: 700, color: p.text)),
                              const SizedBox(height: 2),
                              Text(
                                'Aucun enregistrement, aucun envoi, aucun compte. Voir les permissions utilisées.',
                                style: fluxText(12, color: p.textSoft, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: p.muted),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Center(
                child: Text('Flux · version 1.0.0', style: fluxText(12, color: p.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, {this.sub});

  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: fluxText(15, weight: 700, color: p.text)),
        if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: fluxText(12, color: p.muted))],
      ],
    );
  }
}

class _FluxSwitch extends StatelessWidget {
  const _FluxSwitch({required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: label,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: p.onAccent,
        activeTrackColor: p.accent,
        inactiveThumbColor: p.muted,
        inactiveTrackColor: p.track,
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
