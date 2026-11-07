import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:hyesread_flutter/design/tokens.dart';
import 'package:hyesread_flutter/design/motion.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/ui/app_shell.dart';
import 'package:hyesread_flutter/ui/app_language.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/atelier_widgets.dart';
import 'package:hyesread_flutter/ui/atelier_stage.dart';
import 'package:hyesread_flutter/ui/atelier_command_palette.dart';
import 'package:hyesread_flutter/ui/paper_dock.dart';
import 'package:hyesread_flutter/ui/reader_page.dart';
import 'package:hyesread_flutter/widgets/text_page_reader.dart';
import 'package:hyesread_flutter/widgets/paper_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Widget tests must prepare real file fixtures outside the fake async clock.
/// Import and transactional persistence are covered separately by unit tests.
void seedBook(Directory root, String title, String text,
    {bool recentlyRead = false, int paragraphIndex = 0,
    double progress = 0}) {
  final bytes = utf8.encode(text);
  final hash = sha256.convert(bytes).toString();
  final books = Directory(root.path + '/books')..createSync(recursive: true);
  File(books.path + '/$hash.txt').writeAsBytesSync(bytes);
  File(root.path + '/library.json').writeAsStringSync(jsonEncode({
    'version': 1,
    'books': [{
      'id': hash,
      'title': title,
      'fileName': '$title.txt',
      'format': 'txt',
      'path': books.path + '/$hash.txt',
      'importedAt': DateTime.now().millisecondsSinceEpoch,
      'lastOpenedAt': recentlyRead ? DateTime.now().millisecondsSinceEpoch : null,
      'paragraphIndex': paragraphIndex,
      'progress': progress,
    }],
  }));
}

/// Explicitly reveal chrome; the redesigned reader intentionally opens
/// immersive rather than permanently showing a top bar.
Future<void> revealReaderChrome(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width / 2, size.height / 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 280));
}

