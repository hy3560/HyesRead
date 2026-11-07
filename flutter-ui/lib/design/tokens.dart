import 'dart:ui';

import 'package:flutter/material.dart';

/// The only app chromatic source of truth. Pages consume these tokens rather
/// than inventing gradients, arbitrary brand accents, or default M3 palettes.
@immutable
class HyesTokens extends ThemeExtension<HyesTokens> {
  const HyesTokens({
    required this.background,
    required this.surface,
    required this.raised,
    required this.divider,
    required this.ink,
    required this.secondary,
    required this.quiet,
    required this.vermilion,
  });

  final Color background;
  final Color surface;
  final Color raised;
  final Color divider;
  final Color ink;
  final Color secondary;
  final Color quiet;
  final Color vermilion;

  static const light = HyesTokens(
    background: Color(0xFFF4EEE2),
    surface: Color(0xFFFBF7EE),
    raised: Color(0xFFFFFFFF),
    divider: Color(0x14000000),
    ink: Color(0xFF1F1B16),
    secondary: Color(0xFF6F6657),
    quiet: Color(0xFFA39A88),
    vermilion: Color(0xFFC8452F),
  );

  static const dark = HyesTokens(
    background: Color(0xFF141311),
    surface: Color(0xFF1C1A17),
    raised: Color(0xFF26231F),
    divider: Color(0x14FFFFFF),
    ink: Color(0xFFF0E9DC),
    secondary: Color(0xFFA89F90),
    quiet: Color(0xFF6F685C),
    vermilion: Color(0xFFE4573D),
  );

  static const double pageInset = 24;
  static const double coverRadius = 4;
  static const double buttonRadius = 12;
  static const double touchSize = 48;

  static const String serifFamily = 'HyesSerifSC';

  static HyesTokens of(BuildContext context) =>
      Theme.of(context).extension<HyesTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  TextStyle get display => TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: const ['Noto Serif CJK SC', 'Noto Serif SC', 'serif'],
    fontSize: 38, height: 1.15, letterSpacing: .5,
    fontWeight: FontWeight.w600, color: ink,
  );
  TextStyle get title => display.copyWith(fontSize: 24, letterSpacing: 0);
  TextStyle get body => TextStyle(fontSize: 15, height: 1.6, color: ink);
  TextStyle get caption => TextStyle(fontSize: 12, height: 1.4,
    color: secondary, fontFeatures: const [FontFeature.tabularFigures()]);
  TextStyle get number => caption.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  HyesTokens copyWith({Color? background, Color? surface, Color? raised,
    Color? divider, Color? ink, Color? secondary, Color? quiet,
    Color? vermilion}) => HyesTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    divider: divider ?? this.divider,
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    quiet: quiet ?? this.quiet,
    vermilion: vermilion ?? this.vermilion,
  );

  @override
  HyesTokens lerp(ThemeExtension<HyesTokens>? other, double t) {
    if (other is! HyesTokens) return this;
    return HyesTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      quiet: Color.lerp(quiet, other.quiet, t)!,
      vermilion: Color.lerp(vermilion, other.vermilion, t)!,
    );
  }
}
