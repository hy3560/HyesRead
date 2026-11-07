import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/ui/reader_text_search.dart';

void main() {
  test('local reader search returns exact UTF-16 offsets and bounded hits', () {
    final blocks = [
      '第一章',
      '窗边🌙星星闪烁，夜里还有星星。',
      '没有任何匹配的段落。',
      '后来的人也记得星星。',
    ];
    final hits = searchReaderText(blocks, '星星');
    expect(hits, hasLength(3));
    expect(hits.first.paragraph, 1);
    expect(hits.first.offset, 4,
        reason: 'astral emoji occupies two UTF-16 code units');
    for (final hit in hits) {
      expect(blocks[hit.paragraph]
          .substring(hit.offset, hit.offset + 2), '星星');
      expect(hit.preview, contains('星星'));
    }
    expect(searchReaderText(blocks, '星星', maximum: 1), hasLength(1));
    expect(searchReaderText(blocks, '星'), isEmpty);
    expect(searchReaderText(blocks, 'not here'), isEmpty);
  });

  testWidgets('reader in-book search supports arrow selection and Enter jump',
      (tester) async {
    ReaderTextHit? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) =>
        TextButton(
          onPressed: () async {
            chosen = await showDialog<ReaderTextHit>(
              context: context,
              builder: (_) => const ReaderTextSearchDialog(
                paragraphs: [
                  '窗外有星星，山上也有星星。',
                  '我在梦里寻找星星。',
                ],
                english: false,
              ),
            );
          },
          child: const Text('查找'),
        ))),
    ));
    await tester.tap(find.text('查找'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-search-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')), '星星');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-search-hit-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-search-hit-2')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen?.paragraph, 1);
    expect(chosen?.offset, greaterThan(0));
    expect(find.byKey(const ValueKey('reader-search-dialog')), findsNothing);
    // Immediate Enter must not be lost while the search debounce is pending.
    await tester.tap(find.text('查找'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')), '星星');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen?.paragraph, 0);
    expect(chosen?.offset, 3);
    expect(tester.takeException(), isNull);
  });
}
