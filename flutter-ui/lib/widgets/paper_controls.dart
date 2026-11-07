import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../ui/app_language.dart';

/// Brand-consistent 48dp slider, painted track and a 1.3x pressed thumb.
/// There is no Material Slider widget or its default active indicator.
class PaperSlider extends StatefulWidget {
  const PaperSlider({super.key, required this.value, required this.min,
    required this.max, required this.onChanged, this.label = '',
    this.step, this.enabled = true});
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String label;
  final double? step;
  final bool enabled;
  @override
  State<PaperSlider> createState() => _PaperSliderState();
}

class _PaperSliderState extends State<PaperSlider> {
  bool _touching = false;
  double get _range => widget.max - widget.min;
  void _update(double x, double width) {
    if (!widget.enabled || width <= 36 || _range <= 0) return;
    final unit = ((x - 18) / (width - 36)).clamp(0.0, 1.0);
    var value = widget.min + unit * _range;
    if (widget.step != null && widget.step! > 0) {
      value = widget.min +
          ((value - widget.min) / widget.step!).round() * widget.step!;
    }
    final next = value.clamp(widget.min, widget.max).toDouble();
    if ((next - widget.value).abs() > .00001) {
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    final amount = _range > 0
        ? ((widget.value - widget.min) / _range).clamp(0.0, 1.0) : 0.0;
    final increment = widget.step ?? _range / 16;
    final larger = (widget.value + increment).clamp(widget.min, widget.max);
    final smaller = (widget.value - increment).clamp(widget.min, widget.max);
    return Semantics(slider: true, enabled: widget.enabled, label: widget.label,
      value: widget.value.toStringAsFixed(1),
      increasedValue: larger.toStringAsFixed(1),
      decreasedValue: smaller.toStringAsFixed(1),
      onIncrease: widget.enabled ? () => widget.onChanged(
        larger) : null,
      onDecrease: widget.enabled ? () => widget.onChanged(
        smaller) : null,
      child: LayoutBuilder(builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (details) {
          setState(() => _touching = true);
          _update(details.localPosition.dx, constraints.maxWidth);
        } : null,
        onTapUp: widget.enabled ? (_) => setState(() => _touching = false) : null,
        onTapCancel: widget.enabled ? () => setState(() => _touching = false) : null,
        onHorizontalDragStart: widget.enabled
          ? (_) => setState(() => _touching = true) : null,
        onHorizontalDragUpdate: widget.enabled ? (details) =>
          _update(details.localPosition.dx, constraints.maxWidth) : null,
        onHorizontalDragEnd: widget.enabled
          ? (_) => setState(() => _touching = false) : null,
        child: SizedBox(height: 48, width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _touching && !HyesMotion.reduced(context) ? 1.3 : 1),
            duration: HyesMotion.duration(context, HyesMotion.fast),
            builder: (context, scale, _) => CustomPaint(
              painter: _PaperSliderPainter(
                amount: amount, tokens: t, thumbScale: scale)),
          ),
        ),
      )),
    );
  }
}

class _PaperSliderPainter extends CustomPainter {
  const _PaperSliderPainter({required this.amount, required this.tokens,
    required this.thumbScale});
  final double amount, thumbScale;
  final HyesTokens tokens;
  @override
  void paint(Canvas canvas, Size size) {
    final length = (size.width - 36).clamp(0.0, double.infinity);
    final y = size.height / 2;
    final x = 18 + length * amount;
    final line = Paint()..strokeWidth = 2..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(18, y), Offset(size.width - 18, y),
      line..color = tokens.divider);
    canvas.drawLine(Offset(18, y), Offset(x, y),
      line..color = tokens.vermilion);
    canvas.drawCircle(Offset(x, y), 9 * thumbScale,
      Paint()..color = tokens.raised);
    canvas.drawCircle(Offset(x, y), 9 * thumbScale,
      Paint()..color = tokens.vermilion
        ..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant _PaperSliderPainter old) =>
      old.amount != amount || old.thumbScale != thumbScale ||
      old.tokens != tokens;
}

class PaperToggle extends StatelessWidget {
  const PaperToggle({super.key, required this.label,
    required this.value, required this.onChanged, this.subtitle});
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return Semantics(toggled: value, button: true, label: label,
      child: Material(type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('paper-toggle-$label'),
          onTap: () {
            HyesMotion.selected(context);
            onChanged(!value);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: t.body),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: t.caption),
                  ],
                ],
              )),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: HyesMotion.duration(context, HyesMotion.base),
                width: 48, height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? t.vermilion : t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: value ? t.vermilion : t.divider),
                ),
                child: AnimatedAlign(
                  duration: HyesMotion.duration(context, HyesMotion.base),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: value ? Colors.white : t.secondary,
                      shape: BoxShape.circle)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Single-line text choices with an underline; not default M3 chips.
class PaperChoiceStrip extends StatelessWidget {
  const PaperChoiceStrip({super.key, required this.labels,
    required this.selected, required this.onSelect});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(child: Semantics(button: true,
          selected: i == selected, label: labels[i],
          child: Material(type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('paper-choice-${labels[i]}'),
              onTap: () {
                HyesMotion.selected(context);
                onSelect(i);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                    width: i == selected ? 2 : 1,
                    color: i == selected ? t.vermilion : t.divider))),
                child: Text(labels[i], maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13,
                    color: i == selected ? t.ink : t.secondary,
                    fontWeight: i == selected
                        ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
          ),
        )),
    ]);
  }
}

class PaperThemeSamples extends StatelessWidget {
  const PaperThemeSamples({super.key, required this.selected,
    required this.onSelect, this.options = const ['sepia', 'eye', 'gray', 'dark']});
  final String selected;
  final ValueChanged<String> onSelect;
  final List<String> options;

  static const shades = <String, (String, Color, Color)>{
    'sepia': ('纸', Color(0xFFF4EEE2), Color(0xFF2B2620)),
    'eye': ('护眼', Color(0xFFE3EDD6), Color(0xFF2A3322)),
    'gray': ('灰', Color(0xFFE6E4E0), Color(0xFF2B2B2B)),
    'dark': ('夜', Color(0xFF141311), Color(0xFFC9C1B2)),
    'light': ('白', Color(0xFFFFFDFA), Color(0xFF2B2620)),
  };

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    final copy = HyesCopy(HyesLanguageScope.of(context));
    final english = copy.isEnglish;
    final fontScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final cellHeight = 84.0 + (fontScale - 1).clamp(0.0, 2.0) * 26;
    return Wrap(spacing: 14, runSpacing: 6, children: [
      for (final value in options)
        Semantics(button: true, selected: selected == value,
          label: english ? '${copy.tr(shades[value]!.$1)} paper'
              : '${shades[value]!.$1}色阅读纸张',
          child: Material(type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('paper-theme-$value'),
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HyesMotion.selected(context);
                onSelect(value);
              },
              child: SizedBox(width: 56, height: cellHeight,
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: shades[value]!.$2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected == value ? t.vermilion : t.divider,
                          width: selected == value ? 2 : 1)),
                      child: Center(child: Text(english ? 'A' : '文', style: TextStyle(
                        color: shades[value]!.$3,
                        fontFamily: HyesTokens.serifFamily, fontSize: 19))),
                    ),
                    const SizedBox(height: 6),
                    Text(copy.tr(shades[value]!.$1),
                      style: TextStyle(color: selected == value
                          ? t.vermilion : t.secondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
