import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Explicit press state (0.97 scale, vermilion -8% brightness) with no M3 pill.
class PaperButton extends StatefulWidget {
  const PaperButton({super.key, required this.label, required this.onPressed,
    this.icon, this.outlined = false, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined, loading;
  @override
  State<PaperButton> createState() => _PaperButtonState();
}

class _PaperButtonState extends State<PaperButton> {
  bool _down = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    final reduced = HyesMotion.reduced(context);
    final foreground = widget.outlined ? t.ink : Colors.white;
    final background = widget.outlined
        ? Colors.transparent
        : (_down ? HSLColor.fromColor(t.vermilion)
            .withLightness((HSLColor.fromColor(t.vermilion).lightness * .92)
                .clamp(0, 1)).toColor() : t.vermilion);
    final enabled = widget.onPressed != null && !widget.loading;
    final lifted = enabled && _hovered && !_down && !reduced;
    return Semantics(button: true, enabled: enabled, label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        child: AnimatedSlide(
          offset: lifted ? const Offset(0, -.025) : Offset.zero,
          duration: reduced ? Duration.zero : HyesMotion.fast,
          curve: HyesMotion.enter,
          child: AnimatedScale(
          scale: reduced || !_down ? 1 : .97,
          duration: reduced ? Duration.zero : HyesMotion.fast,
          curve: HyesMotion.enter,
          child: Material(color: Colors.transparent,
            child: InkWell(
              onHover: (hovered) {
                if (_hovered != hovered) {
                  setState(() => _hovered = hovered);
                }
              },
              onTap: enabled ? () {
                HyesMotion.confirmed(context);
                widget.onPressed?.call();
              } : null,
              borderRadius: BorderRadius.circular(HyesTokens.buttonRadius),
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : HyesMotion.fast,
                constraints: const BoxConstraints(minHeight: HyesTokens.touchSize),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(HyesTokens.buttonRadius),
                  border: widget.outlined ? Border.all(color: t.divider) : null,
                  boxShadow: lifted ? [BoxShadow(
                    color: t.ink.withValues(alpha: widget.outlined ? .055 : .11),
                    offset: const Offset(0, 4),
                    blurRadius: 12,
                  )] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (widget.loading) SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5,
                      color: foreground)),
                  if (!widget.loading && widget.icon != null)
                    Icon(widget.icon, color: foreground, size: 19),
                  if (widget.icon != null || widget.loading)
                    const SizedBox(width: 9),
                  Text(widget.label, style: TextStyle(color: foreground,
                    fontWeight: FontWeight.w600, fontSize: 15)),
                ]),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
