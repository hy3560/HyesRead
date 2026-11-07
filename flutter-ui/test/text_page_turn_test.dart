import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/reader_page.dart';
import 'package:hyesread_flutter/ui/text_page_layout.dart';
import 'package:hyesread_flutter/widgets/text_page_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

TextPageLayouter _layout(List<String> paragraphs, {double width = 270,
    double height = 390, double font = 20}) => TextPageLayouter(
  paragraphs: paragraphs, width: width, height: height,
  bodyStyle: TextStyle(fontSize: font, height: 1.6),
  headingStyle: TextStyle(fontSize: font * 1.25, height: 1.5),
  textScaler: TextScaler.noScaling,
  direction: TextDirection.ltr, paragraphSpacing: 13,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real pages keep every character including surrogate pairs', () {
    final paragraphs = [
      '第一章 山间旧事',
      '山河入梦，风从纸页间吹来。' * 170,
      '🌙📚一寸光阴一寸纸。' * 80,
      '尾声',
      '我们会再见。',
    ];
    final layouter = _layout(paragraphs);
    var cursor = const TextPageCursor(0, 0);
    final all = <int, StringBuffer>{};
    var pages = 0;
    while (true) {
      final page = layouter.layout(cursor);
      expect(page.pieces, isNotEmpty);
      for (final part in page.pieces) {
        all.putIfAbsent(part.paragraph, StringBuffer.new).write(part.text);
      }
      pages++;
      expect(pages, lessThan(200), reason: 'page boundary must advance');
      if (page.next == null) break;
      expect(page.next, isNot(cursor));
      cursor = page.next!;
    }
    expect(pages, greaterThan(5));
    for (var i = 0; i < paragraphs.length; i++) {
      expect(all[i].toString(), paragraphs[i],
        reason: 'page splits must neither omit nor repeat paragraph $i');
    }
    expect(layouter.approximatePrevious(const TextPageCursor(0, 0)), isNull);
    expect(layouter.approximatePrevious(cursor), isNotNull);
  });

  test('reflow keeps whole Unicode graphemes at every page boundary', () {
    const unit = '👨‍👩‍👧‍👦e\u0301🇯🇵क्‍ष👩🏽‍💻';
    final content = List.filled(80, unit).join();
    final paragraph = '一段文字。$content';
    final safeEnds = <int>{0};
    var end = 0;
    for (final cluster in paragraph.characters) {
      end += cluster.length;
      safeEnds.add(end);
    }
    final layouter = _layout([paragraph], width: 120,
      height: 165, font: 23);
    var cursor = const TextPageCursor(0, 0);
    final restored = StringBuffer();
    var turns = 0;
    while (true) {
      final page = layouter.layout(cursor);
      expect(page.pieces, isNotEmpty);
      for (final piece in page.pieces) {
        restored.write(piece.text);
        final position = restored.length;
        expect(safeEnds.contains(position), isTrue,
          reason: 'page must end after a complete grapheme at $position');
      }
      expect(++turns, lessThan(400));
      if (page.next == null) break;
      expect(page.next!, isNot(cursor));
      cursor = page.next!;
      expect(safeEnds.contains(cursor.offset), isTrue);
    }
    expect(turns, greaterThan(3));
    expect(restored.toString(), paragraph);
  });

  test('paragraph that fits without trailing spacing completes normally', () {
    final layouter = TextPageLayouter(
      paragraphs: ['这一段。', '下一段。'],
      width: 190, height: 45,
      bodyStyle: const TextStyle(fontSize: 20, height: 1.4),
      headingStyle: const TextStyle(fontSize: 24, height: 1.5),
      textScaler: TextScaler.noScaling,
      direction: TextDirection.ltr, paragraphSpacing: 50);
    final page = layouter.layout(const TextPageCursor(0, 0));
    expect(page.pieces.single.text, '这一段。');
    expect(page.pieces.single.endsParagraph, isTrue);
    expect(page.next, const TextPageCursor(1, 0));
    expect(layouter.layout(page.next!).pieces.single.text, '下一段。');
  });

  test('very long paragraphs reflow incrementally without loading a whole page of text', () {
    final paragraph = '秋雨敲窗，纸张翻动。' * 35000;
    final layouter = _layout([paragraph], width: 210,
      height: 290, font: 19);
    const start = TextPageCursor(0, 0);
    final first = layouter.layout(start);
    expect(first.pieces, isNotEmpty);
    expect(first.next, isNotNull);
    expect(first.next!.offset, greaterThan(0));
    expect(first.next!.offset, lessThan(4096));
    final second = layouter.layout(first.next!);
    expect(second.next, isNotNull);
    expect(second.next!.offset, greaterThan(first.next!.offset));
    expect(first.pieces.map((p) => p.text).join() +
        second.pieces.map((p) => p.text).join(),
        paragraph.substring(0, second.next!.offset));
  });

  test('blank blocks preceding the text do not cause a blank sheet', () {
    final content = List<String>.filled(220, '', growable: true)
      ..add('还有正文。');
    final page = _layout(content).layout(
      const TextPageCursor(0, 0));
    expect(page.pieces, hasLength(1));
    expect(page.pieces.single.text, '还有正文。');
    expect(page.next, isNull);
  });

  test('text position offset survives old and new metadata formats', () {
    final original = BookEntry(
      id: 'a' * 64, title: '书房笔记', fileName: 'notes.txt',
      format: 'txt', path: 'unused.txt', importedAt: 0,
      paragraphIndex: 3, textOffset: 462,
    );
    expect(BookEntry.fromJson(original.toJson()).textOffset, 462);
    final legacy = Map<String, dynamic>.from(original.toJson());
    legacy.remove('textOffset');
    expect(BookEntry.fromJson(legacy).textOffset, 0);
    expect(original.copyWith(textOffset: 120).textOffset, 120);
  });

  testWidgets('previous, next and keyboard actually turn the paper sheet',
      (tester) async {
    final visited = <TextPageCursor>[];
    final paragraphs = List.generate(15, (i) =>
      '第 ${i + 1} 部 · 又翻过一页。' * 35);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextPageReader(
        title: '我的纸墨书房', paragraphs: paragraphs,
        initialCursor: const TextPageCursor(0, 0),
        paper: const Color(0xFFF4EEE2), ink: const Color(0xFF2B2620),
        contentWidth: 590, fontSize: 19, lineHeight: 1.7,
        paragraphSpacing: 13, justify: false, topInset: 0,
        onPositionChanged: visited.add,
      )),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('paper-next-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-previous-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pumpAndSettle();
    expect(visited, isNotEmpty);
    expect(visited.last, isNot(const TextPageCursor(0, 0)));
    final next = visited.last;
    await tester.tap(find.byKey(const ValueKey('paper-previous-page')));
    await tester.pumpAndSettle();
    expect(visited.last, const TextPageCursor(0, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(visited.last, next);
    // Mouse wheel (desktop) must change the actual anchor, not just animate.
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(find.byType(TextPageReader)),
      scrollDelta: const Offset(0, 124),
    ));
    await tester.pumpAndSettle();
    expect(visited.last, isNot(next));
    await tester.drag(find.byType(TextPageReader), const Offset(230, 0));
    await tester.pumpAndSettle();
    expect(visited.last, next);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp 200% text still turns with reduced motion', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2), disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: TextPageReader(
        title: '可以翻动的书', paragraphs: ['楔子', '风从旧纸上吹过。' * 160],
        initialCursor: const TextPageCursor(0, 0),
        paper: const Color(0xFFF4EEE2), ink: const Color(0xFF2B2620),
        contentWidth: 680, fontSize: 19, lineHeight: 1.85,
        paragraphSpacing: 13, justify: false, topInset: 0,
        onPositionChanged: visited.add,
      )),
    ));
    await tester.pump();
    final button = find.byKey(const ValueKey('paper-next-page'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pump();
    expect(visited, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide reader turns a facing pair without repeating text',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final story = List.generate(7, (i) =>
        '段落${i + 1}，窗外秋雨缓缓落下。灯下纸笔仍温暖。' * 80);
    final visited = <TextPageCursor>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: TextPageReader(
        title: '宽屏对页验收', paragraphs: story,
        initialCursor: const TextPageCursor(0, 0),
        paper: const Color(0xFFF4EEE2),
        ink: const Color(0xFF2B2620),
        contentWidth: 640, fontSize: 20, lineHeight: 1.9,
        paragraphSpacing: 11, justify: false, topInset: 0,
        onPositionChanged: visited.add,
      ),
    )));
    await tester.pumpAndSettle();
    final spread = find.byKey(const ValueKey('paper-facing-pages'));
    expect(spread, findsOneWidget);
    expect(find.descendant(of: spread, matching: find.byType(SelectionArea)),
        findsNWidgets(2));
    if (const bool.fromEnvironment('HYES_SPREAD_SHOTS')) {
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('goldens/desktop-facing-pages-1280x800.png'));
    }
    final first = tester.state<TextPageReaderState>(
      find.byType(TextPageReader)).currentCursor;
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pumpAndSettle();
    final next = tester.state<TextPageReaderState>(
      find.byType(TextPageReader)).currentCursor;
    expect(next, isNot(first));
    expect(visited, [next], reason: 'one turn commits a whole facing pair');
    await tester.tap(find.byKey(const ValueKey('paper-previous-page')));
    await tester.pumpAndSettle();
    expect(tester.state<TextPageReaderState>(
        find.byType(TextPageReader)).currentCursor, first);

    // Text from both visible pages must concatenate to exactly the source.
    final all = StringBuffer();
    var turns = 0;
    while (true) {
      final pieces = tester.widgetList<Text>(find.descendant(
        of: spread, matching: find.byType(Text))).map(
          (w) => (w.data ?? '').replaceFirst('\u3000\u3000', ''));
      all.write(pieces.join());
      if (!tester.state<TextPageReaderState>(
          find.byType(TextPageReader)).canGoForward) break;
      expect(turns++, lessThan(90));
      await tester.tap(find.byKey(const ValueKey('paper-next-page')));
      await tester.pumpAndSettle();
    }
    expect(all.toString(), story.join());
    expect(tester.takeException(), isNull);
  });

  testWidgets('spread reflows to one page for narrow and enlarged displays',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final paragraphs = ['溪水流过石桥。' * 300];
    var large = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 2 : 1)),
          child: Scaffold(body: TextPageReader(
            title: '宽窄自适应',
            paragraphs: paragraphs,
            initialCursor: const TextPageCursor(0, 0),
            paper: const Color(0xFFF4EEE2),
            ink: const Color(0xFF2B2620),
            contentWidth: 640, fontSize: 20, lineHeight: 1.9,
            paragraphSpacing: 11, justify: false, topInset: 0,
            onPositionChanged: (_) {},
          )),
        );
      },
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-facing-pages')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pumpAndSettle();
    final anchor = tester.state<TextPageReaderState>(
        find.byType(TextPageReader)).currentCursor;
    tester.view.physicalSize = const Size(720, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-facing-pages')), findsNothing);
    expect(tester.state<TextPageReaderState>(
        find.byType(TextPageReader)).currentCursor, anchor);
    tester.view.physicalSize = const Size(800, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-facing-pages')), findsOneWidget,
        reason: 'a compact desktop window still fits two paper leaves');
    expect(tester.state<TextPageReaderState>(
        find.byType(TextPageReader)).currentCursor, anchor);
    tester.view.physicalSize = const Size(1280, 800);
    update(() => large = true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-facing-pages')), findsNothing);
    update(() => large = false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('paper-facing-pages')), findsOneWidget);
    expect(tester.state<TextPageReaderState>(
        find.byType(TextPageReader)).currentCursor, anchor);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows page turns persist within a long paragraph and reopen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temp = Directory.systemTemp.createTempSync('hyesread-paged-');
    final story = '窗边翻开一本久违的书。' * 240;
    final hash = sha256.convert(utf8.encode(story)).toString();
    final files = Directory('${temp.path}/books')..createSync();
    File('${files.path}/$hash.txt').writeAsStringSync(story);
    File('${temp.path}/library.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'books': [{
        'id': hash, 'title': '窗边的书', 'fileName': '窗边的书.txt',
        'format': 'txt', 'path': '${files.path}/$hash.txt',
        'importedAt': 1,
      }],
    }));
    final repo = LibraryRepository(root: temp);
    // This fixture is prepared outside the fake widget clock, just like the
    // app shell's disk-backed reader tests.
    await tester.runAsync(() async {
      await repo.load();
    });
    final book = repo.books.single;

    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: FilledButton(
          onPressed: () => Navigator.push<void>(context,
            MaterialPageRoute(builder: (_) => ReaderPage(
              repository: repo, bookId: book.id))),
          child: const Text('打开书'),
        )),
      )),
    ));
    Future<void> open() async {
      await tester.tap(find.text('打开书'));
      await tester.pump();
      for (var i = 0; i < 10 && find.byType(TextPageReader).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(find.byType(TextPageReader), findsOneWidget);
      await tester.pumpAndSettle();
    }

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final location = tester.state<TextPageReaderState>(
      find.byType(TextPageReader)).currentCursor;
    expect(location.offset, greaterThan(0));
    await tester.tapAt(const Offset(550, 410));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.tap(find.byTooltip('保存并返回书架'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(ReaderPage).evaluate().isEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 40)));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.byType(ReaderPage), findsNothing);
    expect(repo.byId(book.id)!.textOffset, location.offset);

    await open();
    final restored = tester.state<TextPageReaderState>(
      find.byType(TextPageReader)).currentCursor;
    expect(restored, location);
    await tester.tapAt(const Offset(550, 410));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.tap(find.byTooltip('阅读排版'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('滚动'));
    await tester.tap(find.text('滚动'));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TextPageReader), findsNothing);
    expect(find.byType(ScrollablePositionedList), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    temp.deleteSync(recursive: true);
  });
}
