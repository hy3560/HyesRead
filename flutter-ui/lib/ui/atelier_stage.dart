import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/book_entry.dart';
import '../design/motion.dart';
import '../widgets/book_cover.dart';

/// Shared 3D cover stage. Pointer input drives the tilt and reflection;
/// imported EPUB covers provide the ambient colour.
class AtelierStage extends StatefulWidget {
  const AtelierStage({
    super.key,
    required this.book,
    required this.coverWidth,
    this.hero = false,
    this.editorial = false,
    this.onOpen,
  });

  final BookEntry book;
  final double coverWidth;
  final bool hero;
  final bool editorial;
  final VoidCallback? onOpen;

  @override
  State<AtelierStage> createState() => _AtelierStageState();
}

class _AtelierStageState extends State<AtelierStage>
    with TickerProviderStateMixin {
  late Future<Color> _coverTint;
  @override
  void initState() {
    super.initState();
    _coverTint = CoverColorCache.read(widget.book);
  }
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 310),
    reverseDuration: const Duration(milliseconds: 360),
  );
  late final AnimationController _follow = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 150),
  );
  late final AnimationController _arrival = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 840),
  );
  bool _arrivalStarted = false;
  Animation<Offset> _position =
      const AlwaysStoppedAnimation<Offset>(Offset.zero);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrivalStarted) return;
    _arrivalStarted = true;
    // Never launch a decorative ticker for users requesting less motion.
    if (HyesMotion.reduced(context)) {
      _arrival.value = 1;
    } else {
      _arrival.forward();
    }
  }

  void _move(Offset target) {
    if (HyesMotion.reduced(context)) return;
    final clamped = Offset(
      target.dx.clamp(-1.0, 1.0),
      target.dy.clamp(-1.0, 1.0),
    );
    if ((clamped - _position.value).distance < .018) return;
    _position = Tween<Offset>(
      begin: _position.value, end: clamped,
    ).animate(CurvedAnimation(parent: _follow,
      curve: Curves.easeOutCubic));
    _follow.forward(from: 0);
  }

  void _leave() {
    if (HyesMotion.reduced(context)) return;
    _move(Offset.zero);
    _hover.reverse();
  }

  @override
  void didUpdateWidget(covariant AtelierStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      _coverTint = CoverColorCache.read(widget.book);
      _follow.stop();
      _hover.value = 0;
      _position = const AlwaysStoppedAnimation<Offset>(Offset.zero);
      if (!HyesMotion.reduced(context)) _arrival.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hover.dispose();
    _follow.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color>(
      future: _coverTint,
      builder: (context, snapshot) => _theatre(
        snapshot.data ?? coverPaletteFor(widget.book.title).background),
    );
  }

  Widget _theatre(Color coverColor) {
    final muted = Color.lerp(const Color(0xFFB4C4AD),
      coverColor, .15)!;
    final ground = Color.lerp(const Color(0xFFE5DEC9),
      coverColor, .1)!;
    final reduced = HyesMotion.reduced(context);
    final motion = Listenable.merge([_hover, _follow, _arrival]);
    return LayoutBuilder(builder: (context, bounds) {
      final width = math.min(widget.coverWidth,
          math.min(bounds.maxWidth * (widget.editorial ? .94 : .64),
            math.max(100.0, (bounds.maxHeight -
                (widget.editorial ? 24 : 75)) * 540 / 760)));
      final height = width * 760 / 540;
      return ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: widget.editorial ? null : RadialGradient(
              center: const Alignment(-.02, -.16),
              radius: 1.12,
              colors: [ground, muted],
            ),
          ),
          child: MouseRegion(
            key: const ValueKey('atelier-stage-hover'),
            cursor: widget.onOpen == null
                ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) {
              if (!HyesMotion.reduced(context)) _hover.forward();
            },
            onHover: (event) {
              final x = (event.localPosition.dx /
                  math.max(1, bounds.maxWidth) - .5) * 2;
              final y = (event.localPosition.dy /
                  math.max(1, bounds.maxHeight) - .5) * 2;
              _move(Offset(x, y));
            },
            onExit: (_) => _leave(),
            child: AnimatedBuilder(
              animation: motion,
              builder: (context, _) {
                final t = reduced ? 0.0 : _hover.value;
                final settle = reduced ? 1.0 :
                  Curves.easeOutCubic.transform(_arrival.value);
                final arrive = 1 - settle;
                final p = reduced ? Offset.zero : _position.value;
                final x = p.dx * t, y = p.dy * t;
                final bookMatrix = Matrix4.identity()
                  ..setEntry(3, 2, .00085)
                  ..rotateY(-.12 - arrive * .18 + x * .125)
                  ..rotateX(arrive * .08 - y * .09)
                  ..rotateZ(-.028 + arrive * .025 + x * .01);
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: IgnorePointer(child:
                      CustomPaint(painter: _AtelierAmbientPainter(
                        tint: coverColor,
                        focus: Offset(.51 + x * .17, .40 + y * .12),
                        strength: t,
                      )))),
                    if (widget.editorial)
                      Positioned.fill(child: IgnorePointer(
                        child: Transform.translate(
                          offset: Offset(-x * 10, -y * 6),
                          child: CustomPaint(
                            painter: _AtelierGalleryFramePainter(
                              tint: coverColor,
                              night: Theme.of(context).brightness ==
                                  Brightness.dark,
                              presence: settle,
                            ),
                          ),
                        ),
                      )),
                    if (!widget.editorial) Positioned(
                      left: bounds.maxWidth * .075,
                      right: bounds.maxWidth * .075,
                      top: bounds.maxHeight * .085,
                      bottom: bounds.maxHeight * .13,
                      child: IgnorePointer(child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(260),
                            bottom: Radius.circular(9)),
                          border: Border.all(color:
                            Colors.white.withValues(alpha: .44)),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFF7F0DF).withValues(alpha: .69),
                              const Color(0xFFEDE7D5).withValues(alpha: .1),
                            ]),
                        ),
                      )),
                    ),
                    if (!widget.editorial) Positioned.fill(child: IgnorePointer(child:
                      Transform.translate(
                        offset: Offset(x * -9, y * -6),
                        child: CustomPaint(
                          painter: const _AtelierVinePainter())))),
                    Positioned(
                      bottom: math.max(24, bounds.maxHeight * .10) - 4,
                      left: bounds.maxWidth * .22,
                      right: bounds.maxWidth * .17,
                      height: 20 + t * 6,
                      child: IgnorePointer(child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF32472E)
                                  .withValues(alpha: .16 + t * .08),
                              blurRadius: 21 + t * 9,
                              spreadRadius: 3 + t * 2,
                            ),
                          ],
                        ),
                      )),
                    ),
                    Center(child: Transform.translate(
                      offset: Offset(x * 13 - arrive * 12,
                        arrive * 30 - t * 12 + y * 5),
                      child: Transform(
                        key: const ValueKey('atelier-book-transform'),
                        alignment: Alignment.center,
                        transform: bookMatrix,
                        child: Semantics(
                          button: widget.onOpen != null,
                          label: widget.book.title,
                          child: GestureDetector(
                            key: const ValueKey('atelier-stage-book'),
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onOpen,
                            child: SizedBox(width: width + 12, height: height,
                              child: Stack(clipBehavior: Clip.none, children: [
                                Positioned(
                                  left: 9, right: 0, top: 3, bottom: 5,
                                  child: CustomPaint(
                                    painter: const _BookPagesPainter(),
                                  ),
                                ),
                                Positioned(
                                  left: 0, top: 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF23352A)
                                              .withValues(alpha: .25 + .16 * t),
                                          blurRadius: 26 + 15 * t,
                                          offset: Offset(18 + x * 6,
                                            23 + t * 9),
                                        ),
                                      ],
                                    ),
                                    child: SizedBox(
                                      width: width, height: height,
                                      child: widget.hero
                                          ? Hero(
                                              tag: 'hyes-cover-${widget.book.id}',
                                              child: BookCover(
                                                book: widget.book,
                                                width: width,
                                                height: height,
                                                elevation: false))
                                          : BookCover(
                                              book: widget.book,
                                              width: width,
                                              height: height,
                                              elevation: false),
                                    ),
                                  ),
                                ),
                                if (t > .005) Positioned(
                                  left: 0, top: 0, width: width, height: height,
                                  child: IgnorePointer(child: CustomPaint(
                                    key: const ValueKey('atelier-specular-layer'),
                                    painter: _AtelierVarnishPainter(
                                      cursor: Offset(x, y), intensity: t),
                                  )),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    )),
                    if (!widget.editorial) Positioned(
                      top: 20, right: 24,
                      child: IgnorePointer(child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF5C785E)
                              .withValues(alpha: .22))),
                        alignment: Alignment.center,
                        child: Text(widget.book.format.toUpperCase(),
                          style: const TextStyle(fontSize: 8,
                            letterSpacing: -.25,
                            color: Color(0xFF566953))),
                      )),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// Cover highlight follows the pointer and fades when hovering ends.
