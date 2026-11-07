import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// A chapter-aware, non-Material seek rail. Movement previews a destination;
/// the expensive chapter jump occurs only after release.
class ChapterScrubber extends StatefulWidget {
  const ChapterScrubber({super.key, required this.index,
    required this.count, required this.ink, required this.accent,
    required this.onCommit, required this.chapterLabel, this.paper});
  final int index, count;
  final Color ink, accent;
  final Color? paper;
  final ValueChanged<int> onCommit;
  final String Function(int) chapterLabel;

  @override
  State<ChapterScrubber> createState() => _ChapterScrubberState();
}

class _ChapterScrubberState extends State<ChapterScrubber> {
  int? _preview;
  int get current => (_preview ?? widget.index).clamp(0, math.max(0, widget.count - 1));

  void _move(Offset point, double width) {
    if (widget.count < 2) return;
    final fraction = ((point.dx - 18) / math.max(1, width - 36)).clamp(0.0, 1.0);
    final target = (fraction * (widget.count - 1)).round();
    if (current != target) HyesMotion.selected(context);
    setState(() => _preview = target);
  }

  void _commit() {
    final target = _preview;
    setState(() => _preview = null);
    if (target != null && target != widget.index) widget.onCommit(target);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = HyesMotion.reduced(context);
    final duration = reduced ? Duration.zero : HyesMotion.fast;
    return Semantics(
    slider: true, label: '章节进度',
    value: '第 ${current + 1} / ${widget.count} 章',
    increasedValue: '第 ${math.min(current + 2, widget.count)} 章',
    decreasedValue: '第 ${math.max(1, current)} 章',
    onIncrease: current + 1 < widget.count ?
        () => widget.onCommit(current + 1) : null,
    onDecrease: current > 0 ?
        () => widget.onCommit(current - 1) : null,
    child: LayoutBuilder(builder: (context, bounds) {
      const bubbleWidth = 172.0;
      const leftInset = 18.0;
      final trackWidth = math.max(1.0, bounds.maxWidth - 2 * leftInset);
      final span = math.max(1, widget.count - 1);
      final thumbX = leftInset + trackWidth * current / span;
      final previewLeft = (thumbX - bubbleWidth / 2)
          .clamp(0.0, math.max(0.0, bounds.maxWidth - bubbleWidth)).toDouble();
      final dragging = _preview != null;
      return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _move(d.localPosition, bounds.maxWidth),
      onTapUp: (_) => _commit(),
      onTapCancel: () => setState(() => _preview = null),
      onHorizontalDragStart: (d) => _move(d.localPosition, bounds.maxWidth),
      onHorizontalDragUpdate: (d) => _move(d.localPosition, bounds.maxWidth),
      onHorizontalDragEnd: (_) => _commit(),
      onHorizontalDragCancel: () => setState(() => _preview = null),
      child: SizedBox(height: 68, child: Stack(children: [
        Positioned(left: 0, right: 0, bottom: 0, height: 44,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: dragging ? 1 : 0),
            duration: duration, curve: HyesMotion.enter,
            builder: (context, activity, _) => CustomPaint(
              painter: _RailPainter(current: current, count: widget.count,
                activity: activity, ink: widget.ink, accent: widget.accent)),
          )),
        AnimatedPositioned(
          duration: duration, curve: HyesMotion.enter,
          top: 0, left: previewLeft, width: bubbleWidth,
          child: IgnorePointer(child: AnimatedOpacity(
            key: const ValueKey('chapter-scrubber-preview-opacity'),
            duration: duration, opacity: dragging ? 1 : 0,
            child: AnimatedSlide(
              duration: duration,
              offset: Offset(0, dragging && !reduced ? 0.0 : .15),
              child: Container(
                height: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: widget.paper ?? Theme.of(context).canvasColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.accent.withValues(alpha: .30)),
                  boxShadow: reduced ? null : [BoxShadow(
                    color: Colors.black.withValues(alpha: .07),
                    blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Text(widget.chapterLabel(current),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    fontFamily: HyesTokens.serifFamily,
                    color: widget.ink)),
              ),
            ),
          )),
        ),
      ])),
    );
    }),
  );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({required this.current, required this.count,
    required this.activity, required this.ink, required this.accent});
  final int current, count;
  final double activity;
  final Color ink, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final span = math.max(1, count - 1), y = size.height / 2;
    final begin = 18.0, end = size.width - 18;
    final x = begin + (end - begin) * current / span;
    canvas.drawLine(Offset(begin, y), Offset(end, y),
        Paint()..color = ink.withValues(alpha: .25)..strokeWidth = 2);
    canvas.drawLine(Offset(begin, y), Offset(x, y),
        Paint()..color = accent..strokeWidth = 2);
    final stride = math.max(1, (count / 32).ceil());
    for (var i = 0; i < count; i += stride) {
      final tx = begin + (end - begin) * i / span;
      canvas.drawLine(Offset(tx, y - 4), Offset(tx, y + 4),
          Paint()..color = ink.withValues(alpha: .30)..strokeWidth = 1);
    }
    if (activity > 0) {
      canvas.drawCircle(Offset(x, y), 10 + 7 * activity,
          Paint()..color = accent.withValues(alpha: .11 * activity));
    }
    canvas.drawCircle(Offset(x, y), 8 + 4 * activity,
        Paint()..color = accent);
    canvas.drawCircle(Offset(x, y), 3 + 2 * activity,
        Paint()..color = const Color(0xFFFFFAF0));
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.current != current || old.count != count ||
      old.activity != activity || old.accent != accent || old.ink != ink;
}
