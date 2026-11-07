import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book_entry.dart';

class ImportOutcome {
  const ImportOutcome(this.name, {required this.imported, required this.reactivated});
  final String name;
  final bool imported, reactivated;
}

/// Stores imported book copies and their local metadata index.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository({Directory? root}) : _customRoot = root;
  final Directory? _customRoot;
  late final Directory _root;
  final List<BookEntry> _items = [];
  Future<void> _writes = Future<void>.value();
  bool _loaded = false;

  List<BookEntry> get books => List.unmodifiable(_items.where((b) => !b.archived));
  List<BookEntry> get archived => List.unmodifiable(_items.where((b) => b.archived));
  List<BookEntry> get favorites =>
      List.unmodifiable(_items.where((b) => !b.archived && b.favorite));
  List<BookEntry> get recentlyRead {
    final list = _items.where((b) => !b.archived && b.lastOpenedAt != null).toList();
    list.sort((a, b) => (b.lastOpenedAt ?? 0).compareTo(a.lastOpenedAt ?? 0));
    return List.unmodifiable(list);
  }

  BookEntry? byId(String id) {
    for (final entry in _items) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _root = _customRoot ??
        Directory(p.join((await getApplicationSupportDirectory()).path, 'hyesread-flutter'));
    await Directory(p.join(_root.path, 'books')).create(recursive: true);
    final index = File(p.join(_root.path, 'library.json'));
    final previous = File(p.join(_root.path, 'library.json.previous'));
    final File? source = await index.exists() ? index
        : (await previous.exists() ? previous : null);
    if (source != null) {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 || decoded['books'] is! List) {
        throw const FormatException('书库索引版本或内容异常，已拒绝覆盖');
      }
      final items = (decoded['books'] as List)
          .map((raw) => BookEntry.fromJson(Map<String, dynamic>.from(raw as Map)))
          .toList();
      final ownedBooks = p.normalize(p.join(_root.path, 'books'));
      for (final item in items) {
        final localPath = p.normalize(item.path);
        if (!p.isWithin(ownedBooks, localPath) ||
            p.basename(localPath) != item.id + '.' + item.format) {
          throw const FormatException('书籍路径不属于应用私有目录，已拒绝读取');
        }
      }
      if (items.map((e) => e.id).toSet().length != items.length) {
        throw const FormatException('书库索引存在重复 ID，已拒绝覆盖');
      }
      _items.addAll(items);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<ImportOutcome> importFile(File source, {String? displayName}) async {
    if (!_loaded) throw StateError('书库尚未加载');
    final name = displayName ?? p.basename(source.path);
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    if (!BookEntry.supported.contains(ext)) throw FormatException('不支持的格式：' + ext);
    if (!await source.exists()) throw FileSystemException('找不到文件', source.path);

    final hash = (await sha256.bind(source.openRead()).first).toString();
    final oldIndex = _items.indexWhere((book) => book.id == hash);
    if (oldIndex >= 0) {
      if (_items[oldIndex].archived) {
        final old = _items[oldIndex];
        _items[oldIndex] = old.copyWith(archived: false);
        try {
          await _save();
        } catch (_) {
          _items[oldIndex] = old;
          rethrow;
        }
        notifyListeners();
        return ImportOutcome(name, imported: false, reactivated: true);
      }
      return ImportOutcome(name, imported: false, reactivated: false);
    }

    final target = File(p.join(_root.path, 'books', hash + '.' + ext));
    if (!await target.exists()) {
      final partial = File(target.path + '.pending-' +
          DateTime.now().microsecondsSinceEpoch.toString());
      try {
        await source.copy(partial.path);
        final copiedHash = (await sha256.bind(partial.openRead()).first).toString();
        if (copiedHash != hash) {
          throw const FileSystemException('文件复制期间内容发生变化，已取消导入');
        }
        await partial.rename(target.path);
      } catch (_) {
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
    } else {
      // Verify the existing copy before using a content-addressed filename.
      final existingHash = (await sha256.bind(target.openRead()).first).toString();
      if (existingHash != hash) {
        throw FileSystemException('应用私有副本校验失败，拒绝覆盖', target.path);
      }
    }
    _items.add(BookEntry(
      id: hash, title: p.basenameWithoutExtension(name), fileName: name,
      format: ext, path: target.path,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    try {
      await _save();
    } catch (_) {
      _items.removeLast();
      rethrow;
    }
    notifyListeners();
    return ImportOutcome(name, imported: true, reactivated: false);
  }

  Future<void> replace(BookEntry entry) async {
    final index = _items.indexWhere((book) => book.id == entry.id);
    if (index < 0) throw StateError('书籍不存在');
    final original = _items[index];
    _items[index] = entry;
    try {
      await _save();
    } catch (_) {
      _items[index] = original;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> markOpened(String id) async {
    final book = byId(id);
    if (book != null && !book.archived) {
      await replace(book.copyWith(lastOpenedAt: DateTime.now().millisecondsSinceEpoch));
    }
  }

  Future<void> archive(String id) async {
    final book = byId(id);
    if (book != null) await replace(book.copyWith(archived: true));
  }

  Future<void> restore(String id) async {
    final book = byId(id);
    if (book != null) await replace(book.copyWith(archived: false));
  }

  Future<void> setFavorite(String id, bool favorite) async {
    final book = byId(id);
    if (book == null || book.archived) return;
    if (book.favorite == favorite) return;
    await replace(book.copyWith(favorite: favorite));
  }

  Future<void> _save() {
    final snapshot = jsonEncode({
      'version': 1,
      'books': _items.map((e) => e.toJson()).toList(),
    });
    final result = _writes.then((_) => _writeSnapshot(snapshot));
    _writes = result.catchError((Object _) {});
    return result;
  }

  Future<void> _writeSnapshot(String snapshot) async {
    final index = File(p.join(_root.path, 'library.json'));
    final previous = File(p.join(_root.path, 'library.json.previous'));
    final temporary = File(p.join(_root.path, 'library.json.writing'));
    await temporary.writeAsString(snapshot, flush: true);
    if (await index.exists()) {
      await index.copy(previous.path);
      await index.delete();
    }
    try {
      await temporary.rename(index.path);
    } catch (_) {
      if (!await index.exists() && await previous.exists()) {
        await previous.copy(index.path);
      }
      rethrow;
    }
  }
}
