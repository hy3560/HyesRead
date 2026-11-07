import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Miniature sheets, not a segmented Material control or a boxed card.
/// Automatic mode splits the two actual theme colors diagonally.
class AppearancePaper extends StatelessWidget {
  const AppearancePaper({super.key, required this.label,
    required this.mode, required this.selected, required this.onTap,
    required this.onTapDown});
  final String label;
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<TapDownDetails> onTapDown;

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    return Semantics(button: true, selected: selected, label: '$label外观',
      child: Material(type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('appearance-${mode.name}'),
          borderRadius: BorderRadius.circular(4),
          onTapDown: onTapDown,
          onTap: () {
            HyesMotion.selected(context);
            onTap();
          },
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 102),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 70,
                decoration: BoxDecoration(
                  border: Border.all(color: selected
                      ? t.vermilion : t.divider, width: selected ? 2 : 1),
                  borderRadius: BorderRadius.circular(4)),
                child: ClipRRect(borderRadius: BorderRadius.circular(3),
                  child: CustomPaint(painter: _PaperAppearancePainter(mode))),
              ),
              const SizedBox(height: 10),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(
                  fontSize: 13,
                  color: selected ? t.vermilion : t.secondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PaperAppearancePainter extends CustomPainter {
  const _PaperAppearancePainter(this.mode);
  final ThemeMode mode;
  @override
  void paint(Canvas canvas, Size size) {
    final light = HyesTokens.light, dark = HyesTokens.dark;
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = mode == ThemeMode.dark
        ? dark.background : light.background);
    if (mode == ThemeMode.system) {
      canvas.drawPath(Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(), Paint()..color = dark.background);
    }
    final ink = mode == ThemeMode.dark ? dark.ink : light.ink;
    final lines = Paint()..color = ink.withValues(alpha: .48)
      ..strokeCap = StrokeCap.round..strokeWidth = 1.4;
    for (var i = 0; i < 4; i++) {
      final y = 13.0 + i * 11;
      canvas.drawLine(Offset(11, y), Offset(size.width - 13 - (i % 2) * 9, y),
        lines);
    }
    final seal = Paint()..color = HyesTokens.light.vermilion;
    canvas.drawRect(Rect.fromLTWH(size.width - 19, size.height - 18, 7, 7), seal);
  }

  @override
  bool shouldRepaint(covariant _PaperAppearancePainter old) => old.mode != mode;
}
