import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// The single recurring brand sign; no glass or decorative icon circle.
class InkStamp extends StatelessWidget {
  const InkStamp({super.key, this.size = 20, this.character = '阅',
    this.filled = false});
  final double size;
  final String character;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return Semantics(label: '阅印章', image: true,
      child: Container(width: size, height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? t.vermilion : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: t.vermilion,
            width: size > 32 ? 2 : 1.5),
        ),
        child: Text(character, maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: HyesTokens.serifFamily,
            color: filled ? Colors.white : t.vermilion,
            height: 1, fontSize: size * .64, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// One-shot physical seal impression; repeat by changing the key.
class InkStampArrival extends StatefulWidget {
  const InkStampArrival({super.key, this.size = 56});
  final double size;
  @override
  State<InkStampArrival> createState() => _InkStampArrivalState();
}

class _InkStampArrivalState extends State<InkStampArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 260));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!HyesMotion.reduced(context)) HyesMotion.stamped(context);
      _controller.forward();
    });
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final reduced = HyesMotion.reduced(context);
      final v = Curves.easeOutCubic.transform(_controller.value);
      return Opacity(opacity: reduced ? v : v * .92,
        child: Transform.rotate(angle: reduced ? 0 :
          (-8 + 4 * v) * math.pi / 180,
          child: Transform.scale(scale: reduced ? 1 : 1.6 - .6 * v,
            child: child)));
    },
    child: InkStamp(size: widget.size),
  );
}
