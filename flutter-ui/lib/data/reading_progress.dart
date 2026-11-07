import 'dart:isolate';
import 'package:epub_rtl/epub_rtl.dart';

/// A layout-independent index over stable UTF-16 text-block positions.
class TextReadingProgress {
  TextReadingProgress(List<String> blocks)
      : _lengths = blocks.map((block) => block.length).toList(growable: false) {
    _prefix = List<int>.filled(_lengths.length + 1, 0);
    for (var i = 0; i < _lengths.length; i++) {
      _prefix[i + 1] = _prefix[i] + _lengths[i];
    }
  }

  final List<int> _lengths;
  late final List<int> _prefix;

  double at(int paragraphIndex, int offset) {
    if (_lengths.isEmpty) return 0;
    final total = _prefix.last;
    if (total == 0) return 0;
    final index = paragraphIndex.clamp(0, _lengths.length - 1).toInt();
    final within = offset.clamp(0, _lengths[index]).toInt();
    return ((_prefix[index] + within) / total).clamp(0.0, 1.0).toDouble();
  }
}

/// EPUB locations count blocks in reading order. A block-weighted percentage
/// is consistent across devices and font sizes, unlike a pixel or page count.
double epubProgressFromBlocks(EpubLocation location, List<int> chapterBlocks) {
  if (chapterBlocks.isEmpty) return 0;
  final weights = chapterBlocks.map((count) => count > 0 ? count : 1).toList();
  final total = weights.fold<int>(0, (sum, count) => sum + count);
  final index = location.spineIndex.clamp(0, weights.length - 1);
  var passed = 0;
  for (var i = 0; i < index; i++) {
    passed += weights[i];
  }
  final within = (location.elementIndex + location.fraction)
      .clamp(0.0, weights[index].toDouble());
  return ((passed + within) / total).clamp(0.0, 1.0).toDouble();
}

/// Inspect EPUB structure off the UI isolate. Reading metadata has no side
/// effects on the original book or its saved position.
Future<List<int>> epubBlockCountsFromFile(String path) => Isolate.run(() async {
  final source = EpubBook.openFile(path, lenient: true);
  try {
    return List<int>.generate(source.spine.items.length, (i) {
      try {
        final count = EpubChapter.fromBook(source, i).blocks.length;
        return count > 0 ? count : 1;
      } catch (_) {
        return 1;
      }
    });
  } finally {
    await source.close();
  }
});

Future<double?> epubProgressFromFile(
    String path, String? encodedLocation) async {
  final location = EpubLocation.tryDecode(encodedLocation ?? '');
  if (location == null) return null;
  final weights = await epubBlockCountsFromFile(path);
  return weights.isEmpty ? null : epubProgressFromBlocks(location, weights);
}
