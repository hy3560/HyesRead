/// Text direction of a block, as declared by `dir` or CSS `direction`.
enum EpubDirection {
  /// Left to right.
  ltr,

  /// Right to left.
  rtl,
}

/// CSS `text-align` values supported by the renderer.
enum EpubTextAlign {
  /// Aligned to the start edge (right in RTL).
  start,

  /// Aligned to the end edge (left in RTL).
  end,

  /// Physical left.
  left,

  /// Physical right.
  right,

  /// Centred.
  center,

  /// Justified.
  justify,
}

/// Units of a [CssLength].
enum CssUnit {
  /// Relative to the element font size.
  em,

  /// Relative to the root font size.
  rem,

  /// CSS pixels (logical pixels).
  px,

  /// Points (1pt = 4/3 px).
  pt,
}

/// A CSS length such as `1.5em`.
class CssLength {
  /// Creates a length.
  const CssLength(this.value, this.unit);

  /// Numeric value.
  final double value;

  /// Unit.
  final CssUnit unit;

  /// The length in logical pixels, given the element [fontSize] and the
  /// [rootFontSize] (defaults to [fontSize]).
  double toPixels(double fontSize, {double? rootFontSize}) => switch (unit) {
        CssUnit.em => value * fontSize,
        CssUnit.rem => value * (rootFontSize ?? fontSize),
        CssUnit.px => value,
        CssUnit.pt => value * 4 / 3,
      };

  @override
  bool operator ==(Object other) =>
      other is CssLength && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value${unit.name}';
}

/// Block-level style resolved from `dir`, `lang` and the CSS subset.
///
/// Null values mean "not specified"; the renderer applies its defaults.
class EpubBlockStyle {
  /// Creates a block style.
  const EpubBlockStyle({
    this.direction,
    this.lang,
    this.textAlign,
    this.textIndent,
    this.marginTop,
    this.marginRight,
    this.marginBottom,
    this.marginLeft,
  });

  /// Resolved direction, or null when nothing declared one.
  final EpubDirection? direction;

  /// Resolved language (`lang` / `xml:lang`, inherited).
  final String? lang;

  /// `text-align`.
  final EpubTextAlign? textAlign;

  /// `text-indent`.
  final CssLength? textIndent;

  /// `margin-top`.
  final CssLength? marginTop;

  /// `margin-right` (physical).
  final CssLength? marginRight;

  /// `margin-bottom`.
  final CssLength? marginBottom;

  /// `margin-left` (physical).
  final CssLength? marginLeft;
}

/// Inline formatting of a run of text.
class EpubInlineStyle {
  /// Creates an inline style.
  const EpubInlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.superscript = false,
    this.subscript = false,
    this.monospace = false,
    this.href,
    this.lang,
  });

  /// Bold (`b`, `strong`, `font-weight: bold`).
  final bool bold;

  /// Italic (`i`, `em`, `cite`, `font-style: italic`).
  final bool italic;

  /// Underlined (`u`, `ins`).
  final bool underline;

  /// Struck through (`s`, `del`, `strike`).
  final bool strikethrough;

  /// Superscript (`sup`).
  final bool superscript;

  /// Subscript (`sub`).
  final bool subscript;

  /// Monospace (`code`, `kbd`, `samp`, `tt`, `pre`).
  final bool monospace;

  /// Link target: a full book path with optional fragment, or an external
  /// URL. Null when the run is not a link.
  final String? href;

  /// Language of the run.
  final String? lang;

  /// Returns a copy with the given fields replaced.
  EpubInlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? superscript,
    bool? subscript,
    bool? monospace,
    String? href,
    String? lang,
  }) =>
      EpubInlineStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strikethrough: strikethrough ?? this.strikethrough,
        superscript: superscript ?? this.superscript,
        subscript: subscript ?? this.subscript,
        monospace: monospace ?? this.monospace,
        href: href ?? this.href,
        lang: lang ?? this.lang,
      );

  @override
  bool operator ==(Object other) =>
      other is EpubInlineStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.superscript == superscript &&
      other.subscript == subscript &&
      other.monospace == monospace &&
      other.href == href &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strikethrough,
      superscript, subscript, monospace, href, lang);
}

