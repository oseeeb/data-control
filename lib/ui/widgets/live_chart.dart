import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Une courbe du graphique.
class ChartSeries {
  const ChartSeries({required this.values, required this.color, this.dashed = false, this.filled = false});

  final List<double> values;
  final Color color;
  final bool dashed;
  final bool filled;
}

/// Graphique en direct des dernières secondes. Les courbes sont lissées et
/// le point le plus récent est marqué à droite.
class LiveChart extends StatelessWidget {
  const LiveChart({
    super.key,
    required this.series,
    required this.gridColor,
    this.capacity = 60,
    this.height = 150,
    required this.semanticLabel,
  });

  final List<ChartSeries> series;
  final Color gridColor;
  final int capacity;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LiveChartPainter(series, gridColor, capacity)),
      ),
    );
  }
}

class _LiveChartPainter extends CustomPainter {
  _LiveChartPainter(this.series, this.gridColor, this.capacity);

  final List<ChartSeries> series;
  final Color gridColor;
  final int capacity;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 3.6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    var maxValue = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        maxValue = math.max(maxValue, v);
      }
    }
    if (maxValue <= 0) return;
    final top = maxValue * 1.15;
    const pad = 6.0;
    final usable = size.height - pad * 2;
    final step = size.width / (capacity - 1);

    for (final s in series) {
      if (s.values.length < 2) continue;
      final start = capacity - s.values.length;
      final points = [
        for (var i = 0; i < s.values.length; i++) Offset((start + i) * step, pad + usable * (1 - s.values[i] / top)),
      ];
      final path = _smooth(points);

      if (s.filled) {
        final fill = Path.from(path)
          ..lineTo(points.last.dx, size.height)
          ..lineTo(points.first.dx, size.height)
          ..close();
        canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: 0.14));
      }

      final stroke = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(s.dashed ? _dash(path, 6, 5) : path, stroke);
      canvas.drawCircle(points.last, 4, Paint()..color = s.color);
    }
  }

  Path _smooth(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final cur = pts[i];
      final midX = (prev.dx + cur.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
    }
    return path;
  }

  Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        out.addPath(metric.extractPath(d, math.min(d + on, metric.length)), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_LiveChartPainter old) => true;
}
