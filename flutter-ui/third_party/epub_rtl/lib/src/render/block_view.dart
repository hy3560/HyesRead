import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../content/content_model.dart';
import '../parser/epub_book.dart' show isRtlLanguage;
import '../reader/reader_settings.dart';
import 'image_size.dart';

/// What block widgets need from the reader.
@immutable
class EpubRenderScope {
  /// Creates a scope.
  const EpubRenderScope({
    required this.settings,
    required this.defaultDirection,
    required this.onLink,
    required this.loadImage,
    this.maxImageHeight,
  });

  /// Typography and colours.
  final EpubReaderSettings settings;

  /// Direction for blocks that declare none (from the spine
  /// `page-progression-direction` or the book language).
  final TextDirection defaultDirection;

  /// Called with the `href` of a tapped link.
  final void Function(String href) onLink;

  /// Loads image bytes by full book path.
  final Uint8List? Function(String src) loadImage;

  /// A physical leaf may cap oversized figures to avoid a broken spread.
  /// Null retains the original scrolling chapter image behaviour.
  final double? maxImageHeight;

  /// The base text style.
  TextStyle get baseStyle => TextStyle(
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: settings.theme.textColor,
        fontFamily: settings.fontFamily,
        letterSpacing: settings.letterSpacing,
        fontFeatures: settings.fontFeatures,
        fontFamilyFallback: [
          if (settings.arabicFontFamily != null) settings.arabicFontFamily!,
          ...settings.fontFamilyFallback,
        ],
      );

  /// Resolves the direction of [style].
  TextDirection directionOf(EpubBlockStyle style) => switch (style.direction) {
        EpubDirection.rtl => TextDirection.rtl,
        EpubDirection.ltr => TextDirection.ltr,
        null => defaultDirection,
      };
}

// HyesRead preview chapter/subheading scale at a 20sp body.
const _headingScale = [1.30, 1.20, 1.12, 1.12, 1.05, 1.0];

/// Renders one [EpubBlock].
class EpubBlockView extends StatelessWidget {
  /// Creates a block view.
  const EpubBlockView({super.key, required this.block, required this.scope});

  /// The block.
  final EpubBlock block;

  /// Rendering scope.
  final EpubRenderScope scope;

  @override
  Widget build(BuildContext context) {
    final s = scope.settings;
    final style = block.style;
    final direction = scope.directionOf(style);
    final fontSize = block is EpubTextBlock &&
            (block as EpubTextBlock).headingLevel != null
        ? s.fontSize * _headingScale[(block as EpubTextBlock).headingLevel! - 1]
        : s.fontSize;
    double px(CssLength? l, double fallback) => l == null
        ? fallback
        : l
            .toPixels(fontSize, rootFontSize: s.fontSize)
            .clamp(0, 400)
            .toDouble();
    final isHeading =
        block is EpubTextBlock && (block as EpubTextBlock).headingLevel != null;
    final defaultBottom = s.fontSize * s.paragraphSpacing;
    final headingLevel = block is EpubTextBlock
        ? (block as EpubTextBlock).headingLevel : null;
    final padding = EdgeInsets.fromLTRB(
      px(style.marginLeft, 0),
      isHeading ? (headingLevel == 1 ? 64.0 : s.fontSize * 1.8)
          : px(style.marginTop, 0),
      px(style.marginRight, 0),
      isHeading ? s.fontSize * 0.7 : px(style.marginBottom, defaultBottom),
    );
    Widget content = Directionality(
        textDirection: direction, child: _content(direction));
    if (headingLevel == 1) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: content),
        const SizedBox(height: 15),
        Container(width: 24, height: 2, color: s.headingAccent),
      ]);
    } else if (isHeading) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 3, height: s.fontSize, color: s.headingAccent),
        const SizedBox(width: 12),
        Expanded(child: content),
      ]);
    }
    return Padding(
      padding: padding,
      child: content,
    );
  }

  Widget _content(TextDirection direction) {
    final s = scope.settings;
    switch (block) {
      case final EpubTextBlock b:
        return EpubRichBlock(block: b, scope: scope);
      case final EpubImageBlock b:
        return Center(child: EpubImage(src: b.src, alt: b.alt, scope: scope));
      case EpubRuleBlock():
        return Container(height: 1, color: s.theme.secondaryColor);
      case final EpubQuoteBlock b:
        return Container(
          decoration: BoxDecoration(
            border: BorderDirectional(
                start: BorderSide(color: s.theme.secondaryColor, width: 3)),
          ),
          padding: EdgeInsetsDirectional.only(start: s.fontSize),
          child: _column(b.children),
        );
      case final EpubListBlock b:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < b.items.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: s.fontSize * 2,
                    child: Text(
                      b.ordered ? '${b.start + i}.' : '?',
                      style: scope.baseStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(child: _column(b.items[i])),
                ],
              ),
          ],
        );
      case final EpubTableBlock b:
        final columns = b.rows
            .fold<int>(0, (m, r) => r.cells.length > m ? r.cells.length : m);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 0),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: s.theme.secondaryColor),
              textDirection: direction,
              children: [
                for (final row in b.rows)
                  TableRow(children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: EdgeInsets.all(s.fontSize * 0.3),
                        child: c < row.cells.length
                            ? _column(row.cells[c].children, tight: true)
                            : const SizedBox(),
                      ),
                  ]),
              ],
            ),
          ),
        );
    }
  }

  Widget _column(List<EpubBlock> blocks, {bool tight = false}) => Column(
        crossAxisAlignment:
            tight ? CrossAxisAlignment.start : CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in blocks) EpubBlockView(block: b, scope: scope)
        ],
      );
}

