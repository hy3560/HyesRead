import 'package:xml/xml.dart';

import '../parser/epub_book.dart';
import '../parser/epub_path.dart';
import '../parser/xml_utils.dart';
import 'content_model.dart';
import 'css.dart';

// Unicode bidi controls.
const _lri = '\u2066';
const _rli = '\u2067';
const _fsi = '\u2068';
const _pdi = '\u2069';
const _lro = '\u202D';
const _rlo = '\u202E';
const _pdf = '\u202C';

const _skipped = {
  'head', 'script', 'style', 'template', 'rp', 'rt', 'title', 'iframe', //
  'object', 'embed', 'audio', 'video', 'canvas', 'math', 'noscript',
};

const _containers = {
  'body', 'div', 'section', 'article', 'aside', 'header', 'footer', 'main', //
  'nav', 'figure', 'figcaption', 'dl', 'dd', 'dt', 'address', 'hgroup',
  'details', 'summary', 'center', 'li', 'td', 'th', 'caption', 'fieldset',
};

const _textBlocks = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', //
};

const _structural = {
  'ul', 'ol', 'blockquote', 'table', 'hr', //
};

bool _isBlock(String tag) =>
    _containers.contains(tag) ||
    _textBlocks.contains(tag) ||
    _structural.contains(tag);

/// A parsed chapter: a flat list of top-level blocks plus a map from
/// element ids to block indexes.
///
/// Block indexes are what `EpubLocation.elementIndex` refers to. Containers
/// such as `div` and `section` are flattened, so each paragraph, heading,
/// image, list, quote or table is one top-level block.
class EpubChapter {
  EpubChapter._({
    required this.path,
    required this.blocks,
    required this.anchors,
    required this.direction,
    required this.lang,
    required this.title,
  });

  /// Parses the XHTML [html] of the document at [path] (a full book path).
  ///
  /// Linked stylesheets are fetched through [loadStylesheet], which
  /// receives a full book path and returns the CSS text or null.
  factory EpubChapter.parse(
    String html, {
    required String path,
    String? Function(String href)? loadStylesheet,
  }) =>
      _ChapterBuilder(path, loadStylesheet).build(parseXml(html, path));

  /// Parses the spine item at [spineIndex] of [book], with its stylesheets.
  factory EpubChapter.fromBook(EpubBook book, int spineIndex) =>
      EpubChapter.parse(
        book.chapterHtml(spineIndex),
        path: book.spine.items[spineIndex].item.href,
        loadStylesheet: book.readString,
      );

  /// Full book path of the document.
  final String path;

  /// Top-level blocks.
  final List<EpubBlock> blocks;

  /// Element id to top-level block index.
  final Map<String, int> anchors;

  /// Direction declared on `html` or `body`, if any.
  final EpubDirection? direction;

  /// Language declared on `html` or `body`, if any.
  final String? lang;

  /// Document `<title>`, if any.
  final String? title;
}

class _Ctx {
  const _Ctx({
    this.direction,
    this.lang,
    this.textAlign,
    this.textIndent,
    this.inline = const EpubInlineStyle(),
    this.pre = false,
  });

  final EpubDirection? direction;
  final String? lang;
  final EpubTextAlign? textAlign;
  final CssLength? textIndent;
  final EpubInlineStyle inline;
  final bool pre;

  _Ctx copyWith({
    EpubDirection? direction,
    String? lang,
    EpubTextAlign? textAlign,
    CssLength? textIndent,
    EpubInlineStyle? inline,
    bool? pre,
  }) =>
      _Ctx(
        direction: direction ?? this.direction,
        lang: lang ?? this.lang,
        textAlign: textAlign ?? this.textAlign,
        textIndent: textIndent ?? this.textIndent,
        inline: inline ?? this.inline,
        pre: pre ?? this.pre,
      );
}

/// Collects inline content for one block, collapsing whitespace.
class _InlineBuffer {
  final List<EpubInline> items = [];
  bool _lastWasSpace = true;

  bool get isBlank =>
      items.every((i) => i is EpubTextInline && i.text.trim().isEmpty);

