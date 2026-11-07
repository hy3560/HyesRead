import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../content/chapter_parser.dart';
import '../content/content_model.dart';
import '../parser/epub_book.dart';
import '../render/image_size.dart';
import 'epub_location.dart';
import 'reader_settings.dart';

/// A physical paper leaf; the next cursor is always after its last fragment.
/// Source locations stay in the existing spine/block/fraction format.
class EpubPaperLeaf {
  const EpubPaperLeaf(this.start, this.fragments, this.next);
  final EpubLocation start;
  final List<EpubPaperFragment> fragments;
  final EpubLocation? next;
}

class EpubPaperFragment {
  const EpubPaperFragment(this.block, this.sourceBlock,
      {this.textStart = 0, this.textEnd = 0, this.imageHeight});
  final EpubBlock block;
  final int sourceBlock;
  final int textStart, textEnd;
  final double? imageHeight;
}

/// Measures actual Flutter text before placing it into a finite-height leaf.
/// Images retain their source blocks; large images are scaled, not cropped.
/// Text with embedded images/ruby and complex tables remains atomic and can
/// scroll *inside that leaf* rather than silently losing content.
class EpubPaperLayouter {
  const EpubPaperLayouter({
    required this.book,
    required this.settings,
    required this.width,
    required this.height,
    required this.textScaler,
    required this.direction,
    required this.chapterAt,
    required this.imageBytes,
  });

  final EpubBook book;
  final EpubReaderSettings settings;
  final double width, height;
  final TextScaler textScaler;
  final TextDirection direction;
  final EpubChapter? Function(int) chapterAt;
  final Uint8List? Function(String) imageBytes;

  static const _headingScale = [1.30, 1.20, 1.12, 1.12, 1.05, 1.0];

  double get innerWidth => math.max(120, width - settings.padding.horizontal);
  double get innerHeight => math.max(100, height - settings.padding.vertical);

  double _px(CssLength? value, double fallback, double fontSize) =>
      value?.toPixels(fontSize, rootFontSize: settings.fontSize)
          .clamp(0, 400).toDouble() ?? fallback;

  double _top(EpubBlock block, {required bool continuation}) {
    if (continuation) return 0;
    final h = block is EpubTextBlock ? block.headingLevel : null;
    if (h == 1) return 64;
    if (h != null) return settings.fontSize * 1.8;
    return _px(block.style.marginTop, 0, settings.fontSize);
  }

  double _bottom(EpubBlock block, {required bool continues}) {
    if (continues) return 0;
    if (block is EpubTextBlock && block.headingLevel != null) {
      return settings.fontSize * .7 +
          (block.headingLevel == 1 ? 17 : 0);
    }
    return _px(block.style.marginBottom,
        settings.fontSize * settings.paragraphSpacing, settings.fontSize);
  }

  String _plain(EpubTextBlock block) => block.plainText;
  bool _splittable(EpubTextBlock block) =>
      !block.preformatted &&
      block.headingLevel == null &&
      block.inlines.every((e) => e is EpubTextInline);

  EpubTextBlock _part(EpubTextBlock block, int start, int end) {
    var offset = 0;
    final inlines = <EpubInline>[];
    for (final inline in block.inlines) {
      if (inline is! EpubTextInline) continue;
      final runEnd = offset + inline.text.length;
      final left = math.max(0, start - offset);
      final right = math.min(inline.text.length, end - offset);
      if (right > left) {
        inlines.add(EpubTextInline(inline.text.substring(left, right),
            inline.style));
      }
      offset = runEnd;
      if (offset >= end) break;
    }
    final style = block.style;
    return EpubTextBlock(inlines,
      headingLevel: block.headingLevel,
      preformatted: block.preformatted,
      style: EpubBlockStyle(
        direction: style.direction,
        lang: style.lang,
        textAlign: style.textAlign,
        textIndent: start == 0 ? style.textIndent : null,
        marginTop: start == 0 ? style.marginTop
            : const CssLength(0, CssUnit.px),
        marginBottom: end >= _plain(block).length ? style.marginBottom
            : const CssLength(0, CssUnit.px),
        marginLeft: style.marginLeft,
        marginRight: style.marginRight,
      ),
    );
  }

  double _textHeight(EpubTextBlock block, int start, int end) {
    final fontSize = settings.fontSize *
        (block.headingLevel == null
            ? 1 : _headingScale[block.headingLevel! - 1]);
    final size = textScaler.scale(fontSize);
    final style = TextStyle(
      fontSize: fontSize,
      height: block.headingLevel == null ? settings.lineHeight : 1.3,
      fontWeight: block.headingLevel == null
          ? FontWeight.normal : FontWeight.w600,
      fontFamily: settings.fontFamily,
      fontFamilyFallback: settings.fontFamilyFallback,
      letterSpacing: settings.letterSpacing,
      fontFeatures: settings.fontFeatures,
    );
    final text = _part(block, start, end);
    final parts = <InlineSpan>[
      if (start == 0 && block.style.textIndent != null)
        TextSpan(text: '　' *
            math.max(0, (block.style.textIndent!
                .toPixels(fontSize, rootFontSize: settings.fontSize) /
                math.max(1, size)).round())),
      for (final inline in text.inlines)
        if (inline is EpubTextInline)
          TextSpan(text: inline.text,
            style: TextStyle(
              fontWeight: inline.style.bold ? FontWeight.bold : null,
              fontStyle: inline.style.italic ? FontStyle.italic : null,
            )),
    ];
    final painter = TextPainter(
      text: TextSpan(style: style, children: parts),
      textDirection: block.style.direction == EpubDirection.rtl
          ? TextDirection.rtl : direction,
      textScaler: textScaler,
      textAlign: settings.justify ? TextAlign.justify : TextAlign.start,
    )..layout(maxWidth: math.max(80, innerWidth -
        _px(block.style.marginLeft, 0, fontSize) -
        _px(block.style.marginRight, 0, fontSize) -
        (block.headingLevel == null ? 0 : 16)));
    final result = painter.height;
    painter.dispose();
    return result;
  }