/// Renders a paragraph, heading or `pre` block as rich text.
class EpubRichBlock extends StatefulWidget {
  /// Creates a rich text block.
  const EpubRichBlock({super.key, required this.block, required this.scope});

  /// The block.
  final EpubTextBlock block;

  /// Rendering scope.
  final EpubRenderScope scope;

  @override
  State<EpubRichBlock> createState() => _EpubRichBlockState();
}

class _EpubRichBlockState extends State<EpubRichBlock> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _recognizer(String href) {
    final r = TapGestureRecognizer()..onTap = () => widget.scope.onLink(href);
    _recognizers.add(r);
    return r;
  }

  TextStyle _runStyle(EpubInlineStyle s, TextStyle base) {
    final settings = widget.scope.settings;
    final decorations = <TextDecoration>[
      if (s.underline || s.href != null) TextDecoration.underline,
      if (s.strikethrough) TextDecoration.lineThrough,
    ];
    return TextStyle(
      fontWeight: s.bold ? FontWeight.bold : null,
      fontStyle: s.italic ? FontStyle.italic : null,
      decoration:
          decorations.isEmpty ? null : TextDecoration.combine(decorations),
      color: s.href != null ? settings.theme.linkColor : null,
      fontFamily: s.monospace
          ? 'monospace'
          : (isRtlLanguage(s.lang) && settings.arabicFontFamily != null
              ? settings.arabicFontFamily
              : settings.fontFamily),
      fontSize: s.superscript || s.subscript ? base.fontSize! * 0.7 : null,
      locale: _locale(s.lang),
    );
  }

  static Locale? _locale(String? lang) {
    if (lang == null || lang.isEmpty) return null;
    final parts = lang.split(RegExp('[-_]'));
    final language = parts.first.toLowerCase();
    if (!RegExp(r'^[a-z]{2,3}$').hasMatch(language)) return null;
    final region =
        parts.length > 1 && RegExp(r'^[A-Za-z]{2}$').hasMatch(parts[1])
            ? parts[1].toUpperCase()
            : null;
    return Locale(language, region);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final scope = widget.scope;
    final settings = scope.settings;
    final block = widget.block;
    final level = block.headingLevel;
    var base = scope.baseStyle;
    if (level != null) {
      base = base.copyWith(
          fontSize: settings.fontSize * _headingScale[level - 1],
          fontWeight: FontWeight.w600, height: 1.3);
    }
    final children = <InlineSpan>[];
    final indent = block.style.textIndent
            ?.toPixels(base.fontSize!, rootFontSize: settings.fontSize) ??
        0;
    if (indent > 0 && level == null) {
      children.add(WidgetSpan(child: SizedBox(width: indent)));
    }
    for (final inline in block.inlines) {
      switch (inline) {
        case EpubTextInline(:final text, :final style):
          children.add(TextSpan(
            text: text,
            style: _runStyle(style, base),
            recognizer: style.href == null ? null : _recognizer(style.href!),
          ));
        case EpubImageInline(:final src, :final alt, :final style):
          Widget image = EpubImage(src: src, alt: alt, scope: scope);
          if (style.href != null) {
            final href = style.href!;
            image =
                GestureDetector(onTap: () => scope.onLink(href), child: image);
          }
          children.add(
              WidgetSpan(child: image, alignment: PlaceholderAlignment.middle));
        case EpubRubyInline(:final base, :final annotation, :final style):
          final runStyle =
              scope.baseStyle.merge(_runStyle(style, scope.baseStyle));
          children.add(WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(annotation,
                    style: runStyle.copyWith(
                        fontSize: settings.fontSize * 0.5, height: 1)),
                Text(base, style: runStyle),
              ],
            ),
          ));
      }
    }
    final align = switch (block.style.textAlign) {
      EpubTextAlign.start => TextAlign.start,
      EpubTextAlign.end => TextAlign.end,
      EpubTextAlign.left => TextAlign.left,
      EpubTextAlign.right => TextAlign.right,
      EpubTextAlign.center => TextAlign.center,
      EpubTextAlign.justify => TextAlign.justify,
      null => settings.justify && level == null && !block.preformatted
          ? TextAlign.justify
          : TextAlign.start,
    };
    final text = Text.rich(
      TextSpan(children: children),
      style: base,
      textAlign: align,
      textDirection: scope.directionOf(block.style),
      softWrap: !block.preformatted,
    );
    if (block.preformatted) {
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: text);
    }
    return text;
  }
}

/// An image loaded from the book, laid out at its intrinsic size (capped to
/// the available width) before it is decoded.
class EpubImage extends StatelessWidget {
  /// Creates an image.
  const EpubImage(
      {super.key, required this.src, required this.scope, this.alt});

  /// Full book path.
  final String src;

  /// Alternative text.
  final String? alt;

  /// Rendering scope.
  final EpubRenderScope scope;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = scope.loadImage(src);
    } on Exception {
      bytes = null;
    }
    if (bytes == null) {
      return Text(alt ?? '',
          style: scope.baseStyle.copyWith(fontStyle: FontStyle.italic));
    }
    final image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      semanticLabel: alt,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          Text(alt ?? '', style: scope.baseStyle),
    );
    final size = readImageSize(bytes);
    if (size == null) return image;
    return LayoutBuilder(builder: (context, constraints) {
      final aspect = size.width / size.height;
      final width = size.width.toDouble().clamp(1.0,
          constraints.maxWidth.isFinite ? constraints.maxWidth
              : size.width.toDouble());
      final maxImageHeight = scope.maxImageHeight;
      final shownWidth = maxImageHeight == null ? width
          : width.clamp(1.0, maxImageHeight * aspect);
      return SizedBox(
        width: shownWidth,
        height: shownWidth / aspect,
        child: image,
      );
    });
  }
}
