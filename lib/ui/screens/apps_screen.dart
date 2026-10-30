import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../apps/app_usage.dart';
import '../../traffic/capture_host.dart';
import '../../traffic/capture_session.dart';
import '../../traffic/channel.dart';
import '../format.dart';
import '../widgets/common.dart';

enum _Mode {
  capture('Capture', null),
  day('24 h', Duration(hours: 24)),
  week('7 j', Duration(days: 7)),
  month('30 j', Duration(days: 30));

  const _Mode(this.label, this.length);
  final String label;

  /// Période de l'historique du système ; `null` pour la capture.
  final Duration? length;
}

/// Consommation par app.
///
/// - Mode « Capture » : la part de chaque app pendant la capture (en cours,
///   ou terminée si [summary] est fourni). Les compteurs par app sont relevés
///   à GO et à STOP ; la différence est exacte.
/// - Modes 24 h / 7 j / 30 j : l'historique qu'Android garde déjà, par
///   tranches d'environ 2 heures.
///
/// Dans les deux cas, les chiffres viennent du téléphone et Flux ne les
/// garde pas (sauf la part par app dans le résumé, si l'historique est activé).
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, this.summary});

  /// Capture terminée dont on montre la part par app.
  final SessionSummary? summary;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with WidgetsBindingObserver {
  static const _liveRefresh = Duration(seconds: 15);

  _Mode _mode = _Mode.capture;
  bool _showSystem = false;
  bool _backgroundOnly = false;
  bool? _access;
  bool _loading = false;
  String? _error;

  List<AppUsage> _history = const [];
  AppBreakdown? _live;
  Map<int, Uint8List> _icons = const {};
  Timer? _timer;

  AppUsageSource get _source => FluxScope.of(context).apps;

  // Gardée dès le départ : on en a besoin à la fermeture, quand le contexte n'est plus sûr.
  CaptureSession? _sessionRef;
  CaptureSession get _session => _sessionRef ??= FluxScope.of(context).session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sessionRef == null) {
      _session.addListener(_onSession);
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sessionRef?.removeListener(_onSession);
    super.dispose();
  }

  // Au retour des réglages (accès accordé), on recharge.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _access != true) _load();
  }

  /// STOP pendant qu'on regarde : on fige la dernière lecture.
  void _onSession() {
    if (!_session.running) _timer?.cancel();
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
      if (_mode == _Mode.capture) {
        await _loadCapture();
      } else {
        final end = DateTime.now();
        final apps = await _source.query(end.subtract(_mode.length!), end);
        if (mounted) setState(() => _history = apps);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Le téléphone n’a pas donné les chiffres. Réessayez dans un instant.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCapture() async {
    final summary = widget.summary;
    if (summary != null) {
      if (_icons.isEmpty && summary.apps.isNotEmpty) {
        final icons = await _source.icons([for (final a in summary.apps) a.uid]);
        if (mounted) setState(() => _icons = icons);
      }
      return;
    }
    if (!_session.running) return;
    final live = await FluxScope.of(context).host.captureApps();
    if (!mounted) return;
    setState(() => _live = live);
    _timer ??= Timer.periodic(_liveRefresh, (_) => _loadCapture());
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _load();
  }

  /// Les apps à montrer dans le mode courant, triées, et le volume de référence.
  ({List<AppUsage> apps, DateTime? since, DateTime? startedAt, int reference, Duration? elapsed}) _current() {
    final summary = widget.summary;
    if (_mode != _Mode.capture) {
      return (apps: _history, since: null, startedAt: null, reference: 0, elapsed: null);
    }
    if (summary != null) {
      return (
        apps: [for (final a in summary.apps) a.withIcon(_icons[a.uid])],
        since: summary.appsSince,
        startedAt: summary.startedAt,
        reference: summary.volumeOf(Channel.wifi) + summary.volumeOf(Channel.mobile),
        elapsed: summary.duration,
      );
    }
    final s = _session;
    final wifi = s.rxTotal(Channel.wifi) + s.txTotal(Channel.wifi);
    final mobile = s.rxTotal(Channel.mobile) + s.txTotal(Channel.mobile);
    return (
      apps: _live?.apps ?? const [],
      since: _live?.since,
      startedAt: s.startedAt,
      reference: wifi + mobile,
      elapsed: s.elapsed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final capture = _mode == _Mode.capture;
    // En mode capture on classe par total ; sinon par arrière-plan (l'objet de l'historique).
    final byBackground = !capture || _backgroundOnly;
    int value(AppUsage a) => byBackground ? a.background : a.total;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) {
            final data = _current();
            final visible = [
              for (final a in data.apps)
                if (_showSystem || !a.system) a,
            ]..sort((a, b) => value(b).compareTo(value(a)));
            final listed = visible.where((a) => value(a) > 0).toList();
            final hiddenSystem = data.apps.where((a) => a.system && value(a) > 0).length;
            final attributed = listed.fold(0, (sum, a) => sum + value(a));

            return RefreshIndicator(
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
                          'Consommation par app',
                          style: fluxText(22, weight: 800, color: p.text, spacing: -0.01),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    capture ? 'La part de chaque app pendant la capture, à l’écran et en arrière-plan.' : 'Les apps qui utilisent Internet quand vous ne les avez pas à l’écran, d’après l’historique du téléphone.',
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
                  else ...[
                    Segmented<_Mode>(
                      value: _mode,
                      options: {for (final m in _Mode.values) m: m.label},
                      onChanged: _setMode,
                    ),
                    const SizedBox(height: 16),
                    if (_access == false)
                      _Notice(
                        icon: Icons.query_stats_rounded,
                        title: 'Un accès est nécessaire',
                        text:
                            'Android compte déjà les données de chaque app. Pour les lire, Flux a besoin de l’accès '
                            '« Données d’utilisation ». Flux lit ces chiffres sur cet écran et ne les garde pas. '
                            '${capture && _session.running ? 'La part par app sera comptée à partir du moment où vous l’accordez.' : ''}',
                        action: 'Autoriser l’accès',
                        onAction: _source.requestAccess,
                      )
                    else if (capture && widget.summary == null && !_session.running)
                      const _Notice(
                        icon: Icons.play_circle_outline_rounded,
                        title: 'Aucune capture en cours',
                        text:
                            'Appuyez sur GO : Flux relève les compteurs de chaque app au départ, puis à STOP. '
                            'La part de chaque app apparaît ici en direct, puis dans le résumé.',
                      )
                    else if (_access == null || (_loading && listed.isEmpty && data.apps.isEmpty))
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _Notice(icon: Icons.error_outline_rounded, title: 'Analyse impossible', text: _error!)
                    else ...[
                      if (capture)
                        _CaptureOverview(
                          apps: visible,
                          attributed: attributed,
                          reference: data.reference,
                          since: data.since,
                          startedAt: data.startedAt,
                          elapsed: data.elapsed,
                          running: widget.summary == null && _session.running,
                          backgroundOnly: _backgroundOnly,
                        )
                      else
                        _HistoryOverview(apps: visible, mode: _mode),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(child: SectionLabel(capture ? 'Par app' : 'Les plus gourmandes')),
                          if (capture) ...[
                            _Toggle(
                              label: 'Arrière-plan',
                              value: _backgroundOnly,
                              onChanged: (v) => setState(() => _backgroundOnly = v),
                            ),
                            const SizedBox(width: 6),
                          ],
                          _Toggle(
                            label: 'Système',
                            value: _showSystem,
                            onChanged: (v) => setState(() => _showSystem = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (listed.isEmpty)
                        _Notice(
                          icon: Icons.check_circle_outline_rounded,
                          title: capture ? 'Rien pour l’instant' : 'Rien à signaler',
                          text: capture
                              ? 'Aucune app n’a encore utilisé de données${byBackground ? ' en arrière-plan' : ''} '
                                    'depuis le départ de la mesure.'
                              : 'Aucune app n’a consommé de données en arrière-plan sur cette période.',
                        )
                      else
                        for (final app in listed.take(40)) ...[
                          _AppRow(
                            app: app,
                            value: value(app),
                            max: value(listed.first),
                            share: capture ? formatShare(value(app), attributed) : null,
                            sub: _subtitle(app, capture: capture, byBackground: byBackground),
                            warn: app.mobile >= 0.05 * app.total,
                          ),
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
                        capture
                            ? 'Compteurs par app relevés au départ et à chaque lecture : la différence est exacte. '
                                  'Wi-Fi et mobile seulement : le système ne détaille pas l’USB ni le Bluetooth par app. '
                                  'Flux ne garde cette part par app que dans le résumé, si l’historique est activé.'
                            : 'Chiffres fournis par Android, par tranches d’environ 2 heures (la période est arrondie '
                                  'à la tranche). Wi-Fi et mobile seulement. Flux ne garde rien.',
                        style: fluxText(12, color: p.muted, height: 1.45),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _subtitle(AppUsage a, {required bool capture, required bool byBackground}) {
    final mobileShare = a.total == 0 ? 0.0 : a.mobile / a.total;
    final network = mobileShare >= 0.05 ? '${formatShare(a.mobile, a.total)} en mobile' : 'Wi-Fi';
    if (!capture) {
      return mobileShare >= 0.05
          ? '${formatShare(a.mobileBackground, a.background)} sur le réseau mobile · ${formatVolume(a.foreground)} à l’écran'
          : 'Wi-Fi · ${formatVolume(a.foreground)} à l’écran';
    }
    return byBackground
        ? '$network · ${formatVolume(a.foreground)} à l’écran'
        : '$network · ${formatVolume(a.background)} en arrière-plan';
  }
}

/// Bilan de la capture : part attribuée aux apps, et ce qui reste.
class _CaptureOverview extends StatelessWidget {
  const _CaptureOverview({
    required this.apps,
    required this.attributed,
    required this.reference,
    required this.since,
    required this.startedAt,
    required this.elapsed,
    required this.running,
    required this.backgroundOnly,
  });

  final List<AppUsage> apps;
  final int attributed;
  final int reference;
  final DateTime? since;
  final DateTime? startedAt;
  final Duration? elapsed;
  final bool running;
  final bool backgroundOnly;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = apps.fold(0, (s, a) => s + a.total);
    final background = apps.fold(0, (s, a) => s + a.background);
    final wifi = apps.fold(0, (s, a) => s + a.wifi);
    final mobile = apps.fold(0, (s, a) => s + a.mobile);
    final unattributed = reference - total;
    final volume = formatVolume(backgroundOnly ? background : total);
    // L'accès accordé dès GO (à quelques secondes près) : on compte depuis GO.
    final fromStart =
        since == null || startedAt == null || since!.difference(startedAt!).abs() < const Duration(seconds: 20);
    final when = fromStart ? 'Depuis GO' : 'Depuis ${formatTime(since!)} (autorisation)';
    return FluxCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${backgroundOnly ? 'En arrière-plan' : 'Toutes les apps'} · $when',
                  style: fluxText(13, weight: 600, color: p.muted),
                ),
              ),
              if (running) LiveBadge(elapsed == null ? 'En direct' : formatClock(elapsed!), compact: true),
            ],
          ),
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
            backgroundOnly
                ? '${formatShare(background, total)} de ce que les apps ont utilisé (${formatVolume(total)})'
                : '${formatVolume(background)} en arrière-plan · ${formatVolume(total - background)} à l’écran',
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
          if (reference > 0 && unattributed > reference * 0.05) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${formatVolume(unattributed)} mesurés sur le Wi-Fi et le mobile ne sont attribués à aucune app '
                '(${formatShare(unattributed, reference)}). Causes possibles : VPN, services du système, '
                'ou accès accordé après GO.',
                style: fluxText(12, color: p.textSoft, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bilan d'une période de l'historique du système (arrière-plan).
class _HistoryOverview extends StatelessWidget {
  const _HistoryOverview({required this.apps, required this.mode});

  final List<AppUsage> apps;
  final _Mode mode;

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
          Text('En arrière-plan · ${mode.label}', style: fluxText(13, weight: 600, color: p.muted)),
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

/// Petit interrupteur à pastille (Système, Arrière-plan).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? p.accent : p.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: value ? p.accent : p.border),
          ),
          child: Text(label, style: fluxText(12, weight: 700, color: value ? p.onAccent : p.textSoft)),
        ),
      ),
    );
  }
}

/// Icône d'une app, ou un symbole à défaut.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = 40});

  final AppUsage app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final icon = app.icon;
    final fallback = Container(
      color: p.track,
      child: Icon(app.system ? Icons.settings_rounded : Icons.apps_rounded, size: size * 0.55, color: p.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox(
        width: size,
        height: size,
        // Une icône illisible (image abîmée) laisse place au symbole.
        child: icon == null || icon.isEmpty
            ? fallback
            : Image.memory(icon, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.value,
    required this.max,
    required this.sub,
    required this.warn,
    this.share,
  });

  final AppUsage app;
  final int value;
  final int max;
  final String sub;

  /// Une bonne part passe par le réseau mobile.
  final bool warn;
  final String? share;

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
    final volume = formatVolume(value);
    return Semantics(
      button: true,
      label: '${app.name}, $volume${share != null ? ', $share' : ''}. Voir le détail',
      excludeSemantics: true,
      child: FluxCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        onTap: () => _openDetails(context),
        child: Row(
          children: [
            AppIcon(app),
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
                      if (share != null) ...[
                        Text(share!, style: fluxText(12, weight: 700, color: p.muted)),
                        const SizedBox(width: 8),
                      ],
                      Text(volume.toString(), style: fluxText(14, weight: 700, numbers: true, color: p.text)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LevelBar(fraction: max == 0 ? 0 : value / max, color: p.of(Channel.wifi).bar),
                  const SizedBox(height: 6),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fluxText(12, color: warn ? p.of(Channel.mobile).text : p.muted),
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
                AppIcon(app, size: 48),
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
                Text(
                  formatVolume(app.total).toString(),
                  style: fluxText(16, weight: 700, numbers: true, color: p.text),
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
            text.trim(),
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
