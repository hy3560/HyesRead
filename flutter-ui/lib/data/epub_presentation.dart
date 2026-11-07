import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Normalizes *display-only* XHTML without changing the user's EPUB on disk.
/// Deliberately preserves every structural block and its order: the EPUB
/// renderer persists block indices, so deleting empty paragraphs would break
/// already saved reading positions, bookmarks and TOC anchors.
Uint8List normalizeEpubForReading(Uint8List source) {
  final original = ZipDecoder().decodeBytes(source);
  final output = Archive();
  var modified = false;
  for (final file in original) {
    if (!file.isFile ||
        !RegExp(r'\.(?:xhtml|html|htm)$', caseSensitive: false)
            .hasMatch(file.name)) {
      output.addFile(file);
      continue;
    }
    String xhtml;
    try {
      xhtml = utf8.decode(file.content);
    } on FormatException {
      output.addFile(file);
      continue;
    }
    final styled = normalizeEpubXhtml(xhtml);
    if (styled == xhtml) {
      output.addFile(file);
    } else {
      modified = true;
      output.addFile(ArchiveFile.string(file.name, styled));
    }
  }
  if (!modified) return source;
  return Uint8List.fromList(ZipEncoder().encode(output));
}

/// Keep block indices stable; only typography and markup hierarchy may change.
String normalizeEpubXhtml(String xhtml) {
  if (!RegExp(r'<head\b', caseSensitive: false).hasMatch(xhtml) ||
      !RegExp(r'</head\s*>', caseSensitive: false).hasMatch(xhtml)) {
    return xhtml;
  }
  // Limit heading inference to plain text nodes. Nested markup and existing
  // semantic headings keep their original structure.
  final textParagraph = RegExp(r'<p\b([^>]*)>([^<>]{2,80})</p\s*>',
      caseSensitive: false);
  final inferred = xhtml.replaceAllMapped(textParagraph, (m) {
    final value = m[2]!.trim();
    final attributes = m[1]!;
    // Retain id/class/lang attributes verbatim so old location anchors stay
    // usable even when a plain <p> becomes a semantic heading.
    // Infer headings only from short paragraphs with chapter-like labels.
    final heading = value.length <= 24 &&
        (RegExp(r'(?:层笔记|读书笔记|行动笔记|小结|后记|序言|前言)$')
            .hasMatch(value) ||
          RegExp(r'^第[一二三四五六七八九十百千0-9]+节').hasMatch(value));
    return heading ? '<h3$attributes>$value</h3>' : m[0]!;
  });

  // epub_rtl cascades publisher inline styles after document CSS. Normalize
  // only p-block margins/indent at the *end* of any inline declaration, so
  // a publisher's large 3em bottom margin cannot stack with our 0.55em.
  final paragraphs = inferred.replaceAllMapped(
      RegExp(r'<p\b[^>]*>', caseSensitive: false), (match) {
    final tag = match[0]!;
    if (tag.endsWith('/>')) return tag;
    const spacing = 'margin-top:0;margin-bottom:0.55em;text-indent:2em;';
    final style = RegExp(r'''style\s*=\s*(["'])(.*?)\1''',
        caseSensitive: false, dotAll: true).firstMatch(tag);
    if (style != null) {
      final quote = style[1]!;
      final existing = style[2]!.trim();
      final updated = '$quote$existing;${spacing}$quote';
      return tag.replaceRange(style.start + style[0]!.indexOf(quote),
          style.end, updated);
    }
    return '${tag.substring(0, tag.length - 1)} style="$spacing">';
  });

  // Change heading styles without adding blocks, so saved element indexes
  // still resolve to the same content.
  final chapters = paragraphs.replaceAllMapped(
      RegExp(r'<h[12]\b[^>]*>', caseSensitive: false), (match) {
    final tag = match[0]!;
    const layout = 'text-align:center;text-indent:0;margin-top:3.2em;'
        'margin-bottom:1.2em;';
    final inline = RegExp(r'''style\s*=\s*(["'])(.*?)\1''',
        caseSensitive: false, dotAll: true).firstMatch(tag);
    if (inline != null) {
      final quote = inline[1]!;
      return tag.replaceRange(inline.start, inline.end,
          'style=$quote${inline[2]};$layout$quote');
    }
    return '${tag.substring(0, tag.length - 1)} style="$layout">';
  });

  // The EPUB renderer supports only a CSS subset. This rule covers complex
  // selectors not overridden by an inline style, without removing nodes.
  const css = '<style type="text/css" id="hyesread-reading-style">'
      'body p{margin-top:0;margin-bottom:0.55em;text-indent:2em;}'
      'body h1,body h2,body h3,body h4,body h5,body h6'
      '{margin-top:1.8em;margin-bottom:0.7em;text-indent:0;}'
      '</style>';
  if (chapters.contains('id="hyesread-reading-style"')) return chapters;
  return chapters.replaceFirst(RegExp(r'</head\s*>', caseSensitive: false),
      '$css</head>');
}