  void text(String raw, EpubInlineStyle style, {required bool pre}) {
    var t = raw;
    if (!pre) {
      t = t.replaceAll(RegExp('[ \t\n\r\f]+'), ' ');
      if (_lastWasSpace && t.startsWith(' ')) t = t.substring(1);
    }
    if (t.isEmpty) return;
    _lastWasSpace = !pre && t.endsWith(' ');
    _append(t, style);
  }

  /// Zero-width bidi controls do not affect whitespace collapsing.
  void control(String c, EpubInlineStyle style) => _append(c, style);

  void lineBreak(EpubInlineStyle style) {
    _trimTrailingSpace();
    _append('\n', style);
    _lastWasSpace = true;
  }

  void _append(String t, EpubInlineStyle style) {
    final last = items.isEmpty ? null : items.last;
    if (last is EpubTextInline && last.style == style) {
      items[items.length - 1] = EpubTextInline(last.text + t, style);
    } else {
      items.add(EpubTextInline(t, style));
    }
  }

  void add(EpubInline inline) {
    items.add(inline);
    _lastWasSpace = false;
  }

  static final _trailingSpace =
      RegExp('[ ]+(?=[\u2066-\u2069\u202A-\u202E]*\$)');

  void _trimTrailingSpace() {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item is! EpubTextInline) return;
      final trimmed = item.text.replaceFirst(_trailingSpace, '');
      if (trimmed.isEmpty) {
        items.removeAt(i);
        continue;
      }
      if (trimmed != item.text) items[i] = EpubTextInline(trimmed, item.style);
      if (!trimmed.split('').every(_isBidiControl)) return;
    }
  }

  List<EpubInline> finish() {
    _trimTrailingSpace();
    return List.of(items);
  }
}

bool _isBidiControl(String c) =>
    c == _lri ||
    c == _rli ||
    c == _fsi ||
    c == _pdi ||
    c == _lro ||
    c == _rlo ||
    c == _pdf;

class _ChapterBuilder {
  _ChapterBuilder(this.path, this.loadStylesheet);

  final String path;
  final String? Function(String href)? loadStylesheet;
  final EpubStylesheet css = EpubStylesheet();
  final List<EpubBlock> top = [];
  final Map<String, int> anchors = {};

  EpubChapter build(XmlDocument doc) {
    final html = doc.rootElement;
    final head = html.firstChildNamed('head');
    for (final e in head?.childElements ?? const <XmlElement>[]) {
      if (e.local == 'link' &&
          (e.attr('rel') ?? '').toLowerCase().contains('stylesheet') &&
          e.attr('href') != null &&
          loadStylesheet != null) {
        final text = loadStylesheet!(EpubPath.resolve(path, e.attr('href')!));
        if (text != null) css.add(text);
      } else if (e.local == 'style') {
        css.add(e.innerText);
      }
    }
    // Also honour <style> elements placed in the body.
    for (final s in html.descendantsNamed('style')) {
      if (s.parent != head) css.add(s.innerText);
    }

    var ctx = _apply(html, const _Ctx());
    final body = html.firstChildNamed('body');
    if (body != null) ctx = _apply(body, ctx);
    if (body != null) _container(body, ctx, top, registerSelf: true);

    return EpubChapter._(
      path: path,
      blocks: top,
      anchors: anchors,
      direction: ctx.direction,
      lang: ctx.lang,
      title: head?.firstChildNamed('title')?.cleanText,
    );
  }

  /// Resolves inherited properties for [e].
  _Ctx _apply(XmlElement e, _Ctx parent, [Map<String, String>? decl]) {
    final d = decl ?? css.declarationsFor(e);
    final lang = e.attr('lang');
    EpubDirection? direction;
    final dirAttr = e.attr('dir')?.toLowerCase();
    if (dirAttr == 'rtl') direction = EpubDirection.rtl;
    if (dirAttr == 'ltr') direction = EpubDirection.ltr;
    if (d['direction'] == 'rtl') direction = EpubDirection.rtl;
    if (d['direction'] == 'ltr') direction = EpubDirection.ltr;
    final align = switch (d['text-align']) {
      'left' => EpubTextAlign.left,
      'right' => EpubTextAlign.right,
      'center' => EpubTextAlign.center,
      'justify' => EpubTextAlign.justify,
      'start' => EpubTextAlign.start,
      'end' => EpubTextAlign.end,
      _ => null,
    };
    var inline = parent.inline;
    final weight = d['font-weight'];
    if (weight != null) {
      final n = int.tryParse(weight);
      inline = inline.copyWith(
          bold: weight == 'bold' ||
              weight == 'bolder' ||
              (n != null && n >= 600));
    }
    final fontStyle = d['font-style'];
    if (fontStyle != null) {
      inline = inline.copyWith(
          italic: fontStyle == 'italic' || fontStyle == 'oblique');
    }
    if (lang != null && lang.isNotEmpty) inline = inline.copyWith(lang: lang);
    return parent.copyWith(
      direction: direction,
      lang: lang == null || lang.isEmpty ? null : lang,
      textAlign: align,
      textIndent: parseCssLength(d['text-indent']),
      inline: inline,
    );
  }

