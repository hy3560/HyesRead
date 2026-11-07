import 'package:flutter/foundation.dart';

/// A reading position: a spine item, a top-level block inside it and how
/// far that block has scrolled past the top of the viewport.
///
/// [elementIndex] indexes `EpubChapter.blocks`. [fraction] is between 0
/// (block top at the viewport top) and 1 (block scrolled out).
@immutable
class EpubLocation {
  /// Creates a location.
  const EpubLocation({
    required this.spineIndex,
    this.elementIndex = 0,
    this.fraction = 0,
  })  : assert(spineIndex >= 0),
        assert(elementIndex >= 0);

  /// The start of the book.
  static const EpubLocation start = EpubLocation(spineIndex: 0);

  /// Index into `EpubBook.spine.items`.
  final int spineIndex;

  /// Index of the top-level block within the chapter.
  final int elementIndex;

  /// Offset within the block, as a fraction of its height.
  final double fraction;

  /// A JSON-compatible map.
  Map<String, Object> toJson() => {
        'spine': spineIndex,
        'element': elementIndex,
        'fraction': fraction,
      };

  /// Reads a map produced by [toJson].
  factory EpubLocation.fromJson(Map<String, dynamic> json) => EpubLocation(
        spineIndex: (json['spine'] as num).toInt(),
        elementIndex: (json['element'] as num? ?? 0).toInt(),
        fraction: (json['fraction'] as num? ?? 0).toDouble(),
      );

  /// A compact string form: `spine:element:fraction`.
  String encode() => '$spineIndex:$elementIndex:$fraction';

  /// Parses [encode] output; throws [FormatException] when malformed.
  static EpubLocation decode(String value) {
    final result = tryDecode(value);
    if (result == null) throw FormatException('Not an EpubLocation', value);
    return result;
  }

  /// Parses [encode] output, or returns null when malformed.
  static EpubLocation? tryDecode(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final spine = int.tryParse(parts[0]);
    final element = int.tryParse(parts[1]);
    final fraction = double.tryParse(parts[2]);
    if (spine == null ||
        element == null ||
        fraction == null ||
        spine < 0 ||
        element < 0) {
      return null;
    }
    return EpubLocation(
        spineIndex: spine, elementIndex: element, fraction: fraction);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubLocation &&
      other.spineIndex == spineIndex &&
      other.elementIndex == elementIndex &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(spineIndex, elementIndex, fraction);

  @override
  String toString() => 'EpubLocation($spineIndex, $elementIndex, $fraction)';
}
