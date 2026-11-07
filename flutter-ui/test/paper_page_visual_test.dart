import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/design/tokens.dart';
import 'package:hyesread_flutter/widgets/text_page_reader.dart';
import 'package:hyesread_flutter/ui/text_page_layout.dart';

/// Visual fixture loads the app's licensed CJK font rather than relying on
/// Flutter test's Ahem squares. Uses only original, fictional local text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final data = File('assets/fonts/HyesSerifSC-SemiBold.ttf').readAsBytesSync();
    final font = FontLoader(HyesTokens.serifFamily)
      ..addFont(Future.value(ByteData.sublistView(data)));
    await font.load();
  });

  testWidgets('desktop paged book has a readable Chinese paper layout',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const ink = Color(0xFF2B2620);
    const paper = Color(0xFFF4EEE2);
    final blocks = <String>[
      '第一章 纸上的灯',
      '黄昏落在窗台上，旧书的纸页在灯下慢慢显出温柔的颜色。有人在风里种树，'
          '有人把远方写进信里，而我只想留下这一间安静的书房。',
      '读书不是为了赶路。翻开一页，听见一句话，便知道这段时光属于自己。'
          '故事有时会停下，但那一页还在，等我们再一次回来。',
      '夜色渐深，木桌仍有微光。窗外的树影轻轻摇动，书脊像一条回家的路。',
      '这样的日子，慢一些也很好。',
    ];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        fontFamily: HyesTokens.serifFamily,
        scaffoldBackgroundColor: HyesTokens.light.background,
      ),
      home: Scaffold(body: TextPageReader(
        title: '纸上的灯', paragraphs: blocks,
        initialCursor: const TextPageCursor(0, 0),
        paper: paper, ink: ink,
        contentWidth: 680, fontSize: 21, lineHeight: 1.85,
        paragraphSpacing: 20, justify: false, topInset: 66,
        onPositionChanged: (_) {},
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(TextPageReader),
      matchesGoldenFile('goldens/desktop-facing-paged-reader.png'));
  });

  testWidgets('desktop long Chinese prose fills both facing pages',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const paper = Color(0xFFF4EEE2);
    const ink = Color(0xFF2B2620);
    final paragraphs = <String>[
      '第一章 江边书房',
      for (var i = 0; i < 12; i++)
        '窗外的江水缓缓流过，晚风拂动树影。'
        '桌上摊开的书页留着淡淡的墨香，'
        '远处灯火明灭，时间仿佛也安静下来。'
        '我们沿着熟悉的文字继续前行，'
        '不必急着抵达故事的终点。' * 3,
    ];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: HyesTokens.serifFamily),
      home: Scaffold(body: TextPageReader(
        title: '江边书房', paragraphs: paragraphs,
        initialCursor: const TextPageCursor(0, 0),
        paper: paper, ink: ink,
        contentWidth: 680, fontSize: 20, lineHeight: 1.85,
        paragraphSpacing: 15, justify: false, topInset: 46,
        onPositionChanged: (_) {},
      )),
    ));
    await tester.pumpAndSettle();
    final spread = find.byKey(const ValueKey('paper-facing-pages'));
    expect(spread, findsOneWidget);
    expect(find.descendant(of: spread, matching: find.byType(SelectionArea)),
        findsNWidgets(2));
    final content = tester.widgetList<Text>(find.descendant(
      of: spread, matching: find.byType(Text)))
        .map((e) => e.data ?? '').where((t) => t.trim().isNotEmpty).toList();
    expect(content.length, greaterThan(2));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(TextPageReader),
        matchesGoldenFile('goldens/desktop-facing-chinese-prose.png'));
  });
}
