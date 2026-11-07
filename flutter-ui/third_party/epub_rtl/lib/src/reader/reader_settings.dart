import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Colours of the reader.
@immutable
class EpubReaderTheme {
  /// Creates a theme.
  const EpubReaderTheme({
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.linkColor,
    required this.secondaryColor,
  });

  /// Black text on white.
  static const light = EpubReaderTheme(
    name: 'light',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF1B1B1B),
    linkColor: Color(0xFF1565C0),
    secondaryColor: Color(0xFFBDBDBD),
  );

  /// Brown text on warm paper.
  static const sepia = EpubReaderTheme(
    name: 'sepia',
    backgroundColor: Color(0xFFF4ECD8),
    textColor: Color(0xFF5B4636),
    linkColor: Color(0xFF8B4513),
    secondaryColor: Color(0xFFC8B89A),
  );

  /// Light text on near black.
  static const dark = EpubReaderTheme(
    name: 'dark',
    backgroundColor: Color(0xFF121212),
    textColor: Color(0xFFE0E0E0),
    linkColor: Color(0xFF90CAF9),
    secondaryColor: Color(0xFF424242),
  );

  /// Identifier, such as `light`.
  final String name;

  /// Page background.
  final Color backgroundColor;

  /// Body text.
  final Color textColor;

  /// Links.
  final Color linkColor;

  /// Rules, table borders, quote bars and chapter separators.
  final Color secondaryColor;

  @override
  bool operator ==(Object other) =>
      other is EpubReaderTheme &&
      other.name == name &&
      other.backgroundColor == backgroundColor &&
      other.textColor == textColor &&
      other.linkColor == linkColor &&
      other.secondaryColor == secondaryColor;

  @override
  int get hashCode =>
      Object.hash(name, backgroundColor, textColor, linkColor, secondaryColor);
}

/// Typography and layout settings of the reader.
@immutable
class EpubReaderSettings {
  /// Creates settings.
  const EpubReaderSettings({
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.theme = EpubReaderTheme.light,
    this.fontFamily,
    this.arabicFontFamily,
    this.fontFamilyFallback = const [],
    this.justify = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    this.paragraphSpacing = 0.6,
    this.letterSpacing = 0,
    this.fontFeatures = const [],
    this.headingAccent = const Color(0xFFA44334),
  });

  /// Body font size in logical pixels. Headings scale from it.
  final double fontSize;

  /// Line height as a multiple of the font size.
  final double lineHeight;

  /// Colours.
  final EpubReaderTheme theme;

  /// Font family for body text; null uses the ambient default.
  final String? fontFamily;

  /// Font family for runs in an RTL language (`lang="ar"`, `fa`, `ur`...).
  /// It is also added first to the fallback list, so Arabic script inside
  /// other runs finds it too. The font must be bundled by the app.
  final String? arabicFontFamily;

  /// Further fallback families.
  final List<String> fontFamilyFallback;

  /// Justify paragraphs that do not set `text-align`.
  final bool justify;

  /// Padding around chapter content.
  final EdgeInsets padding;

  /// Default space below paragraphs, in em.
  final double paragraphSpacing;

  /// Letter spacing in physical logical pixels (applies to rendered EPUB).
  final double letterSpacing;

  /// OpenType features, such as CJK proportional punctuation `palt`.
  final List<FontFeature> fontFeatures;

  /// Short vermilion marker used with chapter and subsection headings.
  final Color headingAccent;

  /// Returns a copy with the given fields replaced.
  EpubReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    EpubReaderTheme? theme,
    String? fontFamily,
    String? arabicFontFamily,
    List<String>? fontFamilyFallback,
    bool? justify,
    EdgeInsets? padding,
    double? paragraphSpacing,
    double? letterSpacing,
    List<FontFeature>? fontFeatures,
    Color? headingAccent,
  }) =>
      EpubReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
        fontFamily: fontFamily ?? this.fontFamily,
        arabicFontFamily: arabicFontFamily ?? this.arabicFontFamily,
        fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
        justify: justify ?? this.justify,
        padding: padding ?? this.padding,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        fontFeatures: fontFeatures ?? this.fontFeatures,
        headingAccent: headingAccent ?? this.headingAccent,
      );

  /// Whether a change from [other] to this affects layout (and so needs the
  /// reading position to be restored).
  bool affectsLayout(EpubReaderSettings other) =>
      other.fontSize != fontSize ||
      other.lineHeight != lineHeight ||
      other.fontFamily != fontFamily ||
      other.arabicFontFamily != arabicFontFamily ||
      !listEquals(other.fontFamilyFallback, fontFamilyFallback) ||
      other.justify != justify ||
      other.padding != padding ||
      other.paragraphSpacing != paragraphSpacing ||
      other.letterSpacing != letterSpacing ||
      !listEquals(other.fontFeatures, fontFeatures);

  @override
  bool operator ==(Object other) =>
      other is EpubReaderSettings &&
      !affectsLayout(other) &&
      other.theme == theme &&
      other.headingAccent == headingAccent;

  @override
  int get hashCode => Object.hash(
      fontSize,
      lineHeight,
      theme,
      fontFamily,
      arabicFontFamily,
      Object.hashAll(fontFamilyFallback),
      justify,
      padding,
      paragraphSpacing,
      letterSpacing,
      Object.hashAll(fontFeatures),
      headingAccent);
}