class _AtelierVarnishPainter extends CustomPainter {
  const _AtelierVarnishPainter({
    required this.cursor, required this.intensity,
  });

  final Offset cursor;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intensity <= 0) return;
    final width = size.width;
    final center = width *
        (.46 + cursor.dx * .22 + cursor.dy * .055).clamp(.12, .85);
    final sweep = width * .24;
    final diagonal = width * .12;
    final shape = Path()
      ..moveTo(center - sweep, 0)
      ..lineTo(center + sweep * .36, 0)
      ..lineTo(center + sweep * .36 + diagonal, size.height)
      ..lineTo(center - sweep + diagonal, size.height)
      ..close();
    final brush = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: .042 * intensity),
          Colors.white.withValues(alpha: .18 * intensity),
          Colors.white.withValues(alpha: .015 * intensity),
          Colors.transparent,
        ],
        stops: const [0, .25, .51, .73, 1],
      ).createShader(Offset.zero & size)
      ..blendMode = BlendMode.screen;
    canvas.drawPath(shape, brush);
    canvas.drawLine(
      Offset(center + sweep * .36, 0),
      Offset(center + sweep * .36 + diagonal, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: .14 * intensity)
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(covariant _AtelierVarnishPainter old) =>
      old.cursor != cursor || old.intensity != intensity;
}

