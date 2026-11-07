import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/design/tokens.dart';
import 'package:hyesread_flutter/ui/text_page_layout.dart';
import 'package:hyesread_flutter/widgets/chapter_scrubber.dart';
import 'package:hyesread_flutter/widgets/text_page_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const motionScreenshots = bool.fromEnvironment('HYES_MOTION_SHOTS');
  const paper = Color(0xFFF4EEE2);
  const ink = Color(0xFF2B2620);
  const accent = Color(0xFFC8452F);

  setUpAll(() async {
    // Real Chinese glyphs in visual capture, not Ahem squares. System font
    // stays on the test machine and is never shipped as an app font file.
    final system = File('C:/Windows/Fonts/NotoSerifSC-VF.ttf');
    final font = (system.existsSync()
        ? system : File('assets/fonts/HyesSerifSC-SemiBold.ttf'))
        .readAsBytesSync();
    await (FontLoader(HyesTokens.serifFamily)
      ..addFont(Future.value(ByteData.sublistView(font)))).load();
    final materialIcons = File(
        '.flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (materialIcons.existsSync()) {
      await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(
            materialIcons.readAsBytesSync())))).load();
    }
  });

  testWidgets('chapter scrubber follows pointer and commits only on release',
      (tester) async {
    final committed = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 520, height: 90,
        child: ChapterScrubber(
          index: 4, count: 52, ink: ink, accent: accent, paper: paper,
          chapterLabel: (i) => '第 ${i + 1} 章 · 书房笔记',
          onCommit: committed.add,
        )),
    ))));

    final rect = tester.getRect(find.byType(ChapterScrubber));
    final y = rect.bottom - 22;
    final gesture = await tester.startGesture(Offset(rect.left + 100, y));
    await tester.pump(const Duration(milliseconds: 60));
    expect(committed, isEmpty);
    await gesture.moveTo(Offset(rect.right - 18, y));
    // Start the implicit animation on one frame; the next frame captures
    // its settled visual state rather than the initial 0-opacity frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('chapter-scrubber-preview-opacity')))
        .opacity, 1, reason: 'scrub-preview bubble must really be visible');
    final fade = tester.widget<FadeTransition>(find.descendant(
      of: find.byKey(const ValueKey('chapter-scrubber-preview-opacity')),
      matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, greaterThan(.95),
      reason: 'visual capture requires the preview to be painted, not merely built');
    expect(find.textContaining('第 52 章'), findsOneWidget);
    expect(committed, isEmpty, reason: 'drag preview never reads a book yet');
    if (motionScreenshots) {
      await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/reader-motion-scrubber-preview.png'));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(committed, [51], reason: 'release commits exactly one chapter');
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpLeaf(WidgetTester tester,
      List<TextPageCursor> positions, {bool reduced = false}) async {
    final phrases = List.generate(15, (i) =>
      '第 ${i + 1} 节 · 窗外风声逐渐安静。这里有一盏灯、一杯茶，'
      '以及一页尚未读完的故事。' * 24);
    await tester.pumpWidget(MaterialApp(
      builder: reduced ? (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ) : null,
      home: Scaffold(backgroundColor: const Color(0xFFECE3D0),
        body: TextPageReader(
          title: '书房里的静好时光', paragraphs: phrases,
          initialCursor: const TextPageCursor(0, 0),
          paper: paper, ink: ink, surround: const Color(0xFFECE3D0),
          contentWidth: 640, fontSize: 20, lineHeight: 1.9,
          paragraphSpacing: 11, justify: true, topInset: 0,
          onPositionChanged: positions.add,
        )),
    ));
    await tester.pump();
  }

  testWidgets('paper leaf turns with live fold shading and settles cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    expect(find.byKey(const ValueKey('reader-leaf-turn-shade')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(visited, isNotEmpty);
    expect(find.byKey(const ValueKey('reader-leaf-turn-shade')), findsWidgets);
    expect(find.byKey(const ValueKey('reader-leaf-turn-glint')), findsWidgets,
        reason: 'the moving leaf edge catches a short specular highlight');
    if (motionScreenshots) {
      await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/reader-motion-leaf-midturn-spread-1280x800.png'));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-leaf-turn-shade')), findsNothing);
    expect(find.byKey(const ValueKey('reader-leaf-turn-glint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page-turn handoff never double-exposes two lines of text',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pump();
    for (final step in [
      const Duration(milliseconds: 60),
      const Duration(milliseconds: 75),
      const Duration(milliseconds: 65),
    ]) {
      await tester.pump(step);
      final alphas = tester.widgetList<Opacity>(
        find.byKey(const ValueKey('reader-leaf-handoff')))
          .map((o) => o.opacity).toList();
      expect(alphas, isNotEmpty);
      expect(alphas.where((value) => value > .002), hasLength(1),
        reason: 'only one paper text layer may be visible at a time');
    }
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps page changes but eliminates fold shading',
      (tester) async {
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited, reduced: true);
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pump();
    expect(visited, isNotEmpty);
    expect(find.byKey(const ValueKey('reader-leaf-turn-shade')), findsNothing);
    expect(find.byKey(const ValueKey('reader-leaf-turn-glint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch drag follows the leaf before committing on release',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    final gesture = await tester.startGesture(
      const Offset(900, 380), kind: PointerDeviceKind.touch);
    await gesture.moveTo(const Offset(650, 385));
    await tester.pump();
    expect(visited, isEmpty, reason: 'drag must not prematurely save position');
    expect(find.byKey(const ValueKey('reader-live-drag-shade')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reader-live-drag-edge')),
        findsOneWidget);
    if (motionScreenshots) {
      await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/reader-motion-drag-preview-spread-1280x800.png'));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(visited, hasLength(1), reason: 'release commits one real page');
    expect(find.byKey(const ValueKey('reader-live-drag-shade')), findsNothing);

    // A short hesitant gesture eases the page back without changing position.
    final cancel = await tester.startGesture(
      const Offset(800, 380), kind: PointerDeviceKind.touch);
    await cancel.moveTo(const Offset(768, 382));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-live-drag-shade')),
        findsOneWidget);
    await cancel.up();
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    expect(find.byKey(const ValueKey('reader-live-drag-shade')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse body selection and reduced-motion swipe stay safe',
      (tester) async {
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    final mouse = await tester.startGesture(
      const Offset(550, 360), kind: PointerDeviceKind.mouse);
    await mouse.moveTo(const Offset(350, 362));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-live-drag-shade')), findsNothing);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(visited, isEmpty, reason: 'mouse body drag selects, not turns');

    await pumpLeaf(tester, visited, reduced: true);
    final touch = await tester.startGesture(
      const Offset(600, 350), kind: PointerDeviceKind.touch);
    await touch.moveTo(const Offset(420, 352));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-live-drag-shade')), findsNothing);
    await touch.up();
    await tester.pumpAndSettle();
    expect(visited, hasLength(1), reason: 'reduced motion still turns pages');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop mouse can turn from the actual centered paper margin',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    // Facing spread spans x=24..1256 here, not the full 1280px window.
    final outside = await tester.startGesture(
      const Offset(8, 350), kind: PointerDeviceKind.mouse);
    await outside.moveTo(const Offset(180, 352));
    await tester.pump();
    await outside.up();
    await tester.pumpAndSettle();
    expect(visited, isEmpty, reason: 'off-paper drag is not a page swipe');

    final edge = await tester.startGesture(
      const Offset(1238, 350), kind: PointerDeviceKind.mouse);
    await edge.moveTo(const Offset(760, 353));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-live-drag-shade')),
        findsOneWidget);
    expect(visited, isEmpty);
    await edge.up();
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse hover lifts only an available outer paper corner',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1100, 700));
    await mouse.moveTo(const Offset(1240, 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    final next = find.descendant(
      of: find.byKey(const ValueKey('paper-corner-next')),
      matching: find.byType(AnimatedOpacity));
    final previous = find.descendant(
      of: find.byKey(const ValueKey('paper-corner-previous')),
      matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(next).opacity, 1);
    expect(tester.widget<AnimatedOpacity>(previous).opacity, 0,
      reason: 'the first page has no previous page to curl');
    expect(visited, isEmpty, reason: 'hover never changes reading position');
    if (motionScreenshots) {
      await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/reader-motion-hover-corner-spread-1280x800.png'));
    }
    await mouse.moveTo(const Offset(620, 700));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(next).opacity, 0);
    await mouse.removePointer();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    final mouseBack = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouseBack.addPointer(location: const Offset(100, 690));
    await mouseBack.moveTo(const Offset(40, 690));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.widget<AnimatedOpacity>(previous).opacity, 1);
    await mouseBack.removePointer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion never shows a decorative corner fold',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final visited = <TextPageCursor>[];
    await pumpLeaf(tester, visited, reduced: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1100, 700));
    await mouse.moveTo(const Offset(1240, 700));
    await tester.pump();
    final next = find.descendant(
      of: find.byKey(const ValueKey('paper-corner-next')),
      matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(next).opacity, 0);
    await mouse.removePointer();
    await tester.tap(find.byKey(const ValueKey('paper-next-page')));
    await tester.pumpAndSettle();
    expect(visited, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
