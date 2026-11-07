import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/data/book_entry.dart';
import 'package:hyesread_flutter/data/library_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late LibraryRepository repo;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyesread-flutter-test-');
    repo = LibraryRepository(root: root);
    await repo.load();
  });
  tearDown(() async {
    repo.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('import is offline, content-deduplicated and does not change source', () async {
    final source = File(root.path + '/sample.txt');
    await source.writeAsString('第一段\n\n第二段');
    final first = await repo.importFile(source, displayName: '我的书.txt');
    expect(first.imported, isTrue);
    expect(repo.books, hasLength(1));
    expect(repo.books.first.title, '我的书');
    expect(repo.books.first.format, 'txt');
    final copy = File(repo.books.first.path);
    expect(await copy.exists(), isTrue);
    expect(copy.path, isNot(source.path));
    expect(await copy.readAsString(), await source.readAsString());

    final second = await repo.importFile(source, displayName: '复制书.txt');
    expect(second.imported, isFalse);
    expect(second.reactivated, isFalse);
    expect(repo.books, hasLength(1));
  });

  test('reading, bookmarks and archive survive repository reload', () async {
    final source = File(root.path + '/sample.epub');
    await source.writeAsBytes([1, 2, 3, 4, 5]);
    await repo.importFile(source);
    final book = repo.books.single;
    await repo.replace(book.copyWith(
      progress: .45, epubCfi: 'epubcfi(/6/4!/4/2)',
      epubLocation: 'preview-location-v1',
      epubBookmarks: ['epubcfi(/6/4!/4/2)'],
    ));
    await repo.archive(book.id);
    expect(repo.books, isEmpty);
    expect(await source.exists(), isTrue);
    expect(await File(book.path).exists(), isTrue);

    final fresh = LibraryRepository(root: root);
    await fresh.load();
    expect(fresh.archived, hasLength(1));
    expect(fresh.archived.single.epubCfi, 'epubcfi(/6/4!/4/2)');
    expect(fresh.archived.single.epubLocation, 'preview-location-v1');
    expect(fresh.archived.single.progress, .45);
    expect(fresh.archived.single.epubBookmarks, hasLength(1));
    await fresh.restore(book.id);
    expect(fresh.books, hasLength(1));
    fresh.dispose();
  });

  test('first-page opening counts as started without inventing progress', () async {
    final source = File(root.path + '/first-page.txt');
    await source.writeAsString('开头\n\n第二段');
    await repo.importFile(source);
    final before = repo.books.single;
    expect(before.hasReading, isFalse);
    expect(before.progress, 0);
    await repo.markOpened(before.id);
    final after = repo.books.single;
    expect(after.hasReading, isTrue);
    expect(after.progress, 0);
    expect(after.paragraphIndex, 0);
    expect(repo.recentlyRead.single.id, before.id);
    final fresh = LibraryRepository(root: root);
    await fresh.load();
    expect(fresh.books.single.hasReading, isTrue);
    expect(fresh.books.single.progress, 0);
    fresh.dispose();
  });

  test('favorites persist locally, stay reversible and read old indexes', () async {
    final source = File(root.path + '/favorite.txt');
    await source.writeAsString('想再读一次的书');
    await repo.importFile(source);
    final book = repo.books.single;
    expect(book.favorite, isFalse); // Older indexes have no favorite field.
    await repo.setFavorite(book.id, true);
    expect(repo.favorites.single.id, book.id);
    await repo.archive(book.id);
    expect(repo.favorites, isEmpty); // Hidden books do not leak onto home.
    final fresh = LibraryRepository(root: root);
    await fresh.load();
    expect(fresh.archived.single.favorite, isTrue);
    await fresh.restore(book.id);
    expect(fresh.favorites.single.id, book.id);
    await fresh.setFavorite(book.id, false);
    expect(fresh.favorites, isEmpty);
    final latest = LibraryRepository(root: root);
    await latest.load();
    expect(latest.books.single.favorite, isFalse);
    latest.dispose();
    fresh.dispose();
  });

  test('corrupt index fails closed and is not overwritten', () async {
    final source = File(root.path + '/safe.md');
    await source.writeAsString('私有阅读记录');
    await repo.importFile(source);
    final index = File(root.path + '/library.json');
    await index.writeAsString('{"version":500,"books":[]}');
    final snapshot = await index.readAsString();

    final attempted = LibraryRepository(root: root);
    await expectLater(attempted.load(), throwsFormatException);
    expect(await index.readAsString(), snapshot);
    attempted.dispose();
  });

  test('tampered index cannot point a book outside the app-owned directory', () async {
    final index = File(root.path + '/library.json');
    await index.writeAsString(jsonEncode({
      'version': 1,
      'books': [
        {
          'id': List<String>.filled(64, 'a').join(),
          'title': '错误路径',
          'fileName': 'outside.txt',
          'format': 'txt',
          'path': root.path + '/outside.txt',
          'importedAt': 1,
        },
      ],
    }));
    final fresh = LibraryRepository(root: root);
    await expectLater(fresh.load(), throwsFormatException);
    expect(await index.exists(), isTrue);
    fresh.dispose();
  });

  test('book entry rejects unsupported formats and malformed identifiers', () {
    expect(
      () => BookEntry.fromJson({'id': 'wrong', 'path': '/p', 'format': 'txt'}),
      throwsFormatException,
    );
    expect(
      () => BookEntry.fromJson({
        'id': List<String>.filled(64, 'a').join(),
        'path': '/p',
        'format': 'exe',
      }),
      throwsFormatException,
    );
  });
}