/// A finite secondary stage for editorial metadata and recent books.
class AtelierEditorialEnter extends StatefulWidget {
  const AtelierEditorialEnter({
    super.key, required this.child, this.delay = .12,
    this.duration = const Duration(milliseconds: 790),
    this.horizontalTravel = 20,
  });
  final Widget child;
  final double delay;
  final Duration duration;
  final double horizontalTravel;
  @override
  State<AtelierEditorialEnter> createState() => _AtelierEditorialEnterState();
}

class _AtelierEditorialEnterState extends State<AtelierEditorialEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this, duration: widget.duration,
  );
  bool _launched = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (HyesMotion.reduced(context)) {
      _entrance.value = 1;
    } else if (!_launched) {
      _entrance.forward();
    }
    _launched = true;
  }
  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _entrance,
    child: widget.child,
    builder: (context, child) {
      final t = HyesMotion.reduced(context) ? 1.0 :
          ((_entrance.value - widget.delay) / (1 - widget.delay))
              .clamp(0.0, 1.0);
      final remaining = 1 - Curves.easeOutCubic.transform(t);
      return Opacity(
        opacity: Curves.easeOutQuad.transform(t),
        child: Transform.translate(
          offset: Offset(widget.horizontalTravel * remaining,
            11 * remaining),
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0006)
              ..rotateY(-.025 * remaining),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Book mount and reflected colour, shared by both appearance themes.
class _AtelierGalleryFramePainter extends CustomPainter {
  const _AtelierGalleryFramePainter({
    required this.tint, required this.night, required this.presence,
  });
  final Color tint;
  final bool night;
  final double presence;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || presence <= 0) return;
    // A single archival mount in both palettes. The nested mat/rebate
    // gives the physical cover an intelligible place in space instead of
    // a light-theme rectangle or a disappearing dark-theme halo.
    final mount = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .026, size.height * .024,
          size.width * .948, size.height * .928),
      const Radius.circular(7));
    final warm = night ? const Color(0xFF302A24)
        : const Color(0xFFE8E0D1);
    final cool = night ? const Color(0xFF222521)
        : const Color(0xFFDCDACE);
    canvas.drawRRect(mount, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          warm.withValues(alpha: .94 * presence),
          cool.withValues(alpha: .81 * presence),
        ],
      ).createShader(mount.outerRect));
    canvas.drawRRect(mount, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = (night ? const Color(0xFFAB9678)
          : const Color(0xFF897E69)).withValues(alpha: .38 * presence));
    final rebate = RRect.fromRectAndRadius(
        mount.outerRect.deflate(8), const Radius.circular(3));
    canvas.drawRRect(rebate, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .65
      ..color = (night ? const Color(0xFFBBAB90)
          : const Color(0xFF7D715F)).withValues(alpha: .23 * presence));
    final base = night
        ? const Color(0xFFC6B39B) : const Color(0xFF687363);
    final light = Color.lerp(
        night ? const Color(0xFFC7AB8F) : const Color(0xFFB3A589),
        tint, .19)!;
    final halo = Rect.fromCenter(
      center: Offset(size.width * .50, size.height * .48),
      width: size.width * .94, height: size.height * .80);
    canvas.drawOval(halo, Paint()..shader = RadialGradient(
      colors: [
        light.withValues(alpha: (night ? .075 : .068) * presence),
        light.withValues(alpha: (night ? .025 : .023) * presence),
        Colors.transparent,
      ], stops: const [0, .49, 1],
    ).createShader(halo));

    Path niche(double inset) {
      final left = size.width * (.075 + inset);
      final right = size.width * (.925 - inset);
      final middle = (left + right) / 2;
      final radius = (right - left) / 2;
      final top = size.height * (.085 + inset * .27);
      final foot = size.height * .835;
      return Path()
        ..moveTo(left, foot)
        ..lineTo(left, top + radius * .91)
        ..cubicTo(left, top + radius * .36,
            middle - radius * .57, top, middle, top)
        ..cubicTo(middle + radius * .57, top,
            right, top + radius * .36, right, top + radius * .91)
        ..lineTo(right, foot);
    }

    canvas.drawPath(niche(0), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..color = base.withValues(alpha: (night ? .22 : .20) * presence));
    canvas.drawPath(niche(.038), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = base.withValues(alpha: .09 * presence));
    final horizon = size.height * .85;
    canvas.drawLine(
      Offset(size.width * .035, horizon),
      Offset(size.width * .965, horizon),
      Paint()
        ..color = base.withValues(alpha: .19 * presence)
        ..strokeWidth = .85,
    );
    // Four short registration notches echo bookbinding tooling rather than
    // decorative stars. Their geometry does not change with theme.
    final engraving = Paint()
      ..color = base.withValues(alpha: .40 * presence)
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.square;
    for (final x in [.12, .88]) {
      final px = size.width * x;
      canvas.drawLine(Offset(px, size.height * .027),
          Offset(px, size.height * .052), engraving);
      canvas.drawLine(Offset(px, size.height * .925),
          Offset(px, size.height * .948), engraving);
    }
    for (final side in [.055, .945]) {
      canvas.drawLine(
        Offset(size.width * side, horizon - 6),
        Offset(size.width * side, horizon + 6),
        Paint()
          ..color = base.withValues(alpha: .24 * presence)
          ..strokeWidth = .85,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtelierGalleryFramePainter old) =>
      old.tint != tint || old.night != night ||
      old.presence != presence;
}

