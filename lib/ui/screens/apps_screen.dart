import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../apps/app_usage.dart';
import '../../traffic/channel.dart';
import '../format.dart';
import '../widgets/common.dart';

enum _Period {
  day('24 h', Duration(hours: 24)),
  week('7 jours', Duration(days: 7)),
  month('30 jours', Duration(days: 30));

  const _Period(this.label, this.length);
  final String label;
  final Duration length;
}

/// Analyse : quelles apps consomment des données en arrière-plan.
///
/// Les chiffres viennent du téléphone (Android les compte déjà, app par app) ;
/// Flux les lit à l'ouverture de l'écran et ne les garde pas.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with WidgetsBindingObserver {
  _Period _period = _Period.day;
  bool _showSystem = false;
  bool? _access;
  bool _loading = false;
  String? _error;
  List<AppUsage> _apps = const [];

  AppUsageSource get _source => FluxScope.of(context).apps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Au retour des réglages (accès accordé), on recharge.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _access != true) _load();
  }

  Future<void> _load() async {
    if (!mounted || !_source.supported) return;
    final access = await _source.hasAccess();
    if (!mounted) return;
    setState(() {
      _access = access;
      _loading = access;
      _error = null;
    });
    if (!access) return;
    try {
      final end = DateTime.now();
      final apps = await _source.query(end.subtract(_period.length), end);
      if (mounted) setState(() => _apps = apps);
    } catch (_) {
      if (mounted) setState(() => _error = 'Le téléphone n’a pas donné les chiffres. Réessayez dans un instant.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(_Period p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = [
      for (final a in _apps)
        if (_showSystem || !a.system) a,
    ]..sort((a, b) => b.background.compareTo(a.background));
    final listed = visible.where((a) => a.background > 0).toList();
    final hiddenSystem = _apps.where((a) => a.system && a.background > 0).length;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
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
                    child: Text(
                      'Apps en arrière-plan',
                      style: fluxText(22, weight: 800, color: p.text, spacing: -0.01),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Les apps qui utilisent Internet quand vous ne les avez pas à l’écran.',
                style: fluxText(13, color: p.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              if (!_source.supported)
                const _Notice(
                  icon: Icons.phone_iphone_rounded,
                  title: 'Pas disponible sur iPhone',
                  text:
                      'iOS ne donne à aucune app la consommation des autres apps. Vous la trouverez dans '
                      'Réglages › Données cellulaires, sans le détail de l’arrière-plan.',
                )
              else if (_access == false)
                _Notice(
                  icon: Icons.query_stats_rounded,
                  title: 'Un accès est nécessaire',
                  text:
                      'Android compte déjà les données de chaque app. Pour les lire, Flux a besoin de l’accès '
                      '« Données d’utilisation ». Flux lit ces chiffres seulement sur cet écran et ne les garde pas.',
                  action: 'Autoriser l’accès',
                  onAction: _source.requestAccess,
                )
              else ...[
                Segmented<_Period>(
                  value: _period,
                  options: {for (final x in _Period.values) x: x.label},
                  onChanged: _setPeriod,
                ),
                const SizedBox(height: 16),
                if (_access == null || (_loading && _apps.isEmpty))
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _Notice(icon: Icons.error_outline_rounded, title: 'Analyse impossible', text: _error!)
                else ...[
                  _Overview(apps: visible, period: _period),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: SectionLabel('Les plus gourmandes')),
                      Text('Système', style: fluxText(12, weight: 600, color: p.muted)),
                      Switch(
                        value: _showSystem,
                        onChanged: (v) => setState(() => _showSystem = v),
                        activeThumbColor: p.onAccent,
                        activeTrackColor: p.accent,
                        inactiveThumbColor: p.muted,
                        inactiveTrackColor: p.track,
                        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (listed.isEmpty)
                    const _Notice(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Rien à signaler',
                      text: 'Aucune app n’a consommé de données en arrière-plan sur cette période.',
                    )
                  else
                    for (final app in listed.take(30)) ...[
                      _AppRow(app: app, max: listed.first.background),
                      const SizedBox(height: 8),
                    ],
                  if (!_showSystem && hiddenSystem > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$hiddenSystem service${hiddenSystem > 1 ? 's' : ''} du système masqué${hiddenSystem > 1 ? 's' : ''}.',
                      style: fluxText(12, color: p.muted),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Chiffres fournis par Android, regroupés par tranches d’environ 2 heures. Wi-Fi et mobile '
                    'seulement : le système ne détaille pas l’USB ni le Bluetooth par app. Flux ne garde rien.',
                    style: fluxText(12, color: p.muted, height: 1.45),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.apps, required this.period});

  final List<AppUsage> apps;
  final _Period period;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final background = apps.fold(0, (a, x) => a + x.background);
    final total = apps.fold(0, (a, x) => a + x.total);
    final wifi = apps.fold(0, (a, x) => a + x.wifiBackground);
    final mobile = apps.fold(0, (a, x) => a + x.mobileBackground);
    final volume = formatVolume(background);
    return FluxCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('En arrière-plan · ${period.label}', style: fluxText(13, weight: 600, color: p.muted)),
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
            '${formatShare(background, total)} de toutes les données (${formatVolume(total)})',
            style: fluxText(13, color: p.muted),
          ),
          const SizedBox(height: 16),
          VolumeBar(volumes: {Channel.wifi: wifi, Channel.mobile: mobile}, height: 12),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Legend(color: p.of(Channel.wifi).bar, text: 'Wi-Fi ${formatVolume(wifi)}'),
              _Legend(color: p.of(Channel.mobile).bar, text: 'Mobile ${formatVolume(mobile)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(text, style: fluxText(12, weight: 600, color: context.palette.textSoft)),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon(this.app, {this.size = 40});

  final AppUsage app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final icon = app.icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox(
        width: size,
        height: size,
        child: icon != null
            ? Image.memory(icon, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: p.track,
                child: Icon(
                  app.system ? Icons.settings_rounded : Icons.apps_rounded,
                  size: size * 0.55,
                  color: p.muted,
                ),
              ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.max});

  final AppUsage app;
  final int max;

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AppDetails(app: app),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = formatVolume(app.background);
    final mobileShare = app.background == 0 ? 0 : app.mobileBackground / app.background;
    return Semantics(
      button: true,
      label: '${app.name}, $bg en arrière-plan. Voir le détail',
      excludeSemantics: true,
      child: FluxCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        onTap: () => _openDetails(context),
        child: Row(
          children: [
            _AppIcon(app),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fluxText(14, weight: 700, color: p.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(bg.toString(), style: fluxText(14, weight: 700, numbers: true, color: p.text)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LevelBar(fraction: max == 0 ? 0 : app.background / max, color: p.of(Channel.wifi).bar),
                  const SizedBox(height: 6),
                  Text(
                    mobileShare >= 0.05
                        ? '${formatShare(app.mobileBackground, app.background)} sur le réseau mobile · '
                              '${formatVolume(app.foreground)} à l’écran'
                        : 'Wi-Fi · ${formatVolume(app.foreground)} à l’écran',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fluxText(12, color: mobileShare >= 0.05 ? p.of(Channel.mobile).text : p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDetails extends StatelessWidget {
  const _AppDetails({required this.app});

  final AppUsage app;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pkg = app.packageName;
    Widget row(String label, int bytes, {bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Text(label, style: fluxText(14, color: p.muted)),
          const Spacer(),
          Text(formatVolume(bytes).toString(), style: fluxText(14, weight: 700, color: p.text)),
        ],
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AppIcon(app, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: fluxText(18, weight: 800, color: p.text)),
                      if (pkg != null)
                        Text(
                          pkg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: fluxText(12, color: p.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionLabel('En arrière-plan'),
            row('Wi-Fi', app.wifiBackground),
            row('Réseau mobile', app.mobileBackground, last: true),
            const SizedBox(height: 12),
            const SectionLabel('À l’écran'),
            row('Wi-Fi', app.wifiForeground),
            row('Réseau mobile', app.mobileForeground, last: true),
            if (pkg != null) ...[
              const SizedBox(height: 16),
              Text(
                'Pour la limiter : dans la page de l’app, ouvrez « Données mobiles » et désactivez '
                '« Données en arrière-plan ».',
                style: fluxText(13, color: p.textSoft, height: 1.45),
              ),
              const SizedBox(height: 12),
              BigActionButton(
                label: 'Ouvrir la page de l’app',
                color: p.accent,
                textColor: p.onAccent,
                onPressed: () => FluxScope.of(context).apps.openAppDetails(pkg),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text, this.action, this.onAction});

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
