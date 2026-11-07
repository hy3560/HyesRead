import 'package:epub_rtl/epub_rtl.dart';
import 'dart:ui' show FontFeature;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reversible layout choices. The comfortable preset matches old defaults.
class ReaderLayoutPreset {
  const ReaderLayoutPreset(this.label, this.fontSize, this.lineHeight,
      this.contentWidth);

  final String label;
  final double fontSize, lineHeight, contentWidth;

  bool matches(double font, double spacing, double width) =>
      (font - fontSize).abs() < 0.01 &&
      (spacing - lineHeight).abs() < 0.01 &&
      (width - contentWidth).abs() < 0.01;
}

const readerLayoutPresets = <ReaderLayoutPreset>[
  ReaderLayoutPreset('紧凑', 17, 1.5, 760),
  ReaderLayoutPreset('舒适', 19, 1.85, 680),
  ReaderLayoutPreset('宽松', 22, 2.05, 580),
];

/// Book-specific settings never modify the old global keys or the book index.
/// The override switch is written last so interrupted writes cannot enable
/// a partially prepared layout.
String readerBookPrefix(String bookId) => 'reader.book.$bookId.';

String readerPreferenceKey(String name, String bookId, bool forBook) =>
    forBook ? '${readerBookPrefix(bookId)}$name' : name;

class ReaderAppearance {
  const ReaderAppearance({
    required this.bookOverride,
    required this.fontSize,
    required this.lineHeight,
    required this.contentWidth,
    required this.paper,
    required this.paragraphSpacing,
    required this.justifyText,
    required this.fontKind,
    required this.eyeWarmth,
  });

  final bool bookOverride;
  final double fontSize, lineHeight, contentWidth, paragraphSpacing;
  final String paper;
  final bool justifyText;
  final String fontKind;
  final double eyeWarmth;
}

/// Platform-native book faces, with the bundled offline Serif SC fallback.
String readerFontFamily(String kind, {bool isApple = false}) => switch (kind) {
  'kai' => isApple ? 'Kaiti SC' : 'KaiTi',
  'sans' => isApple ? 'PingFang SC' : 'Microsoft YaHei',
  'system' => 'system',
  _ => isApple ? 'Songti SC' : 'SimSun',
};

const readerFontFallback = <String>[
  'HyesSerifSC', 'Songti SC', 'Noto Serif CJK SC', 'Noto Serif SC',
];

ReaderAppearance loadReaderAppearance(SharedPreferences prefs, String bookId) {
  final isBook = prefs.getBool('${readerBookPrefix(bookId)}override') ?? false;
  double numeric(String name, double fallback, double low, double high) {
    final local = isBook ? prefs.getDouble(readerPreferenceKey(name, bookId, true)) : null;
    final value = local ?? prefs.getDouble(name) ?? fallback;
    return value.isFinite ? value.clamp(low, high).toDouble() : fallback;
  }

  final storedPaper = (isBook
      ? prefs.getString(readerPreferenceKey('paper', bookId, true))
      : null) ?? prefs.getString('paper') ?? 'sepia';
  return ReaderAppearance(
    bookOverride: isBook,
    fontSize: numeric('fontSize', 20, 14, 32),
    lineHeight: numeric('lineHeight', 1.9, 1.2, 2.4),
    contentWidth: numeric('contentWidth', 640, 340, 860),
    paper: {'sepia', 'light', 'eye', 'gray', 'dark'}.contains(storedPaper)
        ? storedPaper : 'sepia',
    paragraphSpacing: numeric('paragraphSpacing', 11, 6, 32),
    justifyText: (isBook
        ? prefs.getBool(readerPreferenceKey('justifyText', bookId, true))
        : null) ?? prefs.getBool('justifyText') ?? true,
    fontKind: () {
      final stored = (isBook
          ? prefs.getString(readerPreferenceKey('fontKind', bookId, true))
          : null) ?? prefs.getString('fontKind') ?? 'serif';
      return {'serif', 'kai', 'sans', 'system'}.contains(stored)
          ? stored : 'serif';
    }(),
    eyeWarmth: numeric('eyeWarmth', .5, 0, 1),
  );
}

