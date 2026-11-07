import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A stationary book-sheet edge finish. It is intentionally limited to the
/// outer 9 px of the sheet: text contrast and touch targets are unaffected.
/// The paint is deterministic, GPU-cheap, and never drives a frame ticker.
class ReaderPaperFinish extends StatelessWidget {
  const ReaderPaperFinish({super.key, required this.sheetWidth,
    required this.ink, required this.paper});

  final double sheetWidth;
  final Color ink, paper;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(
      painter: _ReaderPaperFinishPainter(
        sheetWidth: sheetWidth, ink: ink, paper: paper),
    )),
  );
}

class _ReaderPaperFinishPainter extends CustomPainter {
  const _ReaderPaperFinishPainter({required this.sheetWidth,
    required this.ink, required this.paper});

  final double sheetWidth;
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 680 || size.height <= 0) return;
    final width = math.min(sheetWidth, size.width - 56);
    final left = (size.width - width) / 2;
    final right = left + width;
    final line = Paint()..strokeWidth = 1
        ..color = ink.withValues(alpha: .075);

    canvas.drawLine(Offset(left + .5, 0), Offset(left + .5, size.height), line);
    canvas.drawLine(Offset(right - .5, 0), Offset(right - .5, size.height), line);

    final leftShade = Paint()..shader = LinearGradient(
      colors: [ink.withValues(alpha: .035), Colors.transparent],
    ).createShader(Rect.fromLTWH(left + 1, 0, 9, size.height));
    final rightShade = Paint()..shader = LinearGradient(
      colors: [Colors.transparent, ink.withValues(alpha: .032)],
    ).createShader(Rect.fromLTWH(right - 10, 0, 9, size.height));
    canvas.drawRect(Rect.fromLTWH(left + 1, 0, 9, size.height), leftShade);
    canvas.drawRect(Rect.fromLTWH(right - 10, 0, 9, size.height), rightShade);

    // Tiny, stable paper-edge fibers hint at a real bound book without adding
    // texture over the body text or causing random flicker during scrolling.
    final fiberPaint = Paint()..strokeWidth = .6
        ..color = ink.withValues(alpha: .055);
    for (var y = 28.0; y < size.height - 12; y += 79) {
      final phase = (y ~/ 79) % 3;
      final length = 3 + phase.toDouble();
      canvas.drawLine(Offset(left + 1, y),
          Offset(left + length, y + .6), fiberPaint);
      canvas.drawLine(Offset(right - length, y + 13),
          Offset(right - 1, y + 13.6), fiberPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReaderPaperFinishPainter old) =>
      old.sheetWidth != sheetWidth || old.ink != ink || old.paper != paper;
}
