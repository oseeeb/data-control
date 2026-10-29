import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// Le gros bouton rond de l'accueil, entouré de deux anneaux et d'une
/// pulsation : GO (vert) au repos, STOP (rouge) pendant une capture.
class GoButton extends StatefulWidget {
  const GoButton({super.key, required this.onPressed, this.running = false});

  final VoidCallback onPressed;
  final bool running;

  @override
  State<GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<GoButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final fill = widget.running ? p.stop : p.accent;
    return SizedBox(
      width: 236,
      height: 236,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.cardMuted,
                border: Border.all(color: p.border),
              ),
            ),
          ),
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_pulse.value);
                return Transform.scale(
                  scale: 1 + 0.3 * t,
                  child: Container(
                    width: 164,
                    height: 164,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: fill.withValues(alpha: 0.5 * (1 - t)), width: 3),
                    ),
                  ),
                );
              },
            ),
          Semantics(
            button: true,
            label: widget.running ? 'Arrêter la capture' : 'Démarrer la capture',
            excludeSemantics: true,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onPressed();
              },
              child: AnimatedScale(
                scale: _pressed ? 0.96 : 1,
                duration: const Duration(milliseconds: 150),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 164,
                  height: 164,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    boxShadow: [BoxShadow(color: p.goShadow, blurRadius: 50, offset: const Offset(0, 18))],
                  ),
                  child: Text(
                    widget.running ? 'STOP' : 'GO',
                    style: fluxText(52, weight: 700, numbers: true, color: p.onAccent, spacing: -0.02),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