  EpubBlockStyle _blockStyle(_Ctx ctx, Map<String, String> d) => EpubBlockStyle(
        direction: ctx.direction,
        lang: ctx.lang,
        textAlign: ctx.textAlign,
        textIndent: ctx.textIndent,
        marginTop: parseCssLength(d['margin-top']),
        marginRight: parseCssLength(d['margin-right']),
        marginBottom: parseCssLength(d['margin-bottom']),
        marginLeft: parseCssLength(d['margin-left']),
      );

  void _registerId(XmlElement e) {
    final id = e.attr('id') ?? (e.local == 'a' ? e.attr('name') : null);
    if (id != null && id.isNotEmpty) anchors.putIfAbsent(id, () => top.length);
  }

  /// Walks the children of a container, emitting blocks into [out].
  void _container(XmlElement e, _Ctx ctx, List<EpubBlock> out,
      {bool registerSelf = false, EpubBlockStyle? anonymousStyle}) {
    if (registerSelf) _registerId(e);
    final style = anonymousStyle ?? _blockStyle(ctx, const {});
    var buffer = _InlineBuffer();

    void flush() {
      if (!buffer.isBlank) _emitText(buffer.finish(), style, out, ctx);
      buffer = _InlineBuffer();
    }

    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        buffer.text(node.value ?? '', ctx.inline, pre: ctx.pre);
        continue;
      }
      if (node is! XmlElement) continue;
      final tag = node.local.toLowerCase();
      if (_skipped.contains(tag)) continue;
      final d = css.declarationsFor(node);
      if (d['display'] == 'none') continue;
      if (_isBlock(tag)) {
        flush();
        _block(node, tag, d, ctx, out);
      } else if (tag == 'svg') {
        final src = _svgImage(node);
        if (src != null) {
          flush();
          _registerId(node);
          out.add(EpubImageBlock(src, style: _blockStyle(ctx, d)));
        }
      } else {
        _inline(node, tag, d, ctx, buffer);
      }
    }
    flush();
  }

  void _emitText(List<EpubInline> inlines, EpubBlockStyle style,
      List<EpubBlock> out, _Ctx ctx,
      {int? heading, bool pre = false}) {
    final nonBlank = inlines
        .where((i) => !(i is EpubTextInline && i.text.trim().isEmpty))
        .toList();
    if (heading == null &&
        !pre &&
        nonBlank.length == 1 &&
        nonBlank.single is EpubImageInline) {
      final img = nonBlank.single as EpubImageInline;
      out.add(EpubImageBlock(img.src, alt: img.alt, style: style));
      return;
    }
    out.add(EpubTextBlock(inlines,
        style: style, headingLevel: heading, preformatted: pre));
  }

  void _block(XmlElement e, String tag, Map<String, String> d, _Ctx parent,
      List<EpubBlock> out) {
    _registerId(e);
    var ctx = _apply(e, parent, d);
    final dirAuto = e.attr('dir')?.toLowerCase() == 'auto';
    if (dirAuto) {
      final detected = detectDirection(e.innerText);
      if (detected != null) ctx = ctx.copyWith(direction: detected);
    }
    final style = _blockStyle(ctx, d);
    if (_textBlocks.contains(tag)) {
      final heading = tag.length == 2 && tag.startsWith('h')
          ? int.parse(tag.substring(1))
          : null;
      final pre = tag == 'pre';
      if (heading != null) {
        ctx = ctx.copyWith(
            inline: ctx.inline
                .copyWith(bold: d['font-weight'] == null ? true : null));
      }
      if (pre) {
        ctx = ctx.copyWith(
            pre: true, inline: ctx.inline.copyWith(monospace: true));
      }
      final buffer = _InlineBuffer();
      _inlineChildren(e, ctx, buffer);
      if (buffer.isBlank) return;
      var inlines = buffer.finish();
      if (pre) inlines = _trimPreNewline(inlines);
      _emitText(inlines, style, out, ctx, heading: heading, pre: pre);
      return;
    }
    switch (tag) {
      case 'hr':
        out.add(EpubRuleBlock(style: style));
      case 'blockquote':
        final children = <EpubBlock>[];
        _container(e, ctx, children);
        if (children.isNotEmpty) {
          out.add(EpubQuoteBlock(children, style: style));
        }
      case 'ul' || 'ol':
        final items = <List<EpubBlock>>[];
        for (final li in e.childElements) {
          if (li.local.toLowerCase() == 'li') {
            _registerId(li);
            final item = <EpubBlock>[];
            final liDecl = css.declarationsFor(li);
            if (liDecl['display'] == 'none') continue;
            final liCtx = _apply(li, ctx, liDecl);
            _container(li, liCtx, item);
            items.add(item);
          } else if (li.local == 'ul' || li.local == 'ol') {
            // Invalid but common: a nested list directly inside a list.
            final nested = <EpubBlock>[];
            _block(li, li.local, css.declarationsFor(li), ctx, nested);
            if (items.isEmpty) items.add([]);
            items.last.addAll(nested);
          }
        }
        if (items.isNotEmpty) {
          out.add(EpubListBlock(
            items,
            ordered: tag == 'ol',
            start: int.tryParse(e.attr('start') ?? '') ?? 1,
            style: style,
          ));
        }
      case 'table':
        final rows = <EpubTableRow>[];
        for (final tr in e.descendantsNamed('tr')) {
          _registerId(tr);
          final cells = <EpubTableCell>[];
          for (final cell in tr.childElements) {
            final name = cell.local.toLowerCase();
            if (name != 'td' && name != 'th') continue;
            final cellDecl = css.declarationsFor(cell);
            var cellCtx = _apply(cell, ctx, cellDecl);
            if (name == 'th') {
              cellCtx =
                  cellCtx.copyWith(inline: cellCtx.inline.copyWith(bold: true));
            }
            final children = <EpubBlock>[];
            _container(cell, cellCtx, children, registerSelf: true);
            cells.add(EpubTableCell(children, header: name == 'th'));
          }
          if (cells.isNotEmpty) rows.add(EpubTableRow(cells));
        }
        if (rows.isNotEmpty) out.add(EpubTableBlock(rows, style: style));
      default:
        // Containers: flattened into [out]. Loose text gets the container's
        // resolved style.
        _container(e, ctx, out, anonymousStyle: style);
    }
  }

  List<EpubInline> _trimPreNewline(List<EpubInline> inlines) {
    if (inlines.isNotEmpty) {
      final first = inlines.first;
      if (first is EpubTextInline && first.text.startsWith('\n')) {
        return [
          EpubTextInline(first.text.substring(1), first.style),
          ...inlines.skip(1)
        ];
      }
    }
    return inlines;
  }

  void _inlineChildren(XmlElement e, _Ctx ctx, _InlineBuffer buffer) {
    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        buffer.text(node.value ?? '', ctx.inline, pre: ctx.pre);
      } else if (node is XmlElement) {
        final tag = node.local.toLowerCase();
        if (_skipped.contains(tag)) continue;
        final d = css.declarationsFor(node);
        if (d['display'] == 'none') continue;
        if (_isBlock(tag)) {
          // A block nested inside inline content: keep its text on a new line.
          _registerId(node);
          if (!buffer.isBlank) buffer.lineBreak(ctx.inline);
          _inlineChildren(node, _apply(node, ctx, d), buffer);
        } else if (tag == 'svg') {
          final src = _svgImage(node);
          if (src != null) buffer.add(EpubImageInline(src, style: ctx.inline));
        } else {
          _inline(node, tag, d, ctx, buffer);
        }
      }
    }
  }

  void _inline(XmlElement e, String tag, Map<String, String> d, _Ctx parent,
      _InlineBuffer buffer) {
    _registerId(e);
    switch (tag) {
      case 'br':
        buffer.lineBreak(parent.inline);
        return;
      case 'img':
        final src = e.attr('src');
        if (src != null) {
          buffer.add(EpubImageInline(EpubPath.resolve(path, src),
              alt: e.attr('alt'), style: parent.inline));
        }
        return;
      case 'ruby':
        final base = StringBuffer();
        final annotation = StringBuffer();
        for (final n in e.children) {
          if (n is XmlText) base.write(n.value);
          if (n is XmlElement && n.local == 'rt') annotation.write(n.innerText);
          if (n is XmlElement && n.local == 'rb') base.write(n.innerText);
        }
        final baseText =
            base.toString().replaceAll(RegExp('[ \t\n\r\f]+'), ' ').trim();
        if (baseText.isNotEmpty) {
          buffer.add(EpubRubyInline(baseText, annotation.toString().trim(),
              _apply(e, parent, d).inline));
        }
        return;
    }
    var ctx = _apply(e, parent, d);
    var inline = ctx.inline;
    switch (tag) {
      case 'b' || 'strong':
        if (d['font-weight'] == null) inline = inline.copyWith(bold: true);
      case 'i' || 'em' || 'cite' || 'var' || 'dfn':
        if (d['font-style'] == null) inline = inline.copyWith(italic: true);
      case 'u' || 'ins':
        inline = inline.copyWith(underline: true);
      case 's' || 'strike' || 'del':
        inline = inline.copyWith(strikethrough: true);
      case 'sup':
        inline = inline.copyWith(superscript: true);
      case 'sub':
        inline = inline.copyWith(subscript: true);
      case 'code' || 'kbd' || 'samp' || 'tt':
        inline = inline.copyWith(monospace: true);
      case 'a':
        final href = e.attr('href');
        if (href != null && href.trim().isNotEmpty) {
          inline = inline.copyWith(
              href: EpubPath.isExternal(href)
                  ? href.trim()
                  : EpubPath.resolve(path, href));
        }
    }
    ctx = ctx.copyWith(inline: inline);

    // Bidi: explicit dir on inline content is isolated from its
    // surroundings; bdo overrides; bdi isolates with auto direction.
    final dirAttr = e.attr('dir')?.toLowerCase();
    final cssDir = d['direction'];
    final dir = cssDir == 'rtl' || cssDir == 'ltr' ? cssDir : dirAttr;
    String? open;
    String? close;
    if (tag == 'bdo' && (dir == 'rtl' || dir == 'ltr')) {
      open = dir == 'rtl' ? _rlo : _lro;
      close = _pdf;
    } else if (dir == 'rtl') {
      open = _rli;
      close = _pdi;
    } else if (dir == 'ltr') {
      open = _lri;
      close = _pdi;
    } else if (dir == 'auto' || tag == 'bdi') {
      open = _fsi;
      close = _pdi;
    }
    if (open != null) buffer.control(open, inline);
    _inlineChildren(e, ctx, buffer);
    if (close != null) buffer.control(close, inline);
  }

  String? _svgImage(XmlElement svg) {
    for (final img in svg.descendantsNamed('image')) {
      final href = img.attr('href');
      if (href != null) return EpubPath.resolve(path, href);
    }
    return null;
  }
}

/// The direction of the first strong character of [text], or null when it
/// has none. Arabic, Hebrew, Syriac, Thaana, NKo and the RTL presentation
/// forms count as right to left; Latin, Greek, Cyrillic and other
/// alphabetic scripts count as left to right.
EpubDirection? detectDirection(String text) {
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) return EpubDirection.rtl;
    if (_isLtrRune(rune)) return EpubDirection.ltr;
  }
  return null;
}

bool _isRtlRune(int r) =>
    (r >= 0x0590 && r <= 0x08FF) ||
    (r >= 0xFB1D && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF) ||
    (r >= 0x10800 && r <= 0x10FFF) ||
    (r >= 0x1E800 && r <= 0x1EFFF);

bool _isLtrRune(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) ||
    (r >= 0x370 && r <= 0x58F) ||
    (r >= 0x0900 && r <= 0x1FFF) ||
    (r >= 0x3040 && r <= 0x9FFF) ||
    (r >= 0xAC00 && r <= 0xD7AF);
