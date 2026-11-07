import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/book_entry.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../ui/app_language.dart';
import 'book_cover.dart';
import 'ink_stamp.dart';
import 'rive_ink_waves.dart';

/// A one-shot, nonpersistent celebration after the repository confirms a new
/// import. Never shown for duplicates or failed copies.
class ImportArrival extends StatefulWidget {
  const ImportArrival({super.key, required this.book, required this.onFinished});
  final BookEntry book;
  final VoidCallback onFinished;
  @override
  State<ImportArrival> createState() => _ImportArrivalState();
}

class _ImportArrivalState extends State<ImportArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 950));
  bool _stamped = false;
  bool _finished = false;

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_stamped && _controller.value >= .67) {
        _stamped = true;
        HyesMotion.stamped(context);
      }
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _finish();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // This overlay is decorative: never delay a user who disabled motion.
      if (HyesMotion.reduced(context)) {
        _finish();
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (HyesMotion.reduced(context) && _controller.isAnimating) {
      _controller.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return IgnorePointer(child: AnimatedBuilder(animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        final reduced = HyesMotion.reduced(context);
        final arrival = Curves.easeOutBack.transform((v / .62).clamp(0, 1));
        final stamp = Curves.easeOutCubic.transform(
            ((v - .63) / .27).clamp(0, 1));
        final exit = ((1 - v) / .12).clamp(0.0, 1.0);
        return Opacity(opacity: exit,
          child: ColoredBox(color: t.background.withValues(alpha: .93),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 170, height: 255,
                  child: Transform.translate(
                    offset: reduced ? Offset.zero
                        : Offset(0, -40 * (1 - arrival)),
                    child: Transform.scale(
                      scale: reduced ? 1 : .6 + .4 * arrival,
                      child: Stack(clipBehavior: Clip.none, children: [
                        // Book and seal share one transform. The seal is
                        // inset on the cover, never outside its bottom edge.
                        BookCover(book: widget.book, width: 170,
                          height: 255, showSeal: false),
                        // A single Rive ripple follows the same corner.
                        Positioned(right: -7, bottom: -9,
                          child: RiveInkWaves(
                            impression: _stamped ? 1 : 0, size: 100)),
                        Positioned(right: 18, bottom: 16,
                          child: Opacity(opacity: stamp,
                            child: Transform.scale(
                              scale: reduced ? 1 : 1.2 - .2 * stamp,
                              child: Transform.rotate(angle: reduced ? 0 :
                                (-8 + 4 * stamp) * math.pi / 180,
                                child: const InkStamp(size: 50))))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Text(HyesCopy(HyesLanguageScope.of(context)).tr('上架了。'),
                  style: t.title),
              ])),
          ),
        );
      },
    ));
  }
}
