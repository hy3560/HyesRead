import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

bool _reportedLensSupport = false;

/// Actual sampled-backdrop lens with curved-edge refraction, specular glint
/// and an engine fallback. Do not cover it with an opaque Container: that
/// would hide the very light bending that differentiates it from blur.
class LiquidLens extends StatelessWidget {
  const LiquidLens({
    super.key,
    required this.child,
    this.radius = 30,
    this.padding = EdgeInsets.zero,
    this.brightnessOverride,
    this.shareBackdrop = true,
    this.clear = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Brightness? brightnessOverride;
  final bool shareBackdrop;
  final bool clear;

  @override
  Widget build(BuildContext context) {
    final brightness = brightnessOverride ?? Theme.of(context).brightness;
    if (kDebugMode && !_reportedLensSupport) {
      _reportedLensSupport = true;
      debugPrint('HYESREAD_LIQUID_LENS shaderFilterSupported='
          '${ImageFilter.isShaderFilterSupported}');
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      return GlassSurface(
        radius: radius, blur: 0, padding: padding,
        brightnessOverride: brightness, child: child,
      );
    }
    return LiquidGlassLayer(
      useBackdropGroup: shareBackdrop,
      settings: clear
          ? LiquidGlassSettings.ios27Clear(tintAmount: 0.20)
          : LiquidGlassSettings.ios27Regular(
              brightness: brightness, tintAmount: 0.32),
      defaultAppearance: clear
          ? LiquidGlassAppearance.ios27Clear()
          : LiquidGlassAppearance.ios27Regular(brightness: brightness),
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        shadows: [BoxShadow(
          color: Colors.black.withValues(
            alpha: brightness == Brightness.dark ? 0.34 : 0.15,
          ),
          offset: const Offset(0, 8), blurRadius: 22,
        )],
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A small, high-contrast frosted surface. Reserve actual backdrop blur for
/// a few floating controls rather than every book in a scrolling grid.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 14,
    this.padding = EdgeInsets.zero,
    this.warm = false,
    this.brightnessOverride,
  });

  final Widget child;
  final double radius, blur;
  final EdgeInsetsGeometry padding;
  final bool warm;
  final Brightness? brightnessOverride;

  @override
  Widget build(BuildContext context) {
    final dark = (brightnessOverride ?? Theme.of(context).brightness)
        == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    final base = dark ? const Color(0xFF22242B) : Colors.white;
    final opacity = dark ? 0.86 : 0.84;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              (warm ? colors.primary : Colors.white)
                  .withValues(alpha: dark ? 0.16 : 0.12),
              base.withValues(alpha: opacity),
            ),
            base.withValues(alpha: dark ? 0.92 : 0.74),
          ],
        ),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.17)
              : Colors.white.withValues(alpha: 0.82),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.25 : 0.10),
          blurRadius: 26, offset: const Offset(0, 9),
        ),
      ]),
      child: ClipRRect(
        borderRadius: shape,
        child: reducedMotion || blur <= 0
            ? content
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: content,
              ),
      ),
    );
  }
}

/// Light and inexpensive jelly response: animate the interactive card, not
/// the whole page's backdrop. Text and controls remain opaque and selectable.
class JellyCard extends StatefulWidget {
  const JellyCard({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 16,
    this.hero = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool hero;

  @override
  State<JellyCard> createState() => _JellyCardState();
}

class _JellyCardState extends State<JellyCard> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.radius);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: reduceMotion || !pressed ? 1 : 0.976,
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 185),
      curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [BoxShadow(
            color: colors.shadow.withValues(alpha: dark ? 0.24 : 0.09),
            blurRadius: widget.hero ? 14 : 8,
            offset: Offset(0, widget.hero ? 6 : 3),
          )],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.hero
                    ? [
                        colors.surfaceContainerLowest,
                        colors.surfaceContainerLow,
                      ]
                    : [colors.surfaceContainerLowest, colors.surfaceContainerLow],
              ),
              border: Border.all(color: colors.outlineVariant.withValues(
                  alpha: dark ? 0.52 : 0.60)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (value) {
                  if (mounted && pressed != value) {
                    setState(() => pressed = value);
                  }
                },
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four fixed, accessible destinations; compact mode keeps 48dp targets and
/// full screen-reader labels even at 320dp / 200% system text size.
class GlassDock extends StatelessWidget {
  const GlassDock({
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
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: LiquidStretch(
      interactionScale: MediaQuery.disableAnimationsOf(context) ? 1 : 1.018,
      stretch: MediaQuery.disableAnimationsOf(context) ? 0 : 0.18,
      child: LiquidLens(
        radius: 30,
        clear: true,
        shareBackdrop: true,
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 62,
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedAlign(
                alignment: Alignment(
                    -1 + 2 * selectedIndex / (icons.length - 1), 0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero : const Duration(milliseconds: 390),
                curve: Curves.easeOutBack,
                child: FractionallySizedBox(
                  widthFactor: 1 / icons.length,
                  heightFactor: 0.95,
                  child: MediaQuery.disableAnimationsOf(context)
                      ? DecoratedBox(
                          key: const ValueKey('glass-dock-indicator'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(23),
                            color: colors.primary.withValues(alpha: 0.15),
                            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
                          ),
                        )
                      : LiquidGlass.withOwnLayer(
                          key: const ValueKey('glass-dock-indicator'),
                          useBackdropGroup: true,
                          settings: LiquidGlassSettings.ios27Clear(tintAmount: 0.12),
                          appearance: LiquidGlassAppearance.ios27Clear(),
                          shape: const LiquidRoundedSuperellipse(borderRadius: 23),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(23),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
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
                      key: ValueKey('glass-dock-$i'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onSelected(i),
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero : const Duration(milliseconds: 270),
                        curve: Curves.easeOutBack,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.transparent,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: selectedIndex == i ? 1.10 : 1,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero : const Duration(milliseconds: 260),
                              curve: Curves.easeOutBack,
                              child: Icon(icons[i], size: 22,
                                  color: selectedIndex == i
                                      ? colors.onSurface : colors.onSurfaceVariant),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 3),
                              Text(labels[i], maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10, height: 1.1,
                                  fontWeight: selectedIndex == i
                                      ? FontWeight.w700 : FontWeight.w500,
                                  color: selectedIndex == i
                                      ? colors.onSurface : colors.onSurfaceVariant,
                                )),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )),
          ]),
          ]),
        ),
      ),
      ),
    );
  }
}