  double _imageHeight(EpubImageBlock image) {
    final bytes = imageBytes(image.src);
    final dimensions = bytes == null ? null : readImageSize(bytes);
    if (dimensions == null || dimensions.width <= 0) {
      return math.min(innerHeight * .65, innerWidth * .72);
    }
    final w = math.min(innerWidth, dimensions.width.toDouble());
    return w * dimensions.height / dimensions.width;
  }

  int _fitText(EpubTextBlock block, int start, double available) {
    final text = block.plainText;
    if (start >= text.length) return start;
    // Binary-search rune boundaries, never cut a UTF-16 surrogate pair.
    final ends = <int>[];
    var offset = 0;
    for (final rune in text.substring(start).runes) {
      offset += rune > 0xFFFF ? 2 : 1;
      ends.add(start + offset);
    }
    var lo = 0, hi = ends.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      final end = ends[mid - 1];
      // Leave enough room for font fallback and the renderer's line boxes.
      final height = _textHeight(block, start, end);
      if (height <= available - settings.fontSize * .35) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo == 0 ? start : ends[lo - 1];
  }

  EpubPaperLeaf layout(EpubLocation start) {
    final pieces = <EpubPaperFragment>[];
    var spine = start.spineIndex.clamp(0,
        math.max(0, book.spine.items.length - 1)).toInt();
    var index = start.elementIndex;
    var fraction = start.fraction.clamp(0.0, 1.0).toDouble();
    var used = 0.0;
    var guard = 0;
    while (spine < book.spine.items.length && guard++ < 2000) {
      final chapter = chapterAt(spine);
      if (chapter == null || index >= chapter.blocks.length) {
        spine++;
        index = 0;
        fraction = 0;
        if (pieces.isNotEmpty) break; // New chapter begins on fresh paper.
        continue;
      }
      final block = chapter.blocks[index];
      final continued = fraction > 0 && block is EpubTextBlock;
      final remaining = innerHeight - used;
      if (remaining < settings.fontSize * settings.lineHeight &&
          pieces.isNotEmpty) break;
      final top = _top(block, continuation: continued);
      final bottom = _bottom(block, continues: false);
      double contentHeight;
      var textStart = 0, textEnd = 0;
      if (block is EpubTextBlock) {
        final content = _plain(block);
        textStart = (fraction * content.length).round()
            .clamp(0, content.length).toInt();
        if (textStart >= content.length) {
          index++;
          fraction = 0;
          continue;
        }
        if (_splittable(block)) {
          textEnd = _fitText(block, textStart,
              math.max(1, remaining - top - bottom));
          if (textEnd <= textStart && pieces.isNotEmpty) break;
          if (textEnd <= textStart) {
            textEnd = _fitText(block, textStart,
                math.max(1, innerHeight - top - bottom));
          }
          if (textEnd <= textStart) {
            // Keep a complete first grapheme even on extremely short pages.
            textEnd = math.min(content.length, textStart + 1).toInt();
            if (textEnd < content.length &&
                content.codeUnitAt(textEnd - 1) >= 0xD800 &&
                content.codeUnitAt(textEnd - 1) <= 0xDBFF) textEnd++;
          }
          contentHeight = _textHeight(block, textStart, textEnd);
        } else {
          if (pieces.isNotEmpty && remaining < settings.fontSize * 6) break;
          textEnd = content.length;
          contentHeight = block.preformatted ? settings.fontSize * 3
              : math.min(innerHeight - top - bottom,
                  _textHeight(block, 0, content.length));
        }
      } else if (block is EpubImageBlock) {
        contentHeight = _imageHeight(block);
      } else {
        // Complex tables/lists/quotes keep the original renderer and can
        // scroll within their leaf when taller than the available viewport.
        contentHeight = innerHeight * .7;
      }
      final needed = top + contentHeight + bottom;
      if (needed > remaining && pieces.isNotEmpty) break;
      final imageHeight = block is EpubImageBlock
          ? math.min(contentHeight,
              math.max(80, remaining - top - bottom)).toDouble() : null;
      final visibleBlock = block is EpubTextBlock &&
              _splittable(block) && textEnd < block.plainText.length
          ? _part(block, textStart, textEnd) : block;
      pieces.add(EpubPaperFragment(visibleBlock, index,
        textStart: textStart, textEnd: textEnd, imageHeight: imageHeight));
      used += math.min(needed, remaining);
      if (block is EpubTextBlock && _splittable(block) &&
          textEnd < block.plainText.length) {
        fraction = textEnd / block.plainText.length;
        break;
      }
      index++;
      fraction = 0;
      if (needed >= remaining) break;
    }
    final next = spine >= book.spine.items.length ? null
        : EpubLocation(spineIndex: spine, elementIndex: index,
            fraction: double.parse(fraction.toStringAsFixed(8)));
    return EpubPaperLeaf(start, pieces, next);
  }
}
