import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zeichnet eine gestrichelte Rundecke-Border um ein Kind-Widget.
/// Verwendet für "Freie Stunde"-Karten und freie Zellen in der Wochenmatrix.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    this.color,
    this.radius = 12,
    this.dashWidth = 6,
    this.gapWidth = 4,
    this.strokeWidth = 1.2,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final Color? color;
  final double radius;
  final double dashWidth;
  final double gapWidth;
  final double strokeWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color ?? Theme.of(context).colorScheme.outlineVariant,
        radius: radius,
        dashWidth: dashWidth,
        gapWidth: gapWidth,
        strokeWidth: strokeWidth,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.gapWidth,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double gapWidth;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.gapWidth != gapWidth ||
      oldDelegate.strokeWidth != strokeWidth;
}