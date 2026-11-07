import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/design/tokens.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/widgets/resume_carousel.dart';
import 'package:hyesread_flutter/widgets/book_spine_wall.dart';
import 'package:hyesread_flutter/widgets/rive_ink_waves.dart';
import 'package:hyesread_flutter/widgets/import_arrival.dart';
import 'package:hyesread_flutter/widgets/book_cover.dart';
import 'package:hyesread_flutter/widgets/ink_stamp.dart';

BookEntry _sample(int i) => BookEntry(
  id: i.toRadixString(16).padLeft(64, '0'),
  title: ['风起长安', '万卷山海', '书房夜话', '月落西窗'][i],
  fileName: 'sample$i.txt',
  format: 'txt',
  path: '/no-file-required/sample$i.txt',
  importedAt: 1730000000000,
  progress: .2 + .15 * i,
  lastOpenedAt: 1730000000000 + i,
);

void main() {
  setUpAll(() async {
    final font = ByteData.sublistView(
        File('assets/fonts/HyesSerifSC-SemiBold.ttf').readAsBytesSync());
    await (FontLoader(HyesTokens.serifFamily)
      ..addFont(Future.value(font))).load();
  });

  testWidgets('imported phone book shows one visible lower-right seal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Scaffold(body: ImportArrival(
        book: _sample(0), onFinished: () {})),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 820));
    expect(tester.widget<BookCover>(find.byType(BookCover)).showSeal,
        isFalse, reason: 'the animated stamp replaces the miniature seal');
    await expectLater(find.byType(ImportArrival),
        matchesGoldenFile('goldens/import-arrival-mobile-390.png'));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('import seal stays entirely inside the book cover at ${width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var completed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(Brightness.light),
        home: Scaffold(body: ImportArrival(
          book: _sample(0), onFinished: () => completed++)),
      ));
      await tester.pump(); // Start the one-shot import animation.
      await tester.pump(const Duration(milliseconds: 820));
      final cover = tester.getRect(find.byType(BookCover));
      final seal = tester.getRect(find.byType(InkStamp));
      expect(cover.contains(seal.topLeft), isTrue,
          reason: 'seal top-left must be inside the animated cover');
      expect(cover.contains(seal.bottomRight), isTrue,
          reason: 'seal bottom-right must be inside the animated cover');
      expect(seal.center.dx, greaterThan(cover.center.dx));
      expect(seal.center.dy, greaterThan(cover.center.dy));
      expect(completed, 0);
      await tester.pump(const Duration(milliseconds: 180));
      expect(completed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('three or more books use a calm native cover gallery', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final books = List.generate(4, _sample);
    BookEntry? selected;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: ResumeCarousel(
        books: books, onOpen: (book) => selected = book,
      ))),
    ));
    await tester.pump(const Duration(milliseconds: 850));
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-cover-gallery')),
      findsOneWidget);
    expect(find.text('风起长安'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final target = find.bySemanticsLabel('继续阅读《风起长安》');
    expect(target, findsOneWidget);
    await tester.tap(target);
    expect(selected?.title, '风起长安');
  });

  testWidgets('carousel arrows retain selected book across recent-book reorder',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var books = List.generate(4, _sample);
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return SingleChildScrollView(child: ResumeCarousel(
          books: books, onOpen: (_) {}));
      })),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byKey(const ValueKey('resume-next'))).width,
      greaterThanOrEqualTo(48));
    expect(tester.widget<PageView>(find.byType(PageView))
      .controller!.hasClients, isTrue);
    await tester.tap(find.byKey(const ValueKey('resume-next')));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView))
      .controller!.page!.round(), 1);
    expect(find.text('万卷山海'), findsOneWidget);

    update(() => books = [_sample(3), _sample(0), _sample(1), _sample(2)]);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('万卷山海'), findsOneWidget);
    final gallery = tester.widget<PageView>(find.byType(PageView));
    expect(gallery.controller!.page!.round(), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paper gallery position rail stays usable at 320dp and 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: ResumeCarousel(
        books: List.generate(4, _sample), onOpen: (_) {},
      ))),
    ));
    await tester.pump();
    expect(find.text('风起长安'), findsOneWidget);
    expect(find.text('01 / 04'), findsOneWidget);
    expect(find.bySemanticsLabel('第 1 部，共 4 部'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('resume-next'))).height,
      greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const ValueKey('resume-next')));
    await tester.pump();
    expect(find.text('02 / 04'), findsOneWidget);
    expect(find.bySemanticsLabel('第 2 部，共 4 部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single book shows no gallery chrome but still opens correctly',
      (tester) async {
    BookEntry? opened;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: ResumeCarousel(
        books: [_sample(0)], onOpen: (b) => opened = b,
      ))),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('resume-previous')), findsNothing);
    expect(find.byKey(const ValueKey('resume-next')), findsNothing);
    expect(find.byKey(const ValueKey('resume-position')), findsNothing);
    await tester.tap(find.text('继续阅读'));
    expect(opened?.title, '风起长安');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion keeps native pages and omits decorative transforms',
      (tester) async {
    final books = List.generate(4, _sample);
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: ResumeCarousel(
        books: books, onOpen: (_) {},
      ))),
    ));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('resume-cover-gallery')),
      findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book spines enter without vertical stretching and lift on hover',
      (tester) async {
    final books = List.generate(4, _sample);
    BookEntry? opened;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: Scaffold(body: BookSpineWall(
        books: books, onOpen: (b) => opened = b)),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BookSpineWall), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsNWidgets(4));
    final first = find.byKey(ValueKey('spine-${books.first.id}'));
    final hover = find.descendant(
      of: first, matching: find.byType(AnimatedSlide));
    expect(tester.widget<AnimatedSlide>(hover).offset, Offset.zero);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 50));
    await mouse.moveTo(tester.getCenter(first));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(hover).offset,
        const Offset(0, -.045));
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(hover).offset, Offset.zero);
    await tester.tap(first);
    expect(opened?.id, books.first.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rive ink layer remains safe without native library',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const Scaffold(body: Center(child: RiveInkWaves(
        impression: 1, size: 116,
      ))),
    ));
    await tester.pump();
    expect(find.byType(RiveInkWaves), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion skips import celebration without repeated callback',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: ImportArrival(book: _sample(0),
        onFinished: () => completed++)),
    ));
    await tester.pump();
    expect(completed, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(completed, 1);
    expect(tester.takeException(), isNull);
  });
}
