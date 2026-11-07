import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// Hand-drawn empty shelf. One ticker drives the stroke reveal, 14 dust
/// motes and an eight-second beam. TickerMode pauses when its page is hidden.
class EmptyShelfArt extends StatefulWidget {
  const EmptyShelfArt({super.key, this.height = 218});
  final double height;
  @override
  State<EmptyShelfArt> createState() => _EmptyShelfArtState();
}

class _EmptyShelfArtState extends State<EmptyShelfArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this, duration: const Duration(seconds: 8));
  bool _drawingFinished = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker.addListener(() {
      if (!_drawingFinished && _ticker.value >= .15) {
        _drawingFinished = true;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Continuous idle beam is Android-only. Other platforms use a still
    // drawing, which also keeps widget/golden tests deterministic.
    final active = Platform.isAndroid && TickerMode.of(context) &&
        !HyesMotion.reduced(context);
    if (active && !_running) {
      _running = true;
      _ticker.repeat();
    } else if (!active && _running) {
      _running = false;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return Semantics(label: '一间等书入住的书房', image: true,
      child: RepaintBoundary(child: SizedBox(
        width: double.infinity, height: widget.height,
        child: CustomPaint(painter: _ShelfDrawing(
          tokens: t, ticker: _ticker,
          finished: _drawingFinished || !_running)),
      )),
    );
  }
}

class _ShelfDrawing extends CustomPainter {
  _ShelfDrawing({required this.tokens, required this.ticker,
    required this.finished}) : super(repaint: ticker);
  final HyesTokens tokens;
  final AnimationController ticker;
  final bool finished;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = math.min(w / 320, h / 215);
    canvas.save();
    canvas.translate((w - 320 * scale) / 2, (h - 215 * scale) / 2);
    canvas.scale(scale);
    final t = ticker.value;
    final drawn = finished ? 1.0 : (t / .15).clamp(0.0, 1.0);
    final beamLean = math.sin(t * 2 * math.pi) * 6;

    // Light has no texture or filter; low-opacity polygon with soft stops.
    final lightPath = Path()
      ..moveTo(260 + beamLean, 0)
      ..lineTo(306 + beamLean, 0)
      ..lineTo(262, 196)
      ..lineTo(104, 196)
      ..close();
    canvas.drawPath(lightPath, Paint()
      ..shader = uiGradient(tokens.vermilion.withValues(alpha: .058))
          .createShader(const Rect.fromLTWH(104, 0, 210, 210)));

    final edge = Paint()
      ..color = tokens.ink.withValues(alpha: .54)
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final shelf = Path()
      ..moveTo(28, 185)
      ..lineTo(290, 185)
      ..moveTo(40, 189)
      ..lineTo(40, 202)
      ..moveTo(278, 189)
      ..lineTo(278, 202)
      ..moveTo(28, 185)
      ..lineTo(28, 181)
      ..lineTo(290, 181)
      ..lineTo(290, 185);
    for (final metric in shelf.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * drawn), edge);
    }

    // Draw real book geometry (a hairline and corner vermilion accent), not
    // an emoji or an icon inside a halo. Sequential landing and slight sway.
    final positions = [74.0, 116.0, 165.0];
    final heights = [116.0, 132.0, 102.0];
    final widths = [36.0, 40.0, 31.0];
    final angles = [-.05, .08, -.12];
    for (var i = 0; i < positions.length; i++) {
      final arrival = ((t * 8 - 1.0 - i * .18) / .48).clamp(0.0, 1.0);
      final value = finished ? 1.0 : Curves.easeOutBack.transform(arrival);
      if (value <= 0) continue;
      canvas.save();
      canvas.translate(positions[i], 181);
      canvas.translate(0, (1 - value) * -24);
      canvas.rotate(angles[i] + (1 - value) * .10);
      final rect = Rect.fromLTWH(-widths[i] / 2,
        -heights[i], widths[i], heights[i]);
      canvas.drawRRect(RRect.fromRectAndRadius(rect,
        const Radius.circular(2.5)),
        Paint()..color = tokens.surface);
      canvas.drawRRect(RRect.fromRectAndRadius(rect,
        const Radius.circular(2.5)), edge);
      canvas.drawLine(Offset(rect.left + 6, rect.top + 8),
        Offset(rect.left + 6, rect.bottom - 8), edge);
      if (i == 1) {
        canvas.drawLine(Offset(rect.left + 14, rect.top + 14),
          Offset(rect.right - 7, rect.top + 14),
          Paint()..color = tokens.vermilion..strokeWidth = 2);
      }
      canvas.restore();
    }

    final dust = Paint()..color = tokens.ink.withValues(alpha: .13);
    for (var i = 0; i < 14; i++) {
      final x = 55 + ((i * 71 + 17) % 224).toDouble() +
          math.sin(t * 2 * math.pi + i) * 5;
      final y = 18 + ((i * 47 + 13) % 150).toDouble() -
          ((t * 23 + i * 11) % 25);
      canvas.drawCircle(Offset(x, y), i.isEven ? .7 : .45, dust);
    }
    canvas.restore();
  }

  LinearGradient uiGradient(Color ink) => LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [ink, ink.withValues(alpha: .018), Colors.transparent],
  );

  @override
  bool shouldRepaint(covariant _ShelfDrawing old) =>
      old.tokens != tokens || old.finished != finished;
}