/// A piece of inline content.
sealed class EpubInline {
  const EpubInline();
}

/// A run of text sharing one [style]. Bidi controls from `dir`, `bdi` and
/// `bdo` are embedded in [text].
class EpubTextInline extends EpubInline {
  /// Creates a text run.
  const EpubTextInline(this.text, this.style);

  /// The text.
  final String text;

  /// The formatting.
  final EpubInlineStyle style;
}

/// An inline image.
class EpubImageInline extends EpubInline {
  /// Creates an inline image.
  const EpubImageInline(this.src,
      {this.alt, this.style = const EpubInlineStyle()});

  /// Full book path of the image.
  final String src;

  /// Alternative text.
  final String? alt;

  /// Formatting of the surrounding run (for linked images).
  final EpubInlineStyle style;
}

/// A `<ruby>` annotation: [base] text with [annotation] (`<rt>`) above it.
class EpubRubyInline extends EpubInline {
  /// Creates a ruby run.
  const EpubRubyInline(this.base, this.annotation, this.style);

  /// Base text.
  final String base;

  /// Annotation text.
  final String annotation;

  /// Formatting.
  final EpubInlineStyle style;
}

/// A block of chapter content.
sealed class EpubBlock {
  const EpubBlock(this.style);

  /// Resolved block style.
  final EpubBlockStyle style;
}

/// A paragraph, heading or preformatted block.
class EpubTextBlock extends EpubBlock {
  /// Creates a text block.
  const EpubTextBlock(
    this.inlines, {
    EpubBlockStyle style = const EpubBlockStyle(),
    this.headingLevel,
    this.preformatted = false,
  }) : super(style);

  /// Inline content.
  final List<EpubInline> inlines;

  /// 1-6 for `h1`-`h6`, null for other blocks.
  final int? headingLevel;

  /// Whether whitespace is preserved (`pre`).
  final bool preformatted;

  /// The text content without formatting (ruby annotations excluded).
  String get plainText => inlines
      .map((i) => switch (i) {
            EpubTextInline(:final text) => text,
            EpubRubyInline(:final base) => base,
            EpubImageInline() => '',
          })
      .join();
}

/// A block image.
class EpubImageBlock extends EpubBlock {
  /// Creates an image block.
  const EpubImageBlock(this.src,
      {this.alt, EpubBlockStyle style = const EpubBlockStyle()})
      : super(style);

  /// Full book path of the image.
  final String src;

  /// Alternative text.
  final String? alt;
}

/// An ordered or unordered list.
class EpubListBlock extends EpubBlock {
  /// Creates a list.
  const EpubListBlock(this.items,
      {this.ordered = false,
      this.start = 1,
      EpubBlockStyle style = const EpubBlockStyle()})
      : super(style);

  /// Each item is a list of blocks.
  final List<List<EpubBlock>> items;

  /// `ol` (true) or `ul` (false).
  final bool ordered;

  /// First number of an ordered list.
  final int start;
}

/// A `blockquote`.
class EpubQuoteBlock extends EpubBlock {
  /// Creates a quote.
  const EpubQuoteBlock(this.children,
      {EpubBlockStyle style = const EpubBlockStyle()})
      : super(style);

  /// Quoted blocks.
  final List<EpubBlock> children;
}

/// A table cell.
class EpubTableCell {
  /// Creates a cell.
  const EpubTableCell(this.children, {this.header = false});

  /// Cell content.
  final List<EpubBlock> children;

  /// Whether the cell is a `th`.
  final bool header;
}

/// A table row.
class EpubTableRow {
  /// Creates a row.
  const EpubTableRow(this.cells);

  /// Cells in document order.
  final List<EpubTableCell> cells;
}

/// A basic table (no spans).
class EpubTableBlock extends EpubBlock {
  /// Creates a table.
  const EpubTableBlock(this.rows,
      {EpubBlockStyle style = const EpubBlockStyle()})
      : super(style);

  /// Rows, header rows first as written.
  final List<EpubTableRow> rows;
}

/// A horizontal rule (`hr`).
class EpubRuleBlock extends EpubBlock {
  /// Creates a rule.
  const EpubRuleBlock({EpubBlockStyle style = const EpubBlockStyle()})
      : super(style);
}
