import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

/// A stable paragraph + UTF-16 offset. Page numbers are deliberately not saved:
/// they depend on font, window size and the chosen reading paper.
@immutable
class TextPageCursor {
  const TextPageCursor(this.paragraph, this.offset);
  final int paragraph;
  final int offset;

  @override
  bool operator ==(Object other) => other is TextPageCursor &&
      paragraph == other.paragraph && offset == other.offset;

  @override
  int get hashCode => Object.hash(paragraph, offset);
}

@immutable
class TextPagePiece {
  const TextPagePiece({required this.paragraph, required this.text,
    required this.heading, required this.endsParagraph, this.chapter = false,
    this.indent = false});
  final int paragraph;
  final String text;
  final bool heading;
  final bool chapter;
  /// Visual 2-em first line only; never part of the saved text cursor.
  final bool indent;
  final bool endsParagraph;
}

@immutable
class TextPageResult {
  const TextPageResult(this.pieces, this.next);
  final List<TextPagePiece> pieces;
  final TextPageCursor? next;
}

/// Lays out only the requested screen, never the whole book. This makes the
/// page mode usable for large (up to the app's existing 20 MiB) local books.
class TextPageLayouter {
  TextPageLayouter({required this.paragraphs, required this.width,
    required this.height, required this.bodyStyle, required this.headingStyle,
    required this.textScaler, required this.direction,
    required this.paragraphSpacing, this.chapterStyle});

  final List<String> paragraphs;
  final double width, height, paragraphSpacing;
  final TextStyle bodyStyle, headingStyle;
  final TextStyle? chapterStyle;
  final TextScaler textScaler;
  final TextDirection direction;

  static final RegExp chapterHeading = RegExp(
    r'^(?:第[一二三四五六七八九十百千万零〇两0-9]{1,9}[章回卷节集](?:\s|$|[：:·—-])|序章|楔子|尾声|终章)',
  );

  /// True blank-separated short labels become subsections, never numbered
  /// paragraph anchors or continuation slices from a long paragraph.
  static bool isSubheading(List<String> blocks, int index) {
    if (index < 0 || index >= blocks.length) return false;
    // Short headings cannot exceed 46 UTF-16 units even with surrogate pairs.
    if (blocks[index].length > 46) return false;
    final line = blocks[index].trim();
    if (line.isEmpty || line.runes.length >= 24 ||
        chapterHeading.hasMatch(line) ||
        RegExp(r'[。！？!?；;：:，,、…\u201D\u2019）】]$').hasMatch(line) ||
        RegExp(r'[0-9０-９]$').hasMatch(line)) return false;
    return index == 0 || blocks[index - 1].length < 1400;
  }

  bool isHeading(int index) {
    if (paragraphs[index].length > 50) return false;
    final line = paragraphs[index].trim();
    return (line.length <= 36 && chapterHeading.hasMatch(line)) ||
        isSubheading(paragraphs, index);
  }

  double _measure(String content, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: direction,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final result = painter.height;
    painter.dispose();
    return result;
  }

  // Do not split a surrogate pair in the stored UTF-16 page anchor.
  int _safeCut(String value, int end) {
    if (end > 0 && end < value.length &&
        value.codeUnitAt(end) >= 0xDC00 && value.codeUnitAt(end) <= 0xDFFF) {
      return end - 1;
    }
    return end;
  }

  TextPageCursor normalize(TextPageCursor cursor) {
    if (paragraphs.isEmpty) return const TextPageCursor(0, 0);
    final index = cursor.paragraph.clamp(0, paragraphs.length - 1).toInt();
    return TextPageCursor(index,
      _safeCut(paragraphs[index], cursor.offset.clamp(0, paragraphs[index].length).toInt()));
  }

