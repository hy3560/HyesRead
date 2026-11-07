import 'dart:math' as math;

/// Stable UTF-16 paragraph anchors, independent of screen size and font.
/// Splits long blocks while preserving surrogate pairs.
List<String> splitTextIntoStableBlocks(String raw) {
  final output = <String>[];
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
    if (block.trim().isEmpty) continue;
    var start = 0;
    while (start < block.length) {
      var end = math.min(block.length, start + 1400);
      if (end < block.length && end > start &&
          block.codeUnitAt(end - 1) >= 0xD800 &&
          block.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
      output.add(block.substring(start, end));
      start = end;
    }
  }
  return output;
}
