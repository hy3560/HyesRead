import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:epub_rtl/epub_rtl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/data/epub_presentation.dart';
import 'package:hyesread_flutter/design/tokens.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/reader_page.dart';
import 'package:hyesread_flutter/widgets/chapter_scrubber.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproducible *original-text* EPUB exercise for the real ReaderPage widget.
/// No third-party book is required and the fixture lives in a temp book shelf.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter's raster golden output can differ by a few anti-aliased pixels
  // when the real CJK font and EPUB scroll timing settle across test suites.
  // Screenshot generation is an explicit, reproducible test mode, while
  // normal unit runs assert EPUB structure and widget behaviors below.
  const captureScreenshots = bool.fromEnvironment('HYES_SCREENSHOTS');
  late Directory directory;
  late LibraryRepository repository;
  late String bookId;
  late Uint8List fixtureBytes;

  setUpAll(() async {
    // Real Chinese glyphs for screenshot proof, rather than Ahem rectangles.
    // Windows system font is loaded for tests only, never redistributed.
    final systemFont = File('C:/Windows/Fonts/NotoSerifSC-VF.ttf');
    final data = (systemFont.existsSync() ? systemFont
        : File('assets/fonts/HyesSerifSC-SemiBold.ttf')).readAsBytesSync();
    for (final family in ['SimSun', HyesTokens.serifFamily]) {
      await (FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(data)))).load();
    }

    final cache = Platform.environment['LOCALAPPDATA'] ?? '';
    final iconDir = Directory('$cache/Pub/Cache/hosted/pub.dev/'
        'phosphoricons_flutter-1.1.1/lib/fonts');
    for (final (family, file) in <(String, String)>[
      ('PhosphorRegular', 'Phosphor.ttf'),
      ('PhosphorFill', 'Phosphor-Fill.ttf'),
    ]) {
      final asset = File('${iconDir.path}/$file');
      if (asset.existsSync()) {
        final glyphs = asset.readAsBytesSync();
        for (final alias in [family, 'packages/phosphoricons_flutter/$family']) {
          await (FontLoader(alias)..addFont(Future.value(
            ByteData.sublistView(glyphs)))).load();
        }
      }
    }

    directory = Directory.systemTemp.createTempSync('hyesread-epub-visual-');
    final archive = Archive();
    archive.addFile(ArchiveFile.string('mimetype', 'application/epub+zip'));
    archive.addFile(ArchiveFile.string('META-INF/container.xml',
      '<?xml version="1.0"?><container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>'));
    // Original painted illustration; no external files or copyrighted art.
    final recorder = ui.PictureRecorder();
    final painting = Canvas(recorder);
    painting.drawRect(const Rect.fromLTWH(0, 0, 700, 420),
      Paint()..color = const Color(0xFFF8F2E6));
    for (var i = 0; i < 3; i++) {
      final y = 78.0 + i * 124;
      painting.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(36, y - 40, 628, 90),
          const Radius.circular(8)),
        Paint()..color = i.isEven
            ? const Color(0xFFE8D9C3) : const Color(0xFFDED8CA));
      painting.drawCircle(Offset(92, y + 4), 24,
        Paint()..color = const Color(0xFFAA5746));
      painting.drawLine(Offset(145, y - 5), Offset(615, y - 5),
        Paint()..color = const Color(0xFF776657)..strokeWidth = 5);
      painting.drawLine(Offset(145, y + 17), Offset(465, y + 17),
        Paint()..color = const Color(0xFF9E8A75)..strokeWidth = 3);
    }
    final raster = await recorder.endRecording().toImage(700, 420);
    final rasterData = await raster.toByteData(format: ui.ImageByteFormat.png);
    final illustration = rasterData!.buffer.asUint8List();
    raster.dispose();
    archive.addFile(ArchiveFile('OEBPS/diagram.png',
        illustration.length, illustration));
    final items = StringBuffer();
    final spine = StringBuffer();
    final nav = StringBuffer();
    for (var i = 0; i < 52; i++) {
      items.write('<item id="c$i" href="chapter$i.xhtml" '
          'media-type="application/xhtml+xml"/>');
      spine.write('<itemref idref="c$i"/>');
      nav.write('<li><a href="chapter$i.xhtml">第${i + 1}章</a></li>');
      final story = StringBuffer()
        ..write('<h1>第${i + 1}章</h1>')
        ..write('<h3>封存层笔记</h3>');
      if (i == 9) {
        story.write('<img src="diagram.png" alt="原创思考笔记结构插图" />');
      }
      final passages = <String>[
        '窗外的风轻轻吹过纸页。有人把思考写成笔记，也有人把回忆放在书架深处。阅读无需着急，它是给自己的安静时间。',
        '“这就是答案吗？”“还不是。”我们沿着问题前进，把零散的线索整理成可以再次寻找的方向。每一次记录都为将来的自己留下了一盏灯。',
        '书桌上只剩一杯温茶。那些看起来微不足道的瞬间，经过认真回望，终于变成清晰而温和的记忆。',
        '封存并不是遗忘，而是给重要的东西留一个位置。等到需要的时候，可以不急不忙地重新打开它。',
        '行动层笔记',
        '把一个想法拆分成今天能够执行的一步，方向也因此渐渐清晰。失败和重来都值得被如实记录。',
        '日子缓慢向前，书页不会催促任何人。这是一间安静的书房，想离开时可以合上书，想回来时依然有光。',
      ];
      // Chapter ten is deliberately longer than a whole facing spread.
      // It catches EPUB engines that confuse one chapter with one page.
      final chapterPassages = i == 9
          ? [...passages, ...passages, ...passages, ...passages]
          : passages;
      for (final sentence in chapterPassages) {
        story.write('<p style="margin-top:2.5em;margin-bottom:2.3em">'
            '$sentence</p>');
      }
      archive.addFile(ArchiveFile.string('OEBPS/chapter$i.xhtml',
        '<?xml version="1.0" encoding="utf-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">'
        '<head><title>第${i + 1}章 · 笔记与记忆</title></head>'
        '<body>$story</body></html>'));
    }
    archive.addFile(ArchiveFile.string('OEBPS/nav.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head>'
      '<body><nav epub:type="toc"><ol>$nav</ol></nav></body></html>'));
    archive.addFile(ArchiveFile.string('OEBPS/content.opf',
      '<?xml version="1.0" encoding="utf-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">hyesread:visual</dc:identifier>'
      '<dc:title>笔记与记忆 · 排版验收样本</dc:title>'
      '<dc:language>zh-CN</dc:language></metadata>'
      '<manifest><item id="nav" href="nav.xhtml" '
      'media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="diagram" href="diagram.png" media-type="image/png"/>'
      '$items</manifest>'
      '<spine>$spine</spine></package>'));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    fixtureBytes = bytes;
    bookId = sha256.convert(bytes).toString();
    final books = Directory('${directory.path}/books')..createSync();
    final file = File('${books.path}/$bookId.epub')..writeAsBytesSync(bytes);
    File('${directory.path}/library.json').writeAsStringSync(jsonEncode({
      'version': 1, 'books': [{
        'id': bookId, 'title': '笔记与记忆 · 排版验收样本',
        'fileName': 'visual.epub', 'format': 'epub', 'path': file.path,
        'importedAt': 1, 'epubLocation': '9:0:0',
      }],
    }));
    repository = LibraryRepository(root: directory);
    await repository.load();
  });

  test('display normalization keeps block anchors while cutting large margins', () {
    final before = EpubBook.fromBytes(fixtureBytes);
    final updated = EpubBook.fromBytes(normalizeEpubForReading(fixtureBytes));
    final oldChapter = EpubChapter.fromBook(before, 9);
    final newChapter = EpubChapter.fromBook(updated, 9);
    expect(newChapter.blocks.length, oldChapter.blocks.length);
    final texts = newChapter.blocks.whereType<EpubTextBlock>()
        .where((block) => block.headingLevel == null).toList();
    expect(texts, isNotEmpty);
    expect(texts.first.style.marginTop?.value, 0);
    expect(texts.first.style.marginBottom?.value, closeTo(.55, .01));
    expect(texts.first.style.textIndent?.value, 2);
  });

  tearDownAll(() async {
    repository.dispose();
    // Windows can retain a ZIP or library-index handle briefly while the
    // reader's asynchronous persistence finishes.
    for (var i = 0; i < 12; i++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (i == 11) {
          // Windows retains a handle until flutter_tester itself exits.
          // Treat this as a fixture-cleanup warning, not a UI product failure.
          debugPrint('Deferred visual-fixture cleanup: $error');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    }
  });

  for (final (width, height) in <(int, int)>[
    (1920, 1080), (1280, 800), (390, 844)
  ]) {
    for (final name in ['paper', 'night']) {
      testWidgets('$width x $height $name real EPUB immersion and controls',
          (tester) async {
        SharedPreferences.setMockInitialValues({
          'paper': name == 'night' ? 'dark' : 'sepia',
          'fontKind': 'serif', 'fontSize': width < 600 ? 18.0 : 20.0,
          'lineHeight': 1.9, 'contentWidth': 640.0,
          'paragraphSpacing': 11.0, 'justifyText': true,
          'hyes.reader.pageMode': true,
        });
        tester.view.physicalSize = Size(width.toDouble(), height.toDouble());
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(MaterialApp(
          theme: hyesReadTheme(name == 'night'
              ? Brightness.dark : Brightness.light),
          home: ReaderPage(repository: repository, bookId: bookId),
        ));
        for (var i = 0;
             i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
          await tester.runAsync(() async => Future<void>.delayed(
              const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(find.byType(EpubReaderView), findsOneWidget);
        final displayed = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
        final paragraph = EpubChapter.fromBook(displayed.book, 9).blocks
            .whereType<EpubTextBlock>()
            .firstWhere((e) => e.headingLevel == null);
        expect(paragraph.style.marginTop?.value, 0);
        expect(paragraph.style.marginBottom?.value, closeTo(.55, .01));
        await tester.pump(const Duration(milliseconds: 440));
        expect(tester.takeException(), isNull);

        if (captureScreenshots) {
          await expectLater(find.byType(ReaderPage),
            matchesGoldenFile('goldens/reader-remake-${width}x$height-$name-immersive.png'));
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 330));
        expect(find.byKey(const ValueKey('reader-chapter-scrubber')), findsOneWidget);
        if (captureScreenshots) {
          await expectLater(find.byType(ReaderPage),
            matchesGoldenFile('goldens/reader-remake-${width}x$height-$name-controls.png'));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('wide EPUB shows consecutive facing leaves and turns in pairs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'sepia', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0; i < 40 &&
        find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    final reader = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(reader.mode, EpubReaderMode.spread);
    final imageBlocks = EpubChapter.fromBook(reader.book, 9).blocks
        .whereType<EpubImageBlock>().toList();
    expect(imageBlocks, isNotEmpty,
        reason: 'the spread fixture must contain an inline illustration');
    final imageBytes = reader.book.readBytes(imageBlocks.first.src);
    expect(imageBytes, isNotNull,
        reason: 'the illustration must resolve inside the EPUB archive');
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(imageBytes!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 700);
      expect(frame.image.height, 420);
      frame.image.dispose();
      codec.dispose();
    });
    final epubImages = find.byType(EpubImage);
    expect(epubImages, findsAtLeastNWidgets(1));
    await tester.runAsync(() async {
      await precacheImage(MemoryImage(imageBytes!),
          tester.element(epubImages.first));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widgetList<RawImage>(find.byType(RawImage)).any((raw) =>
          raw.image?.width == 700 && raw.image?.height == 420),
      isTrue,
      reason: 'the EPUB image must be decoded and painted on a real page',
    );
    expect(find.byKey(const ValueKey('epub-facing-pages')), findsOneWidget);
    expect(reader.controller!.facingPairCount, greaterThan(1));
    expect(reader.controller!.facingPairIndex, 0);
    final initial = reader.controller!.location;
    expect(initial.spineIndex, 9);
    if (captureScreenshots) {
      await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/epub-real-facing-pages-1280x800.png'));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('epub-next-chapter')));
    await tester.pumpAndSettle();
    expect(reader.controller!.facingPairIndex, 1);
    expect(reader.controller!.location.spineIndex, 9,
      reason: 'one facing-page turn must not skip the whole EPUB chapter');
    expect(reader.controller!.location, isNot(initial));
    await tester.tap(find.byKey(const ValueKey('epub-previous-chapter')));
    await tester.pumpAndSettle();
    expect(reader.controller!.facingPairIndex, 0);
    final spreadRect = tester.getRect(
        find.byKey(const ValueKey('epub-facing-pages')));
    final drag = await tester.startGesture(
        Offset(spreadRect.right - 18, spreadRect.center.dy));
    await drag.moveBy(const Offset(-96, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('epub-gesture-paper-finish')),
        findsOneWidget);
    if (captureScreenshots) {
      await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/epub-facing-page-fold-1280x800.png'));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(reader.controller!.facingPairIndex, 1,
        reason: 'dragging the outer paper edge advances one spread');
    await tester.tapAt(Offset(spreadRect.right - 18,
        spreadRect.bottom - 36));
    await tester.pumpAndSettle();
    expect(reader.controller!.facingPairIndex, 2,
        reason: 'tapping the lower outer corner turns one more spread');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact desktop EPUB still opens as facing pages',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'sepia', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0; i < 40 &&
        find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    final reader = tester.widget<EpubReaderView>(find.byType(EpubReaderView));
    expect(reader.mode, EpubReaderMode.spread,
        reason: 'the previous 1060px threshold wrongly forced this window to one page');
    expect(find.byKey(const ValueKey('epub-left-leaf')), findsOneWidget);
    expect(find.byKey(const ValueKey('epub-right-leaf')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('epub-left-leaf'))).width,
        greaterThan(300));
    expect(tester.getSize(find.byKey(const ValueKey('epub-right-leaf'))).width,
        greaterThan(300));
    if (captureScreenshots) {
      await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/epub-facing-pages-800x800.png'));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('EPUB chapter switch shows one short tactile chapter cue',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'sepia', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0;
        i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(EpubReaderView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    tester.widget<ChapterScrubber>(
        find.byKey(const ValueKey('reader-chapter-scrubber'))).onCommit(10);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('reader-chapter-transition')),
        findsOneWidget, reason: 'chapter cue must appear only after navigation');
    if (captureScreenshots) {
      await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/reader-motion-chapter-cue-1280x800.png'));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('reader-chapter-transition')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion skips EPUB chapter cue while still navigating',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'dark', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0;
        i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(EpubReaderView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 20));
    tester.widget<ChapterScrubber>(
        find.byKey(const ValueKey('reader-chapter-scrubber'))).onCommit(10);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('reader-chapter-transition')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bookmark addition stamps with a ring and removal settles cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'sepia', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0;
        i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(EpubReaderView), findsOneWidget);
    await tester.tapAt(const Offset(640, 400));
    await tester.pumpAndSettle();
    expect((tester.state(find.byType(ReaderPage)) as dynamic).focusReading,
        isFalse, reason: 'center tap must reveal the interactive reading chrome');
    final action = find.byKey(const ValueKey('reader-bookmark-action'));
    expect(action, findsOneWidget);
    expect(repository.byId(bookId)!.epubBookmarks, isEmpty,
        reason: 'fixture starts without a bookmark');
    expect((tester.state(find.byType(ReaderPage)) as dynamic).epubLocation,
        isNotEmpty, reason: 'the real EPUB location must be ready to bookmark');
    expect(tester.widget<IconButton>(action).onPressed, isNotNull);

    await tester.tap(action);
    // Let the animation acquire its initial frame before advancing time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(repository.byId(bookId)!.epubBookmarks, isNotEmpty,
        reason: 'bookmark animation follows a real persisted bookmark');
    expect(find.byKey(const ValueKey('reader-bookmark-stamp-ring')),
        findsOneWidget);
    if (captureScreenshots) {
      await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/reader-motion-bookmark-stamp-1280x800.png'));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-bookmark-stamp-ring')), findsNothing);

    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.runAsync(() async => Future<void>.delayed(
        const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
    expect(repository.byId(bookId)!.epubBookmarks, isEmpty);
    expect(find.byKey(const ValueKey('reader-bookmark-stamp-ring')), findsNothing,
        reason: 'removing a bookmark does not play the addition stamp');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion saves bookmark without stamp animation',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'dark', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0;
        i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(EpubReaderView), findsOneWidget);
    await tester.tapAt(const Offset(640, 400));
    await tester.pump(const Duration(milliseconds: 20));
    expect((tester.state(find.byType(ReaderPage)) as dynamic).focusReading,
        isFalse);
    expect((tester.state(find.byType(ReaderPage)) as dynamic).epubLocation,
        isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('reader-bookmark-action')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async => Future<void>.delayed(
        const Duration(milliseconds: 60)));
    await tester.pump();
    expect(repository.byId(bookId)!.epubBookmarks, isNotEmpty,
        reason: 'reduced motion disables animation, not the bookmark action');
    expect(find.byKey(const ValueKey('reader-bookmark-stamp-ring')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Aa panel changes the EPUB typeface and theme live on desktop',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'paper': 'sepia', 'hyes.reader.pageMode': true,
      'fontSize': 20.0, 'contentWidth': 640.0,
    });
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: ReaderPage(repository: repository, bookId: bookId),
    ));
    for (var i = 0;
         i < 40 && find.byType(EpubReaderView).evaluate().isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(EpubReaderView), findsOneWidget);
    await tester.tapAt(const Offset(640, 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((tester.state(find.byType(ReaderPage)) as dynamic).focusReading,
        isFalse, reason: 'center third must reveal toolbar without gesture-arena loss');
    expect(find.byKey(const ValueKey('reader-chapter-scrubber')), findsOneWidget);
    await tester.tap(find.byTooltip('阅读排版'));
    await tester.pumpAndSettle();
    expect(find.text('字体'), findsOneWidget);
    expect(find.text('宋体'), findsOneWidget);
    await tester.tap(find.text('楷体'));
    await tester.pump();
    expect(tester.widget<EpubReaderView>(find.byType(EpubReaderView))
        .settings.fontFamily, 'KaiTi');
    await tester.ensureVisible(find.byKey(const ValueKey('paper-theme-dark')));
    await tester.tap(find.byKey(const ValueKey('paper-theme-dark')));
    await tester.pump();
    expect(tester.widget<EpubReaderView>(find.byType(EpubReaderView))
        .settings.theme.backgroundColor, const Color(0xFF1A1815));
    await tester.tapAt(const Offset(30, 380));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