  TextPageResult layout(TextPageCursor position) {
    if (paragraphs.isEmpty) return const TextPageResult([], null);
    var cursor = normalize(position);
    var remaining = math.max(0.0, height - 8); // rounding/selection safety
    final result = <TextPagePiece>[];
    var visibleBlocks = 0;
    while (cursor.paragraph < paragraphs.length) {
      final original = paragraphs[cursor.paragraph];
      if (cursor.offset >= original.length) {
        cursor = TextPageCursor(cursor.paragraph + 1, 0);
        continue;
      }
      if (++visibleBlocks > 100) break;
      final heading = isHeading(cursor.paragraph);
      final chapter = heading && chapterHeading.hasMatch(original.trim());
      final indent = !heading && cursor.offset == 0;
      final prefix = indent ? '\u3000\u3000' : '';
      final decoration = heading && cursor.offset == 0
          ? (chapter ? 84.0 : headingStyle.fontSize! * 1.8 + 14) : 0.0;
      final style = chapter ? (chapterStyle ?? headingStyle)
          : heading ? headingStyle : bodyStyle;
      final available = remaining - decoration;
      if (available < textScaler.scale((style.fontSize ?? 19) * (style.height ?? 1.5)) * .9 &&
          result.isNotEmpty) {
        break;
      }

      // Readest's reflow principle applies here: measure only enough text
      // to fill a visible page, not a full multi-megabyte source paragraph.
      final remainingLength = original.length - cursor.offset;
      var sampleEnd = math.min(remainingLength, 4096);
      var sample = original.substring(cursor.offset,
          cursor.offset + sampleEnd);
      var sampleHeight = _measure('$prefix$sample', style);
      while (sampleEnd < remainingLength && sampleHeight <= available) {
        sampleEnd = math.min(remainingLength, sampleEnd * 2);
        sample = original.substring(cursor.offset,
            cursor.offset + sampleEnd);
        sampleHeight = _measure('$prefix$sample', style);
      }
      if (sampleEnd == remainingLength &&
          decoration + sampleHeight + paragraphSpacing <= remaining) {
        result.add(TextPagePiece(paragraph: cursor.paragraph,
          text: sample, heading: heading && cursor.offset == 0,
          chapter: chapter && cursor.offset == 0,
          indent: indent,
          endsParagraph: true));
        remaining -= decoration + sampleHeight + paragraphSpacing;
        cursor = TextPageCursor(cursor.paragraph + 1, 0);
        continue;
      }

      // Split only at complete grapheme boundaries.
      final boundaries = <int>[0];
      var boundary = 0;
      for (final cluster in sample.characters) {
        boundary += cluster.length;
        boundaries.add(boundary);
      }
      var low = 0, high = boundaries.length - 1;
      while (low < high) {
        final middle = (low + high + 1) ~/ 2;
        final cut = boundaries[middle];
        if (cut > 0 &&
            _measure('$prefix${sample.substring(0, cut)}', style) <= available) {
          low = middle;
        } else {
          high = middle - 1;
        }
      }
      var taken = boundaries[low];
      if (taken == 0) {
        if (result.isNotEmpty) break;
        // A single oversized cluster still advances as one intact unit.
        taken = boundaries[1];
      }
      final completed = taken == remainingLength;
      result.add(TextPagePiece(paragraph: cursor.paragraph,
        text: sample.substring(0, taken),
        heading: heading && cursor.offset == 0,
        chapter: chapter && cursor.offset == 0,
        indent: indent,
        endsParagraph: completed));
      cursor = completed
          ? TextPageCursor(cursor.paragraph + 1, 0)
          : TextPageCursor(cursor.paragraph, cursor.offset + taken);
      break;
    }
    return TextPageResult(result,
      cursor.paragraph >= paragraphs.length ? null : cursor);
  }

  /// Used only when reopening in the middle of a book without turn history.
  /// After that the viewer keeps an exact history of screen anchors.
  TextPageCursor? approximatePrevious(TextPageCursor position) {
    final cursor = normalize(position);
    if (cursor.paragraph == 0 && cursor.offset == 0) return null;
    final index = cursor.offset > 0 ? cursor.paragraph : cursor.paragraph - 1;
    final end = cursor.offset > 0 ? cursor.offset : paragraphs[index].length;
    if (end < 1) return TextPageCursor(index, 0);
    final source = paragraphs[index];
    final style = chapterHeading.hasMatch(source.trim())
        ? (chapterStyle ?? headingStyle)
        : isHeading(index) ? headingStyle : bodyStyle;
    var low = 0, high = end;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final cut = _safeCut(source, middle);
      if (_measure(source.substring(cut, end), style) <= height * .83) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return TextPageCursor(index, _safeCut(source, low));
  }
}