class _AtelierAmbientPainter extends CustomPainter {
  const _AtelierAmbientPainter({
    required this.tint, required this.focus, required this.strength,
  });
  final Color tint;
  final Offset focus;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = RadialGradient(
      center: Alignment(focus.dx * 2 - 1, focus.dy * 2 - 1),
      radius: .96,
      colors: [
        tint.withValues(alpha: .12 + strength * .18),
        tint.withValues(alpha: .026),
        Colors.transparent,
      ],
      stops: const [0, .57, 1],
    ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _AtelierAmbientPainter old) =>
      old.tint != tint || old.focus != focus || old.strength != strength;
}

class _BookPagesPainter extends CustomPainter {
  const _BookPagesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..shader = const LinearGradient(colors: [
        Color(0xFFF1EBDC), Color(0xFFC2B7A2), Color(0xFFF7F1E4),
      ]).createShader(rect));
    final stroke = Paint()..strokeWidth = .55
      ..color = const Color(0x9B8F8672);
    for (var y = 2.0; y < size.height; y += 4.6) {
      canvas.drawLine(Offset(size.width - 10, y),
        Offset(size.width - 1, y + .2), stroke);
    }
    canvas.drawLine(Offset(size.width - 1, 4),
      Offset(size.width - 1, size.height - 4),
      Paint()..color = const Color(0xFF6B6558)..strokeWidth = 1.3);
  }

  @override
  bool shouldRepaint(covariant _BookPagesPainter old) => false;
}

class _AtelierVinePainter extends CustomPainter {
  const _AtelierVinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.translate(size.width * -.07, size.height * .88);
    final s = math.min(size.width / 520, size.height / 580);
    canvas.scale(s);
    final stem = Paint()
      ..color = const Color(0x60839979)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final vine = Path()
      ..moveTo(0, 40)
      ..cubicTo(100, -30, 120, -220, 220, -430);
    canvas.drawPath(vine, stem);
    for (var i = 0; i < 9; i++) {
      final y = -24.0 - i * 50;
      final x = 27.0 + i * 23;
      final side = i.isEven ? -1.0 : 1.0;
      final leaf = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + side * 55, y - 59,
          x + side * 81, y - 42)
        ..quadraticBezierTo(x + side * 56, y - 3, x, y);
      canvas.drawPath(leaf, Paint()
        ..color = Color.lerp(const Color(0x6083987F),
          const Color(0x44768D76), i / 9)!);
      canvas.drawPath(leaf, stem);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AtelierVinePainter old) => false;
}

