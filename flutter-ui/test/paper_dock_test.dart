import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/paper_dock.dart';
import 'package:hyesread_flutter/widgets/paper_button.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('paper dock $brightness keeps four 48dp targets at 320dp / 200%',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var selected = 0;
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: const Center(child: Text('书房')),
          bottomNavigationBar: StatefulBuilder(
            builder: (context, refresh) => PaperDock(
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
      expect(find.byType(PaperDock), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      for (var i = 0; i < 4; i++) {
        final target = tester.getSize(find.byKey(ValueKey('paper-dock-$i')));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paper button hover lifts once, resets, and does not activate',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: PaperButton(
        label: '开始阅读', onPressed: () => taps++)),
    )));
    final slide = find.descendant(
      of: find.byType(PaperButton),
      matching: find.byType(AnimatedSlide));
    final decorated = find.descendant(
      of: find.byType(PaperButton),
      matching: find.byType(AnimatedContainer));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(find.byType(PaperButton)));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(slide).offset,
      const Offset(0, -.025));
    final raised = tester.widget<AnimatedContainer>(decorated)
        .decoration! as BoxDecoration;
    expect(raised.boxShadow, isNotEmpty);
    expect(taps, 0);
    await mouse.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(slide).offset, Offset.zero);
    await mouse.removePointer();
    await tester.tap(find.byType(PaperButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and disabled paper buttons never lift',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!),
      home: Scaffold(body: Center(child: PaperButton(
        label: '继续阅读', onPressed: () => taps++))),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(tester.getCenter(find.byType(PaperButton)));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
    await tester.tap(find.byType(PaperButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await mouse.removePointer();

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: PaperButton(
        label: '不可用', onPressed: null))),
    ));
    final disabledMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await disabledMouse.addPointer(location: const Offset(10, 10));
    await disabledMouse.moveTo(tester.getCenter(find.byType(PaperButton)));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
    await disabledMouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
