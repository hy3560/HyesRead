import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/ui/reader_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('layout presets persist locally using existing preference keys', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(await saveReaderLayoutPreset(prefs, readerLayoutPresets[2]), isTrue);
    expect(prefs.getDouble('fontSize'), 22);
    expect(prefs.getDouble('lineHeight'), 2.05);
    expect(prefs.getDouble('contentWidth'), 580);
    expect(await saveReaderLayoutPreset(prefs, readerLayoutPresets[1]), isTrue);
    expect(prefs.getDouble('fontSize'), 19);
    expect(prefs.getDouble('lineHeight'), 1.85);
    expect(prefs.getDouble('contentWidth'), 680);
  });

  test('layout presets preserve old default and allow denser or looser text', () {
    expect(readerLayoutPresets, hasLength(3));
    expect(readerLayoutPresets[1].matches(19, 1.85, 680), isTrue);
    expect(readerLayoutPresets[0].matches(19, 1.85, 680), isFalse);
    expect(readerLayoutPresets[2].fontSize, greaterThan(readerLayoutPresets[1].fontSize));
    expect(readerLayoutPresets[2].contentWidth, lessThan(readerLayoutPresets[1].contentWidth));
  });

  test('EPUB honors shared size, spacing, and night paper settings', () {
    final settings = epubTypography(
      fontSize: 25, lineHeight: 2.1, paper: 'dark',
    );
    expect(settings.fontSize, 25);
    expect(settings.lineHeight, 2.1);
    expect(settings.theme.backgroundColor, const Color(0xFF1A1815));
    expect(settings.fontFamily, 'SimSun');
    expect(settings.justify, isTrue);
  });

  test('EPUB paper choices map to the same shared preferences', () {
    expect(epubTypography(fontSize: 19, lineHeight: 1.85, paper: 'light')
        .theme.backgroundColor, const Color(0xFFFFFDFA));
    expect(epubTypography(fontSize: 19, lineHeight: 1.85, paper: 'sepia')
        .theme.backgroundColor, const Color(0xFFF4EEE2));
  });

  test('new TXT papers persist with legacy keys and EPUB uses safe themes', () async {
    SharedPreferences.setMockInitialValues({'paper': 'eye'});
    final prefs = await SharedPreferences.getInstance();
    expect(loadReaderAppearance(prefs, 'legacy').paper, 'eye');
    await prefs.setString('paper', 'gray');
    expect(loadReaderAppearance(prefs, 'legacy').paper, 'gray');
    expect(epubTypography(fontSize: 19, lineHeight: 1.85, paper: 'gray')
        .theme.backgroundColor, const Color(0xFFE6E4E0));
    expect(epubTypography(fontSize: 19, lineHeight: 1.85, paper: 'eye')
        .theme.backgroundColor, isNot(const Color(0xFFF4EEE2)));
    expect(await setReaderBookOverride(prefs, 'my-book', true), isTrue);
    await prefs.setString('reader.book.my-book.paper', 'dark');
    expect(loadReaderAppearance(prefs, 'my-book').paper, 'dark');
    expect(loadReaderAppearance(prefs, 'legacy').paper, 'gray');
  });

  test('EPUB clamps invalid saved typography values', () {
    final settings = epubTypography(fontSize: 9, lineHeight: 9, paper: 'unknown');
    expect(settings.fontSize, 14);
    expect(settings.lineHeight, 2.4);
    expect(settings.theme.backgroundColor, const Color(0xFFF4EEE2));
  });

  test('book-only typography starts unchanged and cannot leak to other books', () async {
    SharedPreferences.setMockInitialValues({
      'fontSize': 21.0,
      'lineHeight': 1.9,
      'paper': 'dark',
      'paragraphSpacing': 18.0,
    });
    final prefs = await SharedPreferences.getInstance();
    const first = 'first-book-id';
    const second = 'other-book-id';
    expect(loadReaderAppearance(prefs, first).bookOverride, false);
    expect(await setReaderBookOverride(prefs, first, true), isTrue);
    final seeded = loadReaderAppearance(prefs, first);
    expect(seeded.bookOverride, isTrue);
    expect(seeded.fontSize, 21);
    expect(seeded.paper, 'dark');
    expect(seeded.paragraphSpacing, 18);
    expect(await saveReaderLayoutPreset(prefs, readerLayoutPresets[2],
        prefix: readerBookPrefix(first)), isTrue);
    expect(await prefs.setString(readerPreferenceKey('paper', first, true), 'sepia'), isTrue);
    expect(await prefs.setBool(readerPreferenceKey('justifyText', first, true), true), isTrue);
    expect(await prefs.setDouble(readerPreferenceKey('paragraphSpacing', first, true), 24), isTrue);
    expect(loadReaderAppearance(prefs, first).fontSize, 22);
    expect(loadReaderAppearance(prefs, first).justifyText, true);
    expect(loadReaderAppearance(prefs, first).paragraphSpacing, 24);
    expect(loadReaderAppearance(prefs, second).fontSize, 21);
    expect(loadReaderAppearance(prefs, second).paper, 'dark');
    expect(loadReaderAppearance(prefs, second).paragraphSpacing, 18);
    expect(prefs.getDouble('fontSize'), 21); // Previous global keys untouched.
    expect(await setReaderBookOverride(prefs, first, false), isTrue);
    expect(loadReaderAppearance(prefs, first).bookOverride, false);
    expect(loadReaderAppearance(prefs, first).fontSize, 21);
    expect(loadReaderAppearance(prefs, first).paragraphSpacing, 18);
    expect(loadReaderAppearance(prefs, first).justifyText, true);
  });

  test('reader appearance respects old defaults and clamps invalid stored values', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final defaults = loadReaderAppearance(prefs, 'legacy');
    expect(defaults.fontSize, 20);
    expect(defaults.lineHeight, 1.9);
    expect(defaults.contentWidth, 640);
    expect(defaults.paragraphSpacing, 11);
    expect(defaults.justifyText, true);
    expect(defaults.fontKind, 'serif');
    expect(defaults.paper, 'sepia');
    await prefs.setDouble('fontSize', 500);
    await prefs.setDouble('lineHeight', 0.4);
    await prefs.setDouble('paragraphSpacing', -8);
    await prefs.setString('paper', 'invalid');
    final safe = loadReaderAppearance(prefs, 'legacy');
    expect(safe.fontSize, 32);
    expect(safe.lineHeight, 1.2);
    expect(safe.paragraphSpacing, 6);
    expect(safe.paper, 'sepia');
  });
}