/// Finite, input-driven tactile elevation for editorial actions. It leaves the
/// button's keyboard, screen-reader, and click handling to the actual child.
class AtelierHoverLift extends StatefulWidget {
  const AtelierHoverLift({
    super.key, required this.child, this.elevation = 3,
    this.shadow = false,
  });
  final Widget child;
  final double elevation;
  final bool shadow;

  @override
  State<AtelierHoverLift> createState() => _AtelierHoverLiftState();
}

class _AtelierHoverLiftState extends State<AtelierHoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final elevated = _hovered && !HyesMotion.reduced(context);
    return MouseRegion(
      key: const ValueKey('atelier-hover-lift-region'),
      onEnter: (_) {
        if (!HyesMotion.reduced(context)) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: HyesMotion.duration(context, const Duration(milliseconds: 230)),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0, elevated ? -widget.elevation : 0, 0),
        decoration: widget.shadow ? BoxDecoration(
          boxShadow: elevated ? [
            BoxShadow(
              color: const Color(0xFF2A4633).withValues(alpha: .17),
              blurRadius: 23, offset: const Offset(0, 11),
            ),
          ] : null,
        ) : null,
        child: widget.child,
      ),
    );
  }
}

/// Magnetic motion matches the uploaded HTML's pointer-following action.
/// The actual click and keyboard semantics remain owned by [child].
class AtelierMagneticButton extends StatefulWidget {
  const AtelierMagneticButton({
    super.key, required this.child, this.strength = .16,
  });
  final Widget child;
  final double strength;

  @override
  State<AtelierMagneticButton> createState() =>
      _AtelierMagneticButtonState();
}

class _AtelierMagneticButtonState extends State<AtelierMagneticButton> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: const ValueKey('atelier-magnetic-target'),
    onHover: (event) {
      if (HyesMotion.reduced(context)) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final local = box.globalToLocal(event.position);
      final target = Offset(
        (local.dx - box.size.width * .5) * widget.strength,
        (local.dy - box.size.height * .5) * widget.strength * 1.3,
      );
      if ((target - _offset).distance > .65) {
        setState(() => _offset = target);
      }
    },
    onExit: (_) {
      if (_offset != Offset.zero) setState(() => _offset = Offset.zero);
    },
    child: AnimatedContainer(
      key: const ValueKey('atelier-magnetic-motion'),
      duration: HyesMotion.duration(
        context, const Duration(milliseconds: 260)),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(
        HyesMotion.reduced(context) ? 0 : _offset.dx,
        HyesMotion.reduced(context) ? 0 : _offset.dy, 0),
      child: widget.child,
    ),
  );
}

/// Lightweight pointer tilt for the actual cover thumbnails in the shelf.
/// Unlike the featured stage it does not allocate another ambient painter.
class AtelierCoverTilt extends StatefulWidget {
  const AtelierCoverTilt({super.key, required this.child});
  final Widget child;

  @override
  State<AtelierCoverTilt> createState() => _AtelierCoverTiltState();
}

class _AtelierCoverTiltState extends State<AtelierCoverTilt> {
  Offset _tilt = Offset.zero;

  void _update(Offset offset) {
    if (HyesMotion.reduced(context)) return;
    if ((offset - _tilt).distance < .04) return;
    setState(() => _tilt = offset);
  }

  @override
  Widget build(BuildContext context) {
    final tilt = HyesMotion.reduced(context) ? Offset.zero : _tilt;
    return MouseRegion(
      onHover: (event) {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final at = box.globalToLocal(event.position);
        _update(Offset(
          ((at.dx / math.max(1, box.size.width)) - .5).clamp(-.5, .5),
          ((at.dy / math.max(1, box.size.height)) - .5).clamp(-.5, .5),
        ));
      },
      onExit: (_) => _update(Offset.zero),
      child: AnimatedContainer(
        key: const ValueKey('atelier-mini-cover-motion'),
        duration: HyesMotion.duration(
          context, const Duration(milliseconds: 340)),
        curve: Curves.easeOutCubic,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .001)
          ..rotateY(tilt.dx * .28)
          ..rotateX(-tilt.dy * .20),
        child: widget.child,
      ),
    );
  }
}