/// Enabling starts with the currently visible appearance, so switching on
/// "this book only" never changes the page until the next edit.
Future<bool> setReaderBookOverride(
    SharedPreferences prefs, String bookId, bool enabled) async {
  final prefix = readerBookPrefix(bookId);
  if (!enabled) return prefs.setBool('${prefix}override', false);
  final appearance = loadReaderAppearance(prefs, bookId);
  var ok = true;
  for (final entry in <String, double>{
    'fontSize': appearance.fontSize,
    'lineHeight': appearance.lineHeight,
    'contentWidth': appearance.contentWidth,
    'paragraphSpacing': appearance.paragraphSpacing,
  }.entries) {
    if (!await prefs.setDouble('$prefix${entry.key}', entry.value)) ok = false;
  }
  if (!await prefs.setString('${prefix}paper', appearance.paper)) ok = false;
  if (!await prefs.setBool('${prefix}justifyText', appearance.justifyText)) ok = false;
  if (!await prefs.setString('${prefix}fontKind', appearance.fontKind)) ok = false;
  if (!await prefs.setDouble('${prefix}eyeWarmth', appearance.eyeWarmth)) ok = false;
  return ok && await prefs.setBool('${prefix}override', true);
}

/// Store each field using the same keys as the existing fine-grained sliders.
/// No book metadata or remote service is involved.
Future<bool> saveReaderLayoutPreset(
    SharedPreferences prefs, ReaderLayoutPreset preset,
    {String prefix = ''}) async {
  final font = await prefs.setDouble('${prefix}fontSize', preset.fontSize);
  final spacing = await prefs.setDouble('${prefix}lineHeight', preset.lineHeight);
  final width = await prefs.setDouble('${prefix}contentWidth', preset.contentWidth);
  return font && spacing && width;
}

/// Apply the same stored reading choices to the EPUB and plain-text engines.
/// EPUB positions remain in EpubLocation format, never converted to CFI.
EpubReaderSettings epubTypography({
  required double fontSize,
  required double lineHeight,
  required String paper,
  String fontKind = 'serif',
  double paragraphSpacing = 11,
  bool justify = true,
  bool isApple = false,
  double eyeWarmth = .5,
}) {
  final theme = switch (paper) {
    'dark' => const EpubReaderTheme(name: 'hyes-dark',
      backgroundColor: Color(0xFF1A1815), textColor: Color(0xFFDDD4C5),
      linkColor: Color(0xFFD98C79), secondaryColor: Color(0xFF514B42)),
    'light' => const EpubReaderTheme(name: 'hyes-light',
      backgroundColor: Color(0xFFFFFDFA), textColor: Color(0xFF2B2620),
      linkColor: Color(0xFFA44334), secondaryColor: Color(0xFFCAC4B9)),
    'gray' => const EpubReaderTheme(name: 'hyes-gray',
      backgroundColor: Color(0xFFE6E4E0), textColor: Color(0xFF2B2B2B),
      linkColor: Color(0xFFA44334), secondaryColor: Color(0xFFB9B7B2)),
    'eye' => EpubReaderTheme(name: 'hyes-eye',
      backgroundColor: Color.lerp(const Color(0xFFE9F1DF),
          const Color(0xFFF2E6D2), eyeWarmth.clamp(0.0, 1.0))!,
      textColor: const Color(0xFF2A3322),
      linkColor: const Color(0xFF8C4B37),
      secondaryColor: const Color(0xFFB6C6A8)),
    _ => const EpubReaderTheme(name: 'hyes-sepia',
      backgroundColor: Color(0xFFF4EEE2), textColor: Color(0xFF2B2620),
      linkColor: Color(0xFFA44334), secondaryColor: Color(0xFFC7BAA6)),
  };
  return EpubReaderSettings(
    fontSize: fontSize.clamp(14.0, 32.0),
    lineHeight: lineHeight.clamp(1.2, 2.4),
    theme: theme,
    fontFamily: fontKind == 'system' ? null
        : readerFontFamily(fontKind, isApple: isApple),
    fontFamilyFallback: readerFontFallback,
    justify: justify,
    letterSpacing: fontSize * 0.02,
    fontFeatures: const [FontFeature.enable('palt')],
    headingAccent: const Color(0xFFA44334),
    paragraphSpacing: (paragraphSpacing / fontSize).clamp(.3, 1.1),
    // Insets are inside the rendered sheet, not applied to the whole screen.
    padding: const EdgeInsets.fromLTRB(24, 64, 24, 86),
  );
}
