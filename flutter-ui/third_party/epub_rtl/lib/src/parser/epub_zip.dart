import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_exception.dart';

/// Lazy access to the entries of an EPUB zip.
///
/// Only the zip directory is read up front. Entry contents are inflated on
/// every request and not cached, so memory stays bounded by what the caller
/// keeps.
class EpubZip {
  EpubZip._(this._archive, this._closeable) {
    for (final file in _archive.files) {
      if (!file.isFile) continue;
      _byName[file.name] = file;
      _byLowerName.putIfAbsent(file.name.toLowerCase(), () => file);
    }
  }

  /// Opens a zip held in memory.
  factory EpubZip.fromBytes(List<int> bytes) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw EpubException(
          EpubErrorKind.notZip, 'Not a readable zip archive: $e');
    }
    if (archive.isEmpty) {
      throw const EpubException(
          EpubErrorKind.notZip, 'Not a readable zip archive (no entries)');
    }
    return EpubZip._(archive, null);
  }

  /// Opens a zip file from disk; entries are read from the file on demand.
  factory EpubZip.fromFile(String path) {
    InputFileStream? stream;
    try {
      stream = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(stream);
      if (archive.isEmpty) throw const FormatException('no entries');
      return EpubZip._(archive, stream);
    } on Object catch (e) {
      stream?.closeSync();
      throw EpubException(
          EpubErrorKind.notZip, 'Not a readable zip archive at $path: $e');
    }
  }

  final Archive _archive;
  final InputFileStream? _closeable;
  final Map<String, ArchiveFile> _byName = {};
  final Map<String, ArchiveFile> _byLowerName = {};

  /// Entry names in zip order.
  List<String> get names => [
        for (final f in _archive.files)
          if (f.isFile) f.name,
      ];

  /// The actual entry name for [path], or null. With [ignoreCase] a
  /// case-insensitive match is accepted when there is no exact one.
  String? find(String path, {bool ignoreCase = false}) {
    if (_byName.containsKey(path)) return path;
    if (ignoreCase) return _byLowerName[path.toLowerCase()]?.name;
    return null;
  }

  /// Inflates the entry [name], or returns null when it does not exist.
  Uint8List? read(String name) {
    final file = _byName[name];
    if (file == null) return null;
    final out = OutputMemoryStream();
    file.decompress(out);
    return out.getBytes();
  }

  /// Reads the entry [name] as UTF-8 text (malformed bytes are replaced).
  String? readString(String name) {
    final bytes = read(name);
    if (bytes == null) return null;
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('?')) text = text.substring(1);
    return text;
  }

  /// Releases the file handle when opened from disk.
  Future<void> close() async {
    await _closeable?.close();
  }
}
