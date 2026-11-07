import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/ui/app_language.dart';
import 'package:hyesread_flutter/ui/app_shell.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/widgets/import_arrival.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty app has real import actions but no trial or demo route',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-clean-empty-');
    final repo = LibraryRepository(root: root);
    addTearDown(() {
      repo.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(repo.load);
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
        onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('try-turn-pages')), findsNothing);
    expect(find.text('先试翻一页'), findsNothing);
    expect(find.byKey(const ValueKey('atelier-drop-zone')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('atelier-nav-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debug-demo-shelf')), findsNothing);
    expect(find.text('演示书架'), findsNothing);
    expect(find.text('语言'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English app offers English navigation, settings and import',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('hyes-clean-en-');
    final repo = LibraryRepository(root: root);
    addTearDown(() {
      repo.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(repo.load);
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
        language: HyesLanguage.english, onModeChanged: (_) {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('My library'), findsWidgets);
    expect(find.text('Import books'), findsWidgets);
    expect(find.text('Try turning a page'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('atelier-nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Demo library'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English import success overlay uses English copy',
      (tester) async {
    final book = BookEntry(
      id: 'example', title: 'A book', fileName: 'book.txt',
      format: 'txt', path: 'book.txt', importedAt: 0,
    );
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: HyesLanguageScope(language: HyesLanguage.english,
        child: Scaffold(body: ImportArrival(book: book, onFinished: () {}))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Added to library'), findsOneWidget);
    expect(find.text('上架了。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone offers English settings without debug samples',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final root = Directory.systemTemp.createTempSync('hyes-clean-phone-en-');
    final repo = LibraryRepository(root: root);
    addTearDown(() {
      repo.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(repo.load);
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.light),
      home: AppShell(repository: repo, mode: ThemeMode.light,
        language: HyesLanguage.english, onModeChanged: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('try-turn-pages')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('paper-dock-3')));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byKey(const ValueKey('debug-demo-shelf')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('essential English reading and import controls are translated', () {
    const copy = HyesCopy(HyesLanguage.english);
    for (final label in <String>[
      '我的书签', '还没有书签', '跳转到此处', '返回原处',
      '字体', '只调整这本书', '字号', '行距', '纸张主题',
      '翻页方式', '部分书籍导入失败', '已隐藏，可在设置中恢复',
    ]) {
      expect(copy.tr(label), isNot(label), reason: label);
    }
  });
}
