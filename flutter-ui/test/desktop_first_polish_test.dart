import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/ui/app_shell.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/atelier_widgets.dart';
import 'package:hyesread_flutter/ui/paper_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('phone dock shares desktop forest rail and navigation glyphs: '
        '$brightness', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const icons = [
        Icons.auto_stories_outlined, Icons.library_books_outlined,
        Icons.insights_outlined, Icons.tune_rounded,
      ];
      await tester.pumpWidget(MaterialApp(
        theme: hyesReadTheme(brightness).copyWith(
          platform: TargetPlatform.android),
        home: const Scaffold(bottomNavigationBar: PaperDock(
          selectedIndex: 0,
          onSelected: _noop,
          icons: icons,
          labels: ['续读', '书架', '记录', '设置'],
        )),
      ));
      await tester.pumpAndSettle();
      final decoration = tester.widget<DecoratedBox>(find.descendant(
        of: find.byType(PaperDock), matching: find.byType(DecoratedBox)).first)
          .decoration as BoxDecoration;
      expect(decoration.color, brightness == Brightness.dark
          ? AtelierColor.nightRail : AtelierColor.darkForest);
      for (final icon in icons) {
        expect(find.descendant(of: find.byType(PaperDock),
            matching: find.byIcon(icon)), findsOneWidget);
      }
      final selected = tester.widget<Icon>(find.byIcon(icons.first));
      expect(selected.color, AtelierColor.nightAccent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone reading records align three desktop-style counters',
      (tester) async {
    final repo = await _emptyRepository(tester);
    await _pumpPhone(tester, repo);
    await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
    await tester.pumpAndSettle();
    final a = tester.getTopLeft(find.byKey(
        const ValueKey('atelier-record-stat-书架藏书')));
    final b = tester.getTopLeft(find.byKey(
        const ValueKey('atelier-record-stat-已经开始')));
    final c = tester.getTopLeft(find.byKey(
        const ValueKey('atelier-record-stat-书签')));
    expect((a.dy - b.dy).abs(), lessThan(2));
    expect((a.dy - c.dy).abs(), lessThan(2));
    expect(a.dx, lessThan(b.dx));
    expect(b.dx, lessThan(c.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tab change settles without prolonged three-dimensional '
      'motion', (tester) async {
    final repo = await _emptyRepository(tester);
    await _pumpPhone(tester, repo);
    await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    final metric = find.byKey(const ValueKey('atelier-record-stat-书签'));
    final settled = tester.getTopLeft(metric);
    await tester.pump(const Duration(milliseconds: 380));
    expect((tester.getTopLeft(metric) - settled).distance, lessThan(.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty settings do not explain an already empty hidden shelf',
      (tester) async {
    final repo = await _emptyRepository(tester);
    await _pumpPhone(tester, repo);
    await tester.tap(find.byKey(const ValueKey('paper-dock-3')));
    await tester.pumpAndSettle();
    expect(find.text('已隐藏的书籍'), findsOneWidget);
    expect(find.text('目前没有隐藏的书。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp at 200% keeps editorial page titles within one line',
      (tester) async {
    final repo = await _emptyRepository(tester);
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light).copyWith(
        platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: AppShell(repository: repo, mode: ThemeMode.light,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.text('我的书架').last).height, lessThan(90));
    await tester.tap(find.byKey(const ValueKey('paper-dock-2')));
    await tester.pumpAndSettle();
    final title = find.byWidgetPredicate((widget) =>
        widget is Text && widget.data == '阅读记录');
    expect(tester.getSize(title.last).height, lessThan(90));
    expect(tester.takeException(), isNull);
  });
}

void _noop(int _) {}

Future<LibraryRepository> _emptyRepository(WidgetTester tester) async {
  final root = Directory.systemTemp.createTempSync('hyes-desktop-first-');
  final repo = LibraryRepository(root: root);
  addTearDown(() {
    repo.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  await tester.runAsync(() => repo.load());
  return repo;
}

Future<void> _pumpPhone(WidgetTester tester, LibraryRepository repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: hyesReadTheme(Brightness.light).copyWith(
      platform: TargetPlatform.android),
    home: AppShell(repository: repo, mode: ThemeMode.light,
      onModeChanged: (_) {}),
  ));
  await tester.pumpAndSettle();
}
