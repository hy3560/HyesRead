import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// A single spring-driven segmented control for paper and night themes.
class ShelfFilterBar extends StatefulWidget {
  const ShelfFilterBar({super.key, required this.labels,
    required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  State<ShelfFilterBar> createState() => _ShelfFilterBarState();
}

class _ShelfFilterBarState extends State<ShelfFilterBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _underline = AnimationController.unbounded(
    vsync: this, value: widget.selected.toDouble());
  @override
  void didUpdateWidget(covariant ShelfFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    if (HyesMotion.reduced(context)) {
      _underline.value = widget.selected.toDouble();
    } else {
      _underline.animateWith(SpringSimulation(HyesMotion.spring,
        _underline.value, widget.selected.toDouble(), 0));
    }
  }
  @override
  void dispose() {
    _underline.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    final night = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(height: 48, child: LayoutBuilder(builder: (context, box) {
      // The shape, hit targets and selection motion never change with theme.
      const frame = 4.0;
      final largeText =
          MediaQuery.textScalerOf(context).scale(14) > 22;
      final groupWidth =
          widget.labels.length * (largeText ? 118.0 : 102.0) + frame * 2;
      final column = (groupWidth - frame * 2) / widget.labels.length;
      final selection = SizedBox(width: groupWidth, height: 48,
        child: Stack(children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(
            color: night ? const Color(0xFF221F1B)
                : const Color(0xFFE6DFD3),
            borderRadius: BorderRadius.circular(12)))),
        AnimatedBuilder(animation: _underline, builder: (context, _) =>
            Positioned(top: frame, bottom: frame,
              left: (frame + column * _underline.value)
                  .clamp(frame, groupWidth - frame - column),
              child: SizedBox(width: column, child: DecoratedBox(
                decoration: BoxDecoration(
                  color: night ? const Color(0xFF141311)
                      : const Color(0xFFFAF6EE),
                  borderRadius: BorderRadius.circular(9)))))),
        Row(children: [
          const SizedBox(width: frame),
          for (var i = 0; i < widget.labels.length; i++)
            SizedBox(width: column, child: Semantics(button: true, selected: i == widget.selected,
              label: widget.labels[i],
              child: Material(type: MaterialType.transparency,
                child: InkWell(key: ValueKey('shelf-filter-$i'),
                  onTap: () {
                    HyesMotion.selected(context);
                    widget.onSelect(i);
                  },
                  child: Center(child: Text(widget.labels[i], maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14,
                      fontWeight: i == widget.selected
                          ? FontWeight.w600 : FontWeight.w400,
                      color: i == widget.selected ? t.ink : t.secondary))),
                ),
              ),
            )),
          const SizedBox(width: frame),
        ]),
      ]));
      return groupWidth > box.maxWidth
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: selection,
            )
          : selection;
    }));
  }
}
