import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/library_repository.dart';
import 'package:hyesread_flutter/ui/app_shell.dart';
import 'package:hyesread_flutter/ui/app_language.dart';
import 'package:hyesread_flutter/ui/app_theme.dart';
import 'package:hyesread_flutter/ui/atelier_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android import uses the shared shelf with touch wording',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark).copyWith(
        platform: TargetPlatform.android),
      home: Scaffold(body: AtelierDropZone(
        highlighted: false,
        enabled: true,
        language: HyesLanguage.chinese,
        onTap: () {},
      )),
    ));
    expect(find.text('添加书籍'), findsOneWidget);
    expect(find.text('将书籍拖到这里，直接上架'), findsNothing);
    expect(find.text('EPUB · TXT · MD · PDF'), findsOneWidget);
  });

  testWidgets('Windows keeps the drag and drop entry point',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark).copyWith(
        platform: TargetPlatform.windows),
      home: Scaffold(body: AtelierDropZone(
        highlighted: false,
        enabled: true,
        language: HyesLanguage.chinese,
        onTap: () {},
      )),
    ));
    expect(find.text('将书籍拖到这里，直接上架'), findsOneWidget);
    expect(find.text('添加书籍'), findsNothing);
  });

  testWidgets('Android empty shelf keeps actions without redundant tutorials',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final root = Directory.systemTemp.createTempSync('hyes-android-parity-');
    final repo = LibraryRepository(root: root);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      repo.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    await tester.runAsync(() => repo.load());
    await tester.pumpWidget(MaterialApp(
      theme: hyesReadTheme(Brightness.dark).copyWith(
        platform: TargetPlatform.android),
      home: AppShell(
        repository: repo,
        mode: ThemeMode.dark,
        onModeChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有书籍'), findsOneWidget);
    expect(find.text('添加文件'), findsOneWidget);
    expect(find.byKey(const ValueKey('atelier-drop-zone')), findsOneWidget);
    expect(find.text('书架还空着。先去放一本书，下一次就从上回读到的地方继续。'),
      findsNothing);
    expect(find.text('导入 EPUB、TXT 或 PDF 文件即可开始阅读。'), findsNothing);
    expect(find.text('只是试读，不会加入你的书架'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
