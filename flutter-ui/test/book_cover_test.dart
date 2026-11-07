import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/widgets/book_cover.dart';

BookEntry fakeCoverBook(String title, {String format = 'txt'}) => BookEntry(
  id: 'a' * 64, title: title, fileName: '$title.$format', format: format,
  path: '/fixture/$title.$format', importedAt: 1,
);

void main() {
  test('FNV-1a is stable on UTF-8 and does not use String.hashCode', () {
    expect(stableTitleHash('a'), 0xe40c292c);
    expect(stableTitleHash('hello'), 0x4f9f2cab);
    final before = stableTitleHash('师尊今天也想摸鱼');
    expect(stableTitleHash('师尊今天也想摸鱼'), before);
    expect(stableTitleHash('师尊今天也想摸鱼。'), isNot(before));
    expect(coverPalettes.length, 8);
    expect(coverPaletteFor('师尊今天也想摸鱼').background,
        coverPalettes[before % 8].background);
  });

  for (final mode in [Brightness.light, Brightness.dark]) {
    testWidgets('generated Chinese covers maintain portrait design $mode',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(mode),
        home: Scaffold(body: Center(child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            BookCover(book: fakeCoverBook('我在仙门开食堂'),
              width: 130, height: 195),
            BookCover(book: fakeCoverBook('师尊今天也想摸鱼'),
              width: 130, height: 195),
          ],
        ))),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(BookCover), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/paper-covers-${mode.name}.png'));
    });
  }
}