Finder readingParagraph(String value) => find.byWidgetPredicate(
    (widget) => (widget is SelectableText && widget.data?.trimLeft() == value) ||
        (widget is Text && widget.data?.trimLeft() == value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('resume hero displays real percent instead of saved-position copy',
      (tester) async {
    final book = BookEntry(
      id: 'progress-display', title: '进度演示', fileName: 'sample.txt',
      format: 'txt', path: 'sample.txt', importedAt: 0,
      lastOpenedAt: 1, progress: .376,
    );
    for (final mode in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(mode),
        home: Scaffold(body: SizedBox(
          width: 1080,
          child: AtelierResumePoster(
            book: book,
            translate: (text) => text,
            onRead: () {},
            onBrowse: () {},
          ),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('atelier-reading-percent')),
          findsOneWidget);
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('已保存阅读位置'), findsNothing);
      expect(find.text('阅读位置已保存'), findsNothing);
    }
  });
  // Use the app's bundled, licensed Chinese font for visual snapshots.
  // flutter_test otherwise paints CJK as Ahem squares, hiding layout defects.
  setUpAll(() async {
    final data = File('assets/fonts/HyesSerifSC-SemiBold.ttf')
        .readAsBytesSync();
    final fontBytes = ByteData.sublistView(data);
    for (final family in [HyesTokens.serifFamily, 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(fontBytes))).load();
    }
    // Match production Material icons as well. Flutter's golden test font
    // substitutes missing icon glyphs with squares without this asset.
    final icons = File(
      '.flutter_sdk/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf').readAsBytesSync();
    await (FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });

  test('TXT search returns the reader stable UTF-16 paragraph anchor',
      () async {
    final dir = Directory.systemTemp.createTempSync('hyes-palette-offset-');
    try {
      final file = File('${dir.path}/search.txt');
      await file.writeAsString(
        '序章\n\n今天读书。\n\n窗边的星星透过玻璃。\n\n'
        '最后一页仍然写着星星。');
      final book = BookEntry(
        id: 'local-text-test', title: '中文试读',
        fileName: 'search.txt', format: 'txt',
        path: file.path, importedAt: 0);
      final matches = await findLocalTextMatches([book], '星星');
      expect(matches.length, 2);
      expect(matches.first.paragraphIndex, 2);
      expect(matches.last.paragraphIndex, 3);
      expect(matches.first.textOffset, greaterThan(0));
      expect(matches.first.preview, contains('星星'));
      expect(await findLocalTextMatches([book], '星星', maximum: 1),
          hasLength(1));
      expect(await findLocalTextMatches([book], ''), isEmpty);
      expect(await file.readAsString(), contains('窗边的星星透过玻璃'),
        reason: 'search never mutates the original book');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('HTML animation switch changes scope and keeps controls usable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-motion-toggle-');
    seedBook(root, '视觉动效开关', '正文保留');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    var enabled = true;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, refresh) => MaterialApp(
        theme: hyesReadTheme(Brightness.dark),
        home: HyesMotionScope(
          enabled: enabled,
          child: AppShell(repository: repo, mode: ThemeMode.dark,
            onModeChanged: (_) {},
            animationsEnabled: enabled,
            onAnimationsChanged: (value) =>
                refresh(() => enabled = value))),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-nav-3')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('atelier-animations-switch'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    final toggleContext = tester.element(toggle);
    expect(HyesMotion.reduced(toggleContext), isTrue);
    expect(HyesMotion.duration(toggleContext, HyesMotion.slow),
      Duration.zero);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('day and night share the same editorial layout and shelf',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-theme-parity-');
    seedBook(root, '同一座纸墨书房', '第一章\n\n夜与昼的同一页',
        recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    Rect? firstCover;
    Rect? firstAction;
    Rect? firstSidebar;
    Rect? firstFilter;
    for (final brightness in [Brightness.dark, Brightness.light]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        home: AppShell(repository: repo,
          mode: brightness == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {}),
      ));
      await tester.pumpAndSettle();
      final cover = tester.getRect(
        find.byKey(const ValueKey('atelier-night-cover')));
      final action = tester.getRect(
        find.byKey(const ValueKey('atelier-resume-open')));
      final sidebar = tester.getRect(
        find.byKey(const ValueKey('atelier-sidebar')));
      expect(cover.center.dx, lessThan(action.center.dx));
      expect(find.byKey(const ValueKey('atelier-resume-poster')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('atelier-night-atmosphere')),
          findsOneWidget);
      if (firstCover == null) {
        firstCover = cover; firstAction = action; firstSidebar = sidebar;
      } else {
        expect((cover.topLeft - firstCover.topLeft).distance,
            lessThan(1.1), reason: 'theme never rearranges the book');
        expect((action.topLeft - firstAction!.topLeft).distance,
            lessThan(1.1), reason: 'theme never moves the main CTA');
        expect(sidebar.size, firstSidebar!.size);
      }
      await tester.tap(find.byKey(const ValueKey('atelier-nav-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('atelier-single-book')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-search-open')),
          findsOneWidget);
      final filterRect = tester.getRect(
        find.byKey(const ValueKey('shelf-filter-0')));
      if (firstFilter == null) {
        firstFilter = filterRect;
      } else {
        expect((filterRect.topLeft - firstFilter.topLeft).distance,
            lessThan(1.1));
        expect(filterRect.size, firstFilter.size);
      }
      expect(find.byKey(const ValueKey('paper-import')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('resume hero shows reading percent without saved-position copy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-progress-ui-');
    seedBook(root, '有真实进度的书', '第一段。\n\n第二段。', recentlyRead: true,
      progress: .375);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('38%'), findsOneWidget);
    expect(find.textContaining('已保存'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('atelier-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('38%'), findsWidgets);
    expect(find.textContaining('已保存'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('one still brand seal and no redundant privacy copy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-single-mark-');
    seedBook(root, '一枚安静的书印', '第一章\n\n沉静的文字。',
      recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    for (final scenario in [
      (const Size(1280, 800), Brightness.dark),
      (const Size(1280, 800), Brightness.light),
      (const Size(390, 844), Brightness.light),
      (const Size(390, 844), Brightness.dark),
    ]) {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(scenario.$2),
        home: AppShell(
          repository: repo,
          mode: scenario.$2 == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      final mark = find.byType(AtelierBrandMark);
      expect(mark, findsOneWidget);
      expect(find.text('HyesRead'), findsNothing);
      expect(find.descendant(of: mark,
          matching: find.byType(AnimatedScale)), findsNothing);
      expect(find.descendant(of: mark,
          matching: find.byType(ScaleTransition)), findsNothing);
      expect(find.text('书籍与阅读记录仅保存在本机。'), findsNothing);
      final originalSize = tester.getSize(mark);
      final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: tester.getCenter(mark));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getSize(mark), originalSize,
          reason: 'the brand mark is not a bouncing button');
      await pointer.removePointer();

      await tester.tap(find.byKey(ValueKey(
        scenario.$1.width >= 840 ? 'atelier-nav-3' : 'paper-dock-3')));
      await tester.pumpAndSettle();
      for (final removed in [
        '本机与隐私', '书籍和阅读位置只保存在这台设备上。',
        '无需登录，不会自动上传书籍。', '版本 0.1.0',
      ]) {
        expect(find.text(removed), findsNothing);
      }
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('已隐藏的书籍'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('unified day and night editorial screenshots',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-editorial-day-night-');
    seedBook(root, '在纸页之间，望见群星',
        '第一章\n\n一束光静静落在书页上。', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        home: AppShell(repository: repo,
          mode: brightness == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {}),
      ));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      await expectLater(find.byType(AppShell), matchesGoldenFile(
        brightness == Brightness.dark
            ? 'goldens/editorial-night-1440.png'
            : 'goldens/editorial-day-1440.png'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('unified day and night single-book shelf screenshots',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-unified-shelf-');
    seedBook(root, '一封写给四季的信', '第一章\n\n纸页与花影。');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        home: AppShell(repository: repo,
          mode: brightness == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('atelier-single-book')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-search-open')),
          findsOneWidget);
      await expectLater(find.byType(AppShell), matchesGoldenFile(
        brightness == Brightness.dark
            ? 'goldens/editorial-shelf-night-1280.png'
            : 'goldens/editorial-shelf-day-1280.png'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('unified day and night mobile screenshots',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-unified-mobile-');
    seedBook(root, '雨后春山的读书人',
        '第一章\n\n文字没有离开纸页。', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        home: AppShell(repository: repo,
          mode: brightness == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {}),
      ));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('atelier-resume-poster')),
          findsOneWidget);
      final resume = tester.getRect(
          find.byKey(const ValueKey('atelier-resume-open')));
      final dock = tester.getRect(find.byType(PaperDock));
      expect(resume.bottom, lessThanOrEqualTo(dock.top - 6),
        reason: 'phone CTA must not be obscured by fixed navigation');
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(AppShell), matchesGoldenFile(
        brightness == Brightness.dark
            ? 'goldens/editorial-mobile-night-390.png'
            : 'goldens/editorial-mobile-day-390.png'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('mobile long-title hero uses the same side-by-side book composition',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const title = 'FBI微情绪心理学（若水集）金圣荣';
    final root = Directory.systemTemp.createTempSync('hyes-mobile-longtitle-');
    seedBook(root, title, '第一章\n\n继续从文字中前进。',
        recentlyRead: true, progress: .97);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        home: AppShell(repository: repo,
          mode: brightness == Brightness.dark
              ? ThemeMode.dark : ThemeMode.light,
          onModeChanged: (_) {}),
      ));
      await tester.pumpAndSettle();
      final hero = find.byKey(const ValueKey('atelier-resume-poster'));
      final cover = find.descendant(of: hero,
        matching: find.byKey(const ValueKey('atelier-night-cover')));
      final heading = find.descendant(of: hero, matching: find.text(title));
      expect(heading, findsOneWidget);
      final coverRect = tester.getRect(cover);
      final titleRect = tester.getRect(heading);
      expect(coverRect.right, lessThan(titleRect.left),
        reason: 'phone keeps the desktop book-left / text-right hierarchy');
      expect(titleRect.top, lessThan(coverRect.bottom),
        reason: 'the long title stays next to the book, not beneath it');
      expect(find.descendant(of: hero, matching: find.text('97%')),
        findsOneWidget);
      final action = tester.getRect(
        find.byKey(const ValueKey('atelier-resume-open')));
      final dock = tester.getRect(find.byType(PaperDock));
      expect(action.bottom, lessThanOrEqualTo(dock.top - 6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('uploaded HTML night hero puts actual cover left of main action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-html-night-');
    seedBook(root, '文学长夜与星辰',
      '第一章\n\n黑夜中的书页', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {})));
    await tester.pumpAndSettle();
    final hero = find.byKey(const ValueKey('atelier-resume-poster'));
    final cover = find.byKey(const ValueKey('atelier-night-cover'));
    final cta = find.byKey(const ValueKey('atelier-resume-open'));
    expect(hero, findsOneWidget);
    expect(tester.getSize(hero).width, closeTo(1080, 1));
    expect(cover, findsOneWidget);
    expect(tester.getRect(cover).center.dx,
      lessThan(tester.getRect(cta).center.dx));
    expect(find.byKey(const ValueKey('atelier-night-atmosphere')),
      findsOneWidget);
    expect(tester.takeException(), isNull);
    // A golden records the settled editorial pose, not the entrance frame.
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell),
      matchesGoldenFile('goldens/desktop-night-editorial-1920.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('Ctrl+K palette searches real books and navigates to shelf',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-html-search-');
    seedBook(root, '海风书信', '信件与海潮', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {})));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AtelierCommandPalette), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('atelier-command-input')), '海风');
    await tester.pumpAndSettle();
    expect(find.text('海风书信'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('atelier-command-input')), '书架');
    await tester.pumpAndSettle();
    expect(find.text('书架'), findsWidgets);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AtelierCommandPalette), findsNothing);
    expect(find.byKey(const ValueKey('shelf-filter-0')), findsOneWidget);
    expect(find.text('海风书信'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('command palette keyboard selection opens the highlighted page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-palette-keys-');
    seedBook(root, '松林札记', '雨夜书房', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AtelierCommandPalette), findsOneWidget);
    // The actual book precedes 'resume' and 'shelf'.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final selection = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('atelier-result-2')));
    expect((selection.decoration as BoxDecoration).color, isNotNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AtelierCommandPalette), findsNothing);
    expect(find.byKey(const ValueKey('shelf-filter-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('global text search opens the verified TXT paragraph offset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-search-jump-');
    seedBook(root, '山中星辰',
      '序章\n\n山里看云。\n\n第二章 窗\n\n'
      '在窗边发现一颗星星，仍然写着星星。',
      recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    final original = File(repo.books.single.path).readAsBytesSync();
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-command-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('atelier-command-input')), '星星');
    await tester.pump(const Duration(milliseconds: 210));
    final preview = find.textContaining('在窗边发现');
    for (var i = 0; i < 12 && preview.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 60)));
      await tester.pump();
    }
    expect(preview, findsWidgets);
    await tester.ensureVisible(preview.first);
    await tester.tap(preview.first);
    await tester.pump();
    for (var i = 0; i < 12 &&
        repo.books.single.paragraphIndex != 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 40)));
      await tester.pump();
    }
    expect(repo.books.single.paragraphIndex, 3);
    expect(repo.books.single.textOffset, greaterThan(0));
    expect(File(repo.books.single.path).readAsBytesSync(),
      orderedEquals(original));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 120));
    repo.dispose();
    await tester.runAsync(() async {
      for (var retry = 0; retry < 12; retry++) {
        try {
          if (root.existsSync()) root.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          // Native Windows file readers can release their handle a moment
          // after the ReaderPage is unmounted.
          await Future<void>.delayed(
            const Duration(milliseconds: 110));
        }
      }
      // This is a disposable test fixture, never an actual user library.
      debugPrint('Deferred temporary search fixture cleanup: ${root.path}');
    });
  });

  testWidgets('native Windows drop imports a real file without changing source',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-drop-library-');
    final source = File('${root.path}/original.txt')
      ..writeAsStringSync('原始的外部文件\n\n第二段书页。');
    final originalBytes = source.readAsBytesSync();
    final library = Directory('${root.path}/app');
    final repo = LibraryRepository(root: library);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    final target = find.byType(DropTarget);
    expect(target, findsOneWidget);
    expect(find.byKey(const ValueKey('atelier-drop-zone')),
      findsOneWidget);
    final rect = tester.getRect(target);
    final point = Offset(rect.left + 95, rect.top + 220);
    final initialZoneColor = (tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('atelier-drop-hover')))
        .decoration as BoxDecoration).color;
    Future<void> sendDesktopDrop(String event, Object args) async {
      final wait = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(event, args)),
        (_) => wait.complete(),
      );
      await wait.future;
    }
    await sendDesktopDrop('entered', [point.dx, point.dy]);
    await tester.pump();
    final highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('atelier-drop-hover')));
    expect((highlighted.decoration as BoxDecoration).color,
      isNot(initialZoneColor),
      reason: 'the native drag-enter event must reach the shelf drop target');
    await sendDesktopDrop('performOperation', [source.path]);
    for (var i = 0; i < 30 && repo.books.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 75)));
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(repo.books, hasLength(1),
      reason: 'native drop follows the same repository import path');
    expect(repo.books.single.title, 'original');
    expect(File(repo.books.single.path).readAsBytesSync(),
      orderedEquals(originalBytes));
    expect(source.readAsBytesSync(), orderedEquals(originalBytes),
      reason: 'the external dragged original is never modified');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    await tester.runAsync(() async {
      for (var retry = 0; retry < 10; retry++) {
        try {
          if (root.existsSync()) root.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 70));
        }
      }
    });
  });

  testWidgets('night records page renders one heading and one counter group',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-record-one-');
    seedBook(root, '动效测试书', '第一章\n\n写下这一页。',
      recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-nav-2')));
    await tester.pumpAndSettle();
    final recordHeadings = find.byWidgetPredicate(
      (w) => w is Text && w.data == '阅读记录' &&
          w.style?.fontSize == 39);
    expect(recordHeadings, findsOneWidget,
      reason: 'a duplicate records header compounds ghosting on tab switch');
    expect(find.text('仅呈现真实记录，不估算阅读时长'), findsNothing);
    expect(find.text('Only saved facts, never estimated reading hours'),
      findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('tab choreography mounts only one page, even on rapid changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-scenes-');
    seedBook(root, '页面切换测试', '第一章\n\n窗外的星光。',
      recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-nav-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-nav-0')));
    await tester.pump();

    for (final step in [const Duration(milliseconds: 125),
        const Duration(milliseconds: 110),
        const Duration(milliseconds: 130)]) {
      await tester.pump(step);
      final oldPage = find.byWidgetPredicate(
        (w) => w is Text && w.data == '阅读记录' &&
            w.style?.fontSize == 39);
      final newPage = find.byKey(const ValueKey('atelier-resume-poster'));
      expect(oldPage, findsNothing,
        reason: 'outgoing records are not even mounted behind the book');
      expect(newPage, findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('atelier-resume-poster')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('atelier-nav-1')));
    await tester.pump(const Duration(milliseconds: 85));
    await tester.tap(find.byKey(const ValueKey('atelier-nav-2')));
    await tester.pump(const Duration(milliseconds: 85));
    await tester.tap(find.byKey(const ValueKey('atelier-nav-0')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('atelier-resume-poster')), findsOneWidget);
    expect(find.byWidgetPredicate(
      (w) => w is Text && w.data == '阅读记录' &&
          w.style?.fontSize == 39), findsNothing);
    expect(find.byKey(const ValueKey('atelier-night-cover')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('night shelf shares one-book stage and sliding segmented tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-html-shelf-');
    seedBook(root, '夜色阅读', '尚未开启的书籍');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      home: AppShell(repository: repo, mode: ThemeMode.dark,
        onModeChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-filter-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('atelier-single-book')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-import')), findsOneWidget);
    expect(find.text('夜色阅读'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(AppShell),
      matchesGoldenFile('goldens/desktop-night-bookshelf-1280.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('HTML magnetic CTA follows mouse and returns to neutral',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: AtelierMagneticButton(
        child: FilledButton(onPressed: () {}, child: const Text('打开')))))));
    await tester.pumpAndSettle();
    Offset translation() {
      final container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('atelier-magnetic-motion')));
      final values = container.transform!.storage;
      return Offset(values[12], values[13]);
    }
    expect(translation(), Offset.zero);
    final region = tester.getRect(find.byKey(
      const ValueKey('atelier-magnetic-target')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(region.center + const Offset(35, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(translation().dx, greaterThan(2));
    await mouse.moveTo(const Offset(6, 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(translation(), Offset.zero);
  });

  testWidgets('editorial metadata enters in stages and respects reduce motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AtelierEditorialEnter(
        delay: .24,
        child: Text('书籍位置与操作'),
      )),
    ));
    await tester.pump();
    double opacity() => tester.widget<Opacity>(
      find.ancestor(of: find.text('书籍位置与操作'),
          matching: find.byType(Opacity)).first).opacity;
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 430));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const Scaffold(body: AtelierEditorialEnter(
        child: Text('减少动画仍可阅读'),
      )),
    ));
    await tester.pump();
    expect(tester.widget<Opacity>(find.ancestor(
      of: find.text('减少动画仍可阅读'),
      matching: find.byType(Opacity)).first).opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paper theatre has one finite three-dimensional entrance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-stage-entrance-');
    seedBook(root, '入场动效书籍', '原始内容');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 450, height: 520,
        child: AtelierStage(book: repo.books.single, coverWidth: 255,
          onOpen: () {}))))));
    List<double> matrix() => List<double>.from(tester.widget<Transform>(
      find.byKey(const ValueKey('atelier-book-transform'))).transform.storage);
    final initially = matrix();
    await tester.pump(const Duration(milliseconds: 390));
    final midway = matrix();
    await tester.pump(const Duration(milliseconds: 780));
    final settled = matrix();
    expect(initially, isNot(equals(midway)));
    expect(midway, isNot(equals(settled)));
    expect(tester.binding.hasScheduledFrame, isFalse,
      reason: 'art-directed entrance must not leave a permanent idle ticker');
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('paper theatre follows pointer and settles without idle frames',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-stage-test-');
    seedBook(root, '封面互动书籍', '原始内容');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: SizedBox(width: 450, height: 520,
        child: AtelierStage(book: repo.books.single, coverWidth: 255,
          onOpen: () => openCount++))))));
    await tester.pumpAndSettle();
    List<double> matrix() => List<double>.from(tester.widget<Transform>(
      find.byKey(const ValueKey('atelier-book-transform'))).transform.storage);
    final origin = matrix();
    await expectLater(find.byType(AtelierStage),
      matchesGoldenFile('goldens/atelier-stage-rest-450x520.png'));
    final rect = tester.getRect(find.byKey(
      const ValueKey('atelier-stage-hover')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(rect.center + const Offset(105, -95));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(matrix(), isNot(equals(origin)));
    expect(find.byKey(const ValueKey('atelier-specular-layer')),
      findsOneWidget,
      reason: 'a pointer-linked varnish sheen should move with the book');
    await expectLater(find.byType(AtelierStage),
      matchesGoldenFile('goldens/atelier-stage-hover-right-motion-20261106-450x520.png'));
    final topRight = matrix();
    await mouse.moveTo(rect.center + const Offset(-106, 93));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 270));
    expect(matrix(), isNot(equals(topRight)));
    await expectLater(find.byType(AtelierStage),
      matchesGoldenFile('goldens/atelier-stage-hover-left-motion-20261106-450x520.png'));
    await mouse.moveTo(const Offset(9, 9));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(matrix(), orderedEquals(origin));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.byKey(const ValueKey('atelier-stage-book')));
    expect(openCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('reduced-motion paper theatre stays still but remains clickable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-stage-access-');
    seedBook(root, '无动态书籍', '原始内容');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    var openCount = 0;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(body: Center(child: SizedBox(
        width: 420, height: 490,
        child: AtelierStage(book: repo.books.single, coverWidth: 245,
          onOpen: () => openCount++)))))));
    await tester.pumpAndSettle();
    List<double> matrix() => List<double>.from(tester.widget<Transform>(
      find.byKey(const ValueKey('atelier-book-transform'))).transform.storage);
    final from = matrix();
    final rect = tester.getRect(find.byKey(
      const ValueKey('atelier-stage-hover')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(rect.center + const Offset(70, -78));
    await tester.pump(const Duration(milliseconds: 450));
    expect(matrix(), orderedEquals(from));
    await tester.tap(find.byKey(const ValueKey('atelier-stage-book')));
    expect(openCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('language setting changes desktop navigation without changing book data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-language-');
    seedBook(root, '真实中文书名', '原文不能翻译成英文');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    var language = HyesLanguage.chinese;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, refresh) => MaterialApp(
        theme: hyesReadTheme(Brightness.light),
        home: AppShell(
          repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {},
          language: language,
          onLanguageChanged: (next) {
            refresh(() => language = next);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-nav-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-zh')), findsOneWidget);
    expect(find.byKey(const ValueKey('language-en')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('language-en')));
    await tester.pumpAndSettle();
    expect(language, HyesLanguage.english);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await expectLater(find.byType(AppShell),
        matchesGoldenFile('goldens/desktop-settings-en-atelier-v4.png'));
    await tester.tap(find.byKey(const ValueKey('atelier-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('My library'), findsWidgets);
    expect(find.text('真实中文书名'), findsOneWidget,
        reason: 'book metadata is never translated');
    await tester.tap(find.byKey(const ValueKey('atelier-nav-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-zh')));
    await tester.pumpAndSettle();
    expect(language, HyesLanguage.chinese);
    expect(find.text('语言'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('English reader chrome retains the original TXT paragraphs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-english-reader-');
    seedBook(root, '中文书名保留', '第一章\n\n原文内容不能被翻译',
        recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: HyesLanguageScope(
        language: HyesLanguage.english,
        child: ReaderPage(repository: repo, bookId: repo.books.single.id),
      ),
    ));
    for (var attempt = 0; attempt < 24; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(TextPageReader).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 35)));
    }
    await revealReaderChrome(tester);
    expect(find.byTooltip('Save & return to library'), findsOneWidget);
    expect(find.byTooltip('Bookmark this page'), findsOneWidget);
    expect(find.text('中文书名保留'), findsWidgets);
    expect(find.byType(TextPageReader), findsOneWidget);
    final settingsButton = find.byTooltip('Reading layout');
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();
    expect(find.text('Font'), findsOneWidget);
    expect(find.text('This book only'), findsOneWidget);
    expect(find.text('Paper theme'), findsOneWidget);
    expect(find.text('Page mode'), findsOneWidget);
    expect(find.text('快速选择'), findsNothing);
    expect(find.textContaining('本书使用独立排版'), findsNothing);
    expect(File(repo.books.single.path).readAsStringSync(),
        contains('原文内容不能被翻译'),
        reason: 'interface localization must not alter source book bytes');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('V4 desktop at 1920px centers a capped 1160px book poster',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-atelier-wide-');
    seedBook(root, '宽屏封面构图测试',
        '阅读原文不会被改动。\n\n下一段', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    final poster = find.byKey(const ValueKey('atelier-resume-poster'));
    expect(poster, findsOneWidget);
    expect(tester.getSize(poster).width, closeTo(1080, 1));
    final rect = tester.getRect(poster);
    expect(rect.center.dx, closeTo(1072, 2),
        reason: 'center within desktop content area, not viewport edge');
    expect(find.byKey(const ValueKey('atelier-sidebar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell),
        matchesGoldenFile('goldens/desktop-resume-atelier-v4-1920.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('V4 single-book desktop shelf keeps import and book on screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-atelier-shelf-');
    seedBook(root, '真实的单本书',
        '这是本机保存的原文，不是设计假数据。');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('atelier-single-book')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-import')), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-filter-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell),
        matchesGoldenFile('goldens/desktop-shelf-atelier-v4-1280.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('empty Windows shelf offers import without a demo preview',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-page-invitation-');
    final repository = LibraryRepository(root: root);
    await tester.runAsync(() => repository.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repository, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('try-turn-pages')), findsNothing);
    expect(find.byKey(const ValueKey('debug-demo-shelf')), findsNothing);
    expect(find.byKey(const ValueKey('paper-import')), findsOneWidget);
    expect(find.byKey(const ValueKey('atelier-drop-zone')), findsOneWidget);
    expect(repository.books, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('320px viewport with 200% text keeps primary controls visible', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-a11y-small-');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: AppShell(repository: repo, mode: ThemeMode.system,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PaperDock), findsOneWidget);
    expect(find.byTooltip('导入书籍'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
    await tester.pumpAndSettle();
    expect(find.text('暂无阅读记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('320px library with 200% text keeps book and archive control usable', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-large-text-books-');
    seedBook(root, '这是一本标题非常长的自有中文小说', '第一章\n\n第二章');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: AppShell(repository: repo, mode: ThemeMode.system,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byTooltip('书籍操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(AppShell),
        matchesGoldenFile('goldens/phone-books-large-text-atelier-v4.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('favorite menu is explicit and hiding requires confirmation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-favorite-ui-');
    seedBook(root, '我常翻的书', '第一章\n\n第二章');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('书籍操作'));
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(repo.books.single.archived, isFalse);
    expect(find.text('加入收藏'), findsOneWidget);
    await tester.tap(find.text('加入收藏'));
    await tester.pump();
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.text('收藏').evaluate().isNotEmpty) break;
    }
    expect(repo.favorites.single.title, '我常翻的书');
    await tester.ensureVisible(find.text('收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('我常翻的书'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('书籍操作'));
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
    await tester.tap(find.text('从书架隐藏'));
    await tester.pumpAndSettle();
    expect(repo.books, hasLength(1));
    expect(find.text('从书架隐藏这本书？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.books, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('home shows favorite once even if it was recently opened', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyesread-home-favorite-');
    seedBook(root, '常读的收藏书', '书的第一段', recentlyRead: true);
    final index = File(root.path + '/library.json');
    final metadata = jsonDecode(index.readAsStringSync()) as Map<String, dynamic>;
    final entries = metadata['books'] as List<dynamic>;
    final older = entries.single as Map<String, dynamic>;
    older['favorite'] = true;
    final bytes = utf8.encode('另一本书');
    final hash = sha256.convert(bytes).toString();
    File(root.path + '/books/$hash.txt').writeAsBytesSync(bytes);
    entries.add({
      'id': hash,
      'title': '最近打开的新书',
      'fileName': '最近打开的新书.txt',
      'format': 'txt',
      'path': root.path + '/books/$hash.txt',
      'importedAt': older['importedAt'],
      'lastOpenedAt': (older['lastOpenedAt'] as int) + 10000,
    });
    index.writeAsStringSync(jsonEncode(metadata));
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('常读的收藏书'), findsOneWidget);
    expect(find.text('最近打开的新书'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('320px recent card remains readable with 200% text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-compact-resume-');
    seedBook(root, '一本标题很长且要继续阅读的本地图书', '第一章\n\n第二章',
        recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('阅读进度'), findsOneWidget);
    expect(find.text('继续阅读'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('mobile empty library exposes import entry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-ui-phone-');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        repository: repo,
        mode: ThemeMode.system,
        onModeChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PaperDock), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('还没有书籍'), findsOneWidget);
    expect(find.text('添加文件'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('mobile glass dock switches pages without losing the library',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-glass-navigation-');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PaperDock), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-import')), findsNothing);
    expect(find.byTooltip('导入书籍'), findsNothing);
    expect(find.text('A ROOM FOR STORIES'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('shelf-search-open')));
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('暂无阅读记录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-dock-3')));
    await tester.pumpAndSettle();
    expect(find.text('本机与隐私'), findsNothing);
    expect(find.text('选择界面显示的语言'), findsNothing);
    expect(find.text('挑一张喜欢的纸。'), findsNothing);
    expect(find.text('关闭装饰动画，保留正常阅读和操作。'), findsNothing);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paper-dock-1')));
    await tester.pumpAndSettle();
    expect(find.text('还没有书籍'), findsOneWidget);
    expect(repo.books, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('liquid appearance controls work on 320dp at 200% text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-liquid-mode-');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    var selected = ThemeMode.system;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, refresh) => MaterialApp(
        theme: hyesReadTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AppShell(repository: repo, mode: selected,
          onModeChanged: (next) => refresh(() => selected = next)),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-dock-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appearance-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('appearance-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('appearance-dark')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('appearance-dark')));
    await tester.pumpAndSettle();
    expect(selected, ThemeMode.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('reader settings remain usable on 320px at 200% text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-large-settings-');
    seedBook(root, '阅读排版可访问性验证', '第一章\n\n内容');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    await tester.pump();
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byTooltip('阅读排版').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(find.byTooltip('阅读排版'), findsOneWidget);
    await revealReaderChrome(tester);
    await tester.tap(find.byTooltip('阅读排版'));
    // File-backed reader loading may keep its spinner animating; wait for the
    // settings content, not for every animation in the app to stop.
    await tester.pump();
    for (var attempt = 0; attempt < 15; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('纸张主题').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(find.text('纸张主题'), findsOneWidget);
    expect(find.text('只调整这本书'), findsOneWidget);
    expect(find.text('段落排版'), findsOneWidget);
    expect(find.text('两端对齐'), findsOneWidget);
    expect(find.text('宽松'), findsOneWidget);
    expect(find.text('舒适'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('per-book typography updates live prose without overwriting global settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'fontSize': 19.0, 'lineHeight': 1.85, 'paper': 'sepia',
      'hyes.reader.pageMode': false,
    });
    tester.view.physicalSize = const Size(480, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-one-book-layout-');
    seedBook(root, '独立排版书籍',
        List.generate(100, (i) => '舒适阅读测试段落 ${i + 1}').join('\n\n'),
        paragraphIndex: 45);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    final body = readingParagraph('舒适阅读测试段落 46');
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (body.evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(body, findsOneWidget);
    expect(tester.widget<SelectableText>(body).style!.fontSize, 19);
    await revealReaderChrome(tester);
    await tester.tap(find.byTooltip('阅读排版'));
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PaperToggle).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(find.byType(PaperToggle), findsOneWidget);
    await tester.tap(find.byType(PaperToggle));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.widget<PaperToggle>(find.byType(PaperToggle)).value) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(tester.widget<PaperToggle>(find.byType(PaperToggle)).value, true);
    await tester.ensureVisible(find.text('宽松'));
    await tester.tap(find.text('宽松'));
    await tester.pump();
    await tester.ensureVisible(find.text('两端对齐'));
    await tester.tap(find.text('两端对齐'));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (prefs.getBool('reader.book.${repo.books.single.id}.justifyText') == true) break;
    }
    final prefix = 'reader.book.${repo.books.single.id}.';
    expect(prefs.getBool('${prefix}override'), true);
    expect(prefs.getDouble('${prefix}fontSize'), 22);
    expect(prefs.getBool('${prefix}justifyText'), true);
    expect(prefs.getDouble('fontSize'), 19);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(body, findsOneWidget);
    expect(tester.widget<SelectableText>(body).style!.fontSize, 22);
    expect(tester.widget<SelectableText>(body).textAlign, TextAlign.justify);
    expect(repo.books.single.paragraphIndex, 45);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (body.evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(body, findsOneWidget);
    expect(tester.widget<SelectableText>(body).style!.fontSize, 22);
    await revealReaderChrome(tester);
    await tester.tap(find.byTooltip('阅读排版'));
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PaperToggle).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await tester.tap(find.byType(PaperToggle));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.widget<PaperToggle>(find.byType(PaperToggle)).value) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(tester.widget<PaperToggle>(find.byType(PaperToggle)).value, false);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(body).style!.fontSize, 19);
    expect(prefs.getDouble('fontSize'), 19);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('reader arrow keys turn inside a chapter, not skip chapters',
      (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': true});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-arrow-pages-');
    final blocks = <String>[
      '第一章 开始',
      for (var i = 0; i < 70; i++)
        List.filled(4, '第一章第 $i 段。这段文字属于第一章，并没有到第二章。'
            '一页应该只翻到后续几段，不能跳过整章。').join(),
      '第二章 终点',
      '真正的第二章文字。',
    ];
    seedBook(root, '方向键逐页翻阅', blocks.join('\n\n'));
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(TextPageReader).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    final pager = find.byType(TextPageReader);
    expect(pager, findsOneWidget);
    final before = tester.state<TextPageReaderState>(pager).currentCursor;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final after = tester.state<TextPageReaderState>(pager).currentCursor;
    expect(after, isNot(before));
    expect(after.paragraph, lessThan(71),
      reason: 'a right arrow advances the current page, not chapter two');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A fixture can remain open until its native file handle closes.
    }
  });

  testWidgets('focus mode keeps viewport dimensions and restored TXT location', (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': false});
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-focus-');
    seedBook(root, '专注阅读测试', List.generate(120, (i) => '段落 ${i + 1}').join('\n\n'),
        paragraphIndex: 64);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(home: ReaderPage(
      repository: repo, bookId: repo.books.single.id,
    )));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (readingParagraph('段落 65').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(readingParagraph('段落 65'), findsOneWidget);
    final viewport = tester.getSize(find.byType(ScrollablePositionedList));
    await revealReaderChrome(tester);
    expect(find.byTooltip('进入专注阅读'), findsOneWidget);
    await tester.tap(find.byTooltip('进入专注阅读'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byTooltip('标记当前位置')).dy,
        lessThan(0), reason: 'chrome must slide entirely off the paper');
    expect(tester.getSize(find.byType(ScrollablePositionedList)), viewport);
    expect(readingParagraph('段落 65'), findsOneWidget);
    await expectLater(find.byType(ReaderPage),
        matchesGoldenFile('goldens/desktop-focus-reader.png'));
    await revealReaderChrome(tester);
    expect(find.byTooltip('标记当前位置'), findsOneWidget);
    expect(tester.getSize(find.byType(ScrollablePositionedList)), viewport);
    expect(repo.books.single.paragraphIndex, 64);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('narrow reader exposes focus and bookmarks without clipping', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-narrow-focus-');
    seedBook(root, '窄屏专注阅读', '第一章\n\n内容');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    await tester.pump();
    await revealReaderChrome(tester);
    expect(find.byTooltip('更多阅读操作'), findsOneWidget);
    await tester.tap(find.byTooltip('更多阅读操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('专注阅读'), findsOneWidget);
    await tester.tap(find.text('专注阅读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getTopLeft(find.byTooltip('标记当前位置')).dy,
        lessThan(0));
    expect(tester.takeException(), isNull);
    await revealReaderChrome(tester);
    expect(find.byTooltip('标记当前位置'), findsOneWidget);
    await tester.tap(find.byTooltip('更多阅读操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('书签列表'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('我的书签'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('TXT can seek to a paragraph and return without changing viewport', (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': false});
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-seek-');
    seedBook(root, '段落定位测试',
        List.generate(120, (i) => '定位段落 ${i + 1}').join('\n\n'),
        paragraphIndex: 64);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    for (var attempt = 0; attempt < 25; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (readingParagraph('定位段落 65').evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(readingParagraph('定位段落 65'), findsOneWidget);
    final viewport = tester.getSize(find.byType(ScrollablePositionedList));
    await revealReaderChrome(tester);
    expect(find.textContaining('第 65 / 120 段'), findsOneWidget);
    await tester.tap(find.byTooltip('跳转阅读位置'));
    await tester.pumpAndSettle();
    expect(find.text('目标段落预览'), findsOneWidget);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(80);
    await tester.pump();
    expect(find.text('第 81 / 120 段'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is Text &&
        widget.data == '定位段落 81'), findsOneWidget); // destination preview
    await tester.tap(find.text('跳转到此处'));
    await tester.pumpAndSettle();
    expect(readingParagraph('定位段落 81'), findsOneWidget);
    expect(tester.getSize(find.byType(ScrollablePositionedList)), viewport);
    await tester.tap(find.text('返回原处'));
    await tester.pumpAndSettle();
    expect(readingParagraph('定位段落 65'), findsOneWidget);
    expect(tester.getSize(find.byType(ScrollablePositionedList)), viewport);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('TXT seek persists when leaving immediately and reopening', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-seek-persist-');
    seedBook(root, '跳转后退出测试',
        List.generate(90, (i) => '保存段落 ${i + 1}').join('\n\n'));
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: AppShell(repository: repo, mode: ThemeMode.light,
          onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-feature-open')));
    for (var attempt = 0; attempt < 25; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (readingParagraph('保存段落 1').evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await revealReaderChrome(tester);
    await tester.tap(find.byTooltip('跳转阅读位置'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(39);
    await tester.pump();
    await tester.tap(find.text('跳转到此处'));
    await tester.pumpAndSettle();
    expect(readingParagraph('保存段落 40'), findsOneWidget,
        reason: 'visible text: ${tester.widgetList<SelectableText>(
          find.byType(SelectableText)).map((w) => w.data).take(24).toList()}');
    await tester.tap(find.byTooltip('保存并返回书架'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(ReaderPage).evaluate().isEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    // The new 520ms route and its Hero reverse flight can outlive the disk
    // snapshot; settle both only after the real position-save future finishes.
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.byType(ReaderPage), findsNothing);
    expect(repo.books.single.paragraphIndex, 39);
    await tester.tap(find.byKey(const ValueKey('atelier-feature-open')));
    for (var attempt = 0; attempt < 25; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (readingParagraph('保存段落 40').evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    expect(readingParagraph('保存段落 40'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('Ctrl+K inside TXT reader jumps only after confirming a result',
      (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': true});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-reader-find-');
    seedBook(root, '本书正文搜索',
      List.generate(65, (i) => i == 40
          ? '第 41 段银河定位。真正的正文搜索结果应来到这里。'
          : '第 ${i + 1} 段安静的读书时光。').join('\n\n'));
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    for (var attempt = 0; attempt < 25; attempt++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.byType(TextPageReader).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-search-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')), '银河定位');
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-search-hit-0')), findsOneWidget);
    // Escape must not alter the last saved reading position.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(repo.books.single.paragraphIndex, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reader-search-input')), '银河定位');
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reader-search-hit-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-search-dialog')), findsNothing);
    expect(find.textContaining('银河定位'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold the temporary fixture until its pending IO closes.
    }
  });

  testWidgets('320px navigation sheet at 200% text is cancellable and safe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-seek-small-');
    seedBook(root, '小屏定位测试',
        List.generate(80, (i) => '第 ${i + 1} 段文字').join('\n\n'),
        paragraphIndex: 30);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: ReaderPage(repository: repo, bookId: repo.books.single.id),
    ));
    for (var attempt = 0; attempt < 25; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ScrollablePositionedList).evaluate().isNotEmpty) break;
      await tester.runAsync(() =>
          Future<void>.delayed(const Duration(milliseconds: 40)));
    }
    await revealReaderChrome(tester);
    expect(find.textContaining('第 31 / 80 段'), findsOneWidget);
    await tester.tap(find.byTooltip('更多阅读操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳转阅读位置'));
    await tester.pumpAndSettle();
    expect(find.text('目标段落预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 31 / 80 段'), findsOneWidget);
    expect(repo.books.single.paragraphIndex, 30);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('TXT restores the persisted paragraph in a reopened reader', (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': false});
    tester.view.physicalSize = const Size(420, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-resume-test-');
    final content = List.generate(110, (i) => '段落 ${i + 1}').join('\n\n');
    seedBook(root, '段落恢复测试', content, paragraphIndex: 64);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());
    expect(repo.books.single.paragraphIndex, 64);
    await tester.pumpWidget(MaterialApp(home: ReaderPage(
      repository: repo, bookId: repo.books.single.id,
    )));
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (readingParagraph('段落 65').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    final shown = tester.widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data).take(12).toList();
    expect(readingParagraph('段落 65'), findsOneWidget,
      reason: '当前实际渲染的文本: $shown');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('desktop resumes the last-read book', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-ui-wide-');
    seedBook(root, '我在读的一本书', '我在读的一本书\n\n下一段', recentlyRead: true);
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());

    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(
        repository: repo,
        mode: ThemeMode.system,
        onModeChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('atelier-sidebar')), findsOneWidget);
    expect(find.byType(PaperDock), findsNothing);
    expect(find.text('阅读进度'), findsOneWidget);
    expect(find.text('我在读的一本书'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    await expectLater(find.byType(AppShell),
        matchesGoldenFile('goldens/desktop-resume-atelier-v4.png'));

    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });

  testWidgets('text reader opens, bookmarks, and exits safely', (tester) async {
    SharedPreferences.setMockInitialValues({'hyes.reader.pageMode': false});
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyesread-ui-reader-');
    seedBook(root, '阅读测试', '第一章\n\n阅读测试正文');
    final repo = LibraryRepository(root: root);
    await tester.runAsync(() => repo.load());

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        repository: repo,
        mode: ThemeMode.system,
        onModeChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('atelier-feature-open')));
    // The reader displays an indeterminate spinner until real file I/O
    // completes; pumpAndSettle must not be used during that loading state.
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byWidgetPredicate((w) =>
          w is SelectableText && w.data == '第一章').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(find.byWidgetPredicate((w) =>
        w is SelectableText && w.data == '第一章'), findsOneWidget);
    await revealReaderChrome(tester);
    expect(find.byTooltip('标记当前位置'), findsOneWidget);
    await tester.tap(find.byTooltip('标记当前位置'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(repo.books.first.textBookmarks, isNotEmpty);

    await tester.tap(find.byTooltip('保存并返回书架'));
    await tester.pump();
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PaperDock).evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 80));
    expect(find.byType(PaperDock), findsOneWidget);
    expect(repo.books.first.lastOpenedAt, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
    root.deleteSync(recursive: true);
  });
}
