import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design/motion.dart';
import 'atelier_widgets.dart';

/// The desktop forest rail folded into a phone-width bookend, using the same
/// four navigation glyphs and color semantics rather than a second UI theme.
/// Each destination keeps a 48dp+ hit box, including at 200% text scaling.
class PaperDock extends StatelessWidget {
  const PaperDock({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.icons,
    required this.labels,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IconData> icons;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final rail = AtelierColor.rail(context);
    const ink = AtelierColor.nightInk;
    const accent = AtelierColor.nightAccent;
    final secondary = ink.withValues(alpha: .72);
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final reduceMotion = HyesMotion.reduced(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: rail,
        border: Border(top: BorderSide(color: ink.withValues(alpha: .1))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 3),
        child: SizedBox(
          height: 58,
          child: Stack(children: [
            Positioned(left: 0, right: 0, top: 0,
              child: SizedBox(height: 2,
                child: _SpringUnderline(index: selectedIndex,
                  count: icons.length, color: accent,
                  reduced: reduceMotion))),
            Row(children: [
            for (var i = 0; i < icons.length; i++)
              Expanded(child: Semantics(
                button: true,
                selected: selectedIndex == i,
                label: labels[i],
                child: Tooltip(
                  message: labels[i],
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: ValueKey('paper-dock-$i'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        HyesMotion.selected(context);
                        onSelected(i);
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          _BounceIcon(selected: selectedIndex == i,
                            reduced: reduceMotion,
                            icon: icons[i],
                            color: selectedIndex == i
                                ? accent : secondary),
                          if (!compact) ...[
                            const SizedBox(height: 4),
                            Text(labels[i], maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                color: selectedIndex == i
                                    ? ink : secondary,
                                fontWeight: selectedIndex == i
                                    ? FontWeight.w700 : FontWeight.w500,
                              )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              )),
          ]),
          ]),
        ),
      ),
    );
  }
}

class _BounceIcon extends StatefulWidget {
  const _BounceIcon({required this.selected, required this.reduced,
    required this.icon, required this.color});
  final bool selected, reduced;
  final IconData icon;
  final Color color;
  @override
  State<_BounceIcon> createState() => _BounceIconState();
}

class _BounceIconState extends State<_BounceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 170));

  @override
  void didUpdateWidget(covariant _BounceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (widget.selected && !oldWidget.selected) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.scale(
      scale: widget.reduced ? 1 : 1 +
          .035 * mathSinBump(_controller.value),
      child: child),
    child: Icon(widget.icon, size: 23, color: widget.color),
  );
}

double mathSinBump(double t) => t < .48 ? t / .48 : (1 - t) / .52;

class _SpringUnderline extends StatefulWidget {
  const _SpringUnderline({required this.index, required this.count,
    required this.color, required this.reduced});
  final int index, count;
  final Color color;
  final bool reduced;
  @override
  State<_SpringUnderline> createState() => _SpringUnderlineState();
}

class _SpringUnderlineState extends State<_SpringUnderline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this, value: widget.index.toDouble());

  @override
  void didUpdateWidget(covariant _SpringUnderline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduced) {
      _controller.stop();
      _controller.value = widget.index.toDouble();
    } else if (widget.index != oldWidget.index) {
      _controller.animateWith(SpringSimulation(HyesMotion.spring,
        _controller.value, widget.index.toDouble(), 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(animation: _controller,
      builder: (context, _) => Stack(children: [
        Positioned(top: 0,
          left: ((box.maxWidth / widget.count) * (_controller.value + .5) - 11)
              .clamp(0, box.maxWidth - 22),
          child: Container(width: 22, height: 2,
            decoration: BoxDecoration(color: widget.color,
              borderRadius: BorderRadius.circular(1)))),
      ])),
  );
}
