import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/glass_widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  testWidgets('320dp / 200% text glass dock keeps four accessible tap targets',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: const Center(child: Text('书房')),
        bottomNavigationBar: StatefulBuilder(
          builder: (context, refresh) => GlassDock(
            selectedIndex: selected,
            onSelected: (value) => refresh(() => selected = value),
            icons: const [
              Icons.auto_stories_outlined,
              Icons.library_books_outlined,
              Icons.insights_outlined,
              Icons.tune_rounded,
            ],
            labels: const ['续读', '书架', '记录', '设置'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GlassDock), findsOneWidget);
    expect(find.byKey(const ValueKey('glass-dock-indicator')), findsOneWidget);
    expect(find.byType(LiquidLens), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    for (var index = 0; index < 4; index++) {
      final size = tester.getSize(find.byKey(ValueKey('glass-dock-$index')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byKey(const ValueKey('glass-dock-2')));
    await tester.pumpAndSettle();
    expect(selected, 2);
    final alignment = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
    expect((alignment.alignment as Alignment).x, closeTo(1 / 3, 0.000001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('jelly press animation keeps the original tap behavior',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 200, height: 120,
        child: JellyCard(
          onTap: () => taps++,
          child: const Center(child: Text('打开书籍')),
        ),
      ))),
    ));
    final gesture = await tester.startGesture(
        tester.getCenter(find.text('打开书籍')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        closeTo(0.976, 0.00001));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion omits glass blur and jelly scale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(body: Center(child: GlassSurface(
        child: SizedBox(width: 200, height: 120, child: JellyCard(
          onTap: () {}, child: const Center(child: Text('安静阅读')),
        )),
      ))),
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    final gesture = await tester.startGesture(
        tester.getCenter(find.text('安静阅读')));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
