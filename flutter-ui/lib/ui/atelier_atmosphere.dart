import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../data/book_entry.dart';
import '../design/motion.dart';
import '../widgets/book_cover.dart';
import 'atelier_widgets.dart';

/// Ambient book color and subtle cursor light, without an idle animation.
class AtelierNightAtmosphere extends StatefulWidget {
  const AtelierNightAtmosphere({
    super.key, required this.child, this.focusBook,
  });
  final BookEntry? focusBook;
  final Widget child;

  @override
  State<AtelierNightAtmosphere> createState() =>
      _AtelierNightAtmosphereState();
}

class _AtelierNightAtmosphereState extends State<AtelierNightAtmosphere> {
  final ValueNotifier<Offset> _pointer =
      ValueNotifier(const Offset(-1000, -1000));
  Future<Color>? _color;

  @override
  void initState() {
    super.initState();
    _loadColor();
  }

  void _loadColor() {
    final book = widget.focusBook;
    _color = book == null ? null : CoverColorCache.read(book);
  }

  @override
  void didUpdateWidget(covariant AtelierNightAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusBook?.id != widget.focusBook?.id) {
      _loadColor();
    }
  }

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (HyesMotion.reduced(context)) {
      return widget.child;
    }
    final night = AtelierColor.dark(context);
    return MouseRegion(
      key: const ValueKey('atelier-night-atmosphere'),
      opaque: false,
      onHover: (event) {
        if (event.kind != PointerDeviceKind.mouse &&
            event.kind != PointerDeviceKind.stylus) return;
        if ((event.localPosition - _pointer.value).distance > 3) {
          _pointer.value = event.localPosition;
        }
      },
      onExit: (_) => _pointer.value = const Offset(-1000, -1000),
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        Positioned.fill(child: IgnorePointer(
          child: RepaintBoundary(
            child: FutureBuilder<Color>(
              future: _color,
              builder: (context, snapshot) =>
                ValueListenableBuilder<Offset>(
                  valueListenable: _pointer,
                  builder: (context, point, _) =>
                    CustomPaint(painter: _AtelierNightFieldPainter(
                      pointer: point,
                      night: night,
                      accent: snapshot.data ??
                        AtelierColor.accent(context))),
                ),
            ),
          ),
        )),
      ]),
    );
  }
}

class _AtelierNightFieldPainter extends CustomPainter {
  const _AtelierNightFieldPainter({
    required this.pointer, required this.accent, required this.night,
  });
  final Offset pointer;
  final Color accent;
  final bool night;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final ambience = Rect.fromCircle(
      center: Offset(size.width * .17, size.height * .12),
      radius: math.min(540, size.width * .6));
    canvas.drawOval(ambience, Paint()..shader = RadialGradient(colors: [
      accent.withValues(alpha: night ? .055 : .045),
      accent.withValues(alpha: night ? .018 : .014),
      Colors.transparent,
    ]).createShader(ambience));
    if (pointer.dx >= 0 && pointer.dy >= 0) {
      final beam = Rect.fromCircle(center: pointer, radius: 245);
      canvas.drawOval(beam, Paint()..shader = RadialGradient(colors: [
        (night ? AtelierColor.nightAccent : const Color(0xFFAE7952))
            .withValues(alpha: night ? .095 : .042),
        (night ? AtelierColor.nightAccent : const Color(0xFFAE7952))
            .withValues(alpha: night ? .023 : .010),
        Colors.transparent,
      ], stops: const [0, .48, 1]).createShader(beam));
    }
    // Identical paper-fibre geometry in both themes; the old circular
    // night-only specks read as a starfield rather than a quiet library.
    // All fibres are deterministic and have no idle animation ticker.
    var seed = 0x4A1F02;
    double random() {
      seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF;
      return seed / 4294967296;
    }
    final dust = Paint()
      ..color = night
          ? const Color(0x28EADBC5) : const Color(0x1D705E49)
      ..strokeWidth = .45
      ..strokeCap = StrokeCap.round;
    final count = math.min(46, (size.width / 30).floor());
    for (var i = 0; i < count; i++) {
      final x = random() * size.width;
      final y = random() * size.height;
      final length = 1.0 + random() * 2.1;
      canvas.drawLine(Offset(x, y),
          Offset(x + length, y - length * .13), dust);
    }
  }

  @override
  bool shouldRepaint(covariant _AtelierNightFieldPainter old) =>
      old.pointer != pointer || old.accent != accent ||
      old.night != night;
}
