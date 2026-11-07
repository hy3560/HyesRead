import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real CJK glyph comparison. Synthetic, original reading passages; no
/// copyrighted book is copied into test fixtures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/NotoSerifSC-VF.ttf');
    final bytes = (font.existsSync() ? font
        : File('assets/fonts/HyesSerifSC-SemiBold.ttf')).readAsBytesSync();
    await (FontLoader('ChineseReading')..addFont(Future.value(
        ByteData.sublistView(bytes)))).load();
  });

  const samples = <String>[
    '她问：“这里还有灯吗？”“有。”窗外的风渐渐停了，书页安静下来。',
    '“你会回来吗？”“会的。”他说。离别不等于遗忘，那些日子仍在心里。',
    '纸页上写着：“请记得这一刻。”她想：“也许每一段路都值得珍惜。”',
    '我们讨论“什么才是答案？”“先学会提出问题。”他把笔记收进书里。',
    '“这样就够了吗？”“还不够。”又一行字在灯下慢慢浮现，夜已深了。',
  ];

  testWidgets('compare default/palt/halt at five real Chinese passages',
      (tester) async {
    tester.view.physicalSize = const Size(1536, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget column(String label, List<FontFeature> features) =>
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontFamily: 'ChineseReading',
              fontSize: 18,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          for (var i = 0; i < samples.length; i++) ...[
            Text('样例 ${i + 1}', style: const TextStyle(
                fontFamily: 'ChineseReading', fontSize: 12)),
            const SizedBox(height: 4),
            Text(samples[i], textAlign: TextAlign.justify,
              style: TextStyle(fontFamily: 'ChineseReading',
                  color: const Color(0xFF2B2620), fontSize: 19,
                  height: 1.9, letterSpacing: .38,
                  fontFeatures: features)),
            const SizedBox(height: 20),
          ],
        ]));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(backgroundColor: const Color(0xFFF4EEE2),
        body: Padding(padding: const EdgeInsets.all(32),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column('默认 · 无标点挤压', const []),
              const SizedBox(width: 28),
              column('palt · 比例标点', const [FontFeature.enable('palt')]),
              const SizedBox(width: 28),
              column('halt · 半宽标点', const [FontFeature.enable('halt')]),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/reader-punctuation-default-palt-halt.png'));
  });
}
