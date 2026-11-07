import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:epub_rtl/epub_rtl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/book_entry.dart';
import '../design/tokens.dart';

@immutable
class CoverPalette {
  const CoverPalette(this.background, this.ink);
  final Color background;
  final Color ink;
}

const coverPalettes = <CoverPalette>[
  CoverPalette(Color(0xFFB8412F), Color(0xFFF1E7D3)),
  CoverPalette(Color(0xFF2F4858), Color(0xFFE9E1CF)),
  CoverPalette(Color(0xFF3B5B4B), Color(0xFFEFE6D2)),
  CoverPalette(Color(0xFF8C5A3C), Color(0xFFF3E9D6)),
  CoverPalette(Color(0xFF6B5876), Color(0xFFEFE6DA)),
  CoverPalette(Color(0xFFDDE3E0), Color(0xFF23302D)),
  CoverPalette(Color(0xFF1E1D1B), Color(0xFFC9A86A)),
  CoverPalette(Color(0xFFD9A441), Color(0xFF2A1F12)),
];

/// Stable UTF-8 FNV-1a. Never use process-dependent String.hashCode.
int stableTitleHash(String title) {
  var value = 0x811c9dc5;
  for (final byte in utf8.encode(title)) {
    value = ((value ^ byte) * 0x01000193) & 0xffffffff;
  }
  return value;
}

CoverPalette coverPaletteFor(String title) =>
    coverPalettes[stableTitleHash(title) % coverPalettes.length];

Uint8List? _loadEpubCover(String path) {
  EpubBook? epub;
  try {
    epub = EpubBook.openFile(path, lenient: true);
    final item = epub.coverItem;
    if (item == null || !item.mediaType.startsWith('image/')) return null;
    final bytes = epub.readBytes(item.href);
    return bytes == null ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  } finally {
    epub?.close();
  }
}

class EpubCoverCache {
  static final _pending = LinkedHashMap<String, Future<Uint8List?>>();
  static Future<Uint8List?> read(BookEntry book) {
    final previous = _pending.remove(book.id);
    if (previous != null) {
      _pending[book.id] = previous;
      return previous;
    }
    final task = compute(_loadEpubCover, book.path);
    _pending[book.id] = task;
    if (_pending.length > 40) _pending.remove(_pending.keys.first);
    return task;
  }
}

class _RasterEntry {
  _RasterEntry(this.future);
  final Future<ui.Image> future;
  int refs = 0;
}

/// Forty cached DPR-capped pictures. No in-use image can be disposed.
class _RasterCache {
  static final _entries = LinkedHashMap<String, _RasterEntry>();
  static _RasterEntry acquire(String key, Future<ui.Image> Function() make) {
    final entry = _entries.remove(key) ?? _RasterEntry(make());
    entry.refs++;
    _entries[key] = entry;
    _trim();
    return entry;
  }
  static void release(_RasterEntry entry) {
    entry.refs = math.max(0, entry.refs - 1);
    _trim();
  }
  static void _trim() {
    while (_entries.length > 40) {
      final key = _entries.keys.firstWhere(
        (key) => _entries[key]!.refs == 0, orElse: () => '');
      if (key.isEmpty) break;
      final discarded = _entries.remove(key)!;
      unawaited(discarded.future.then((picture) => picture.dispose())
          .catchError((Object _) {}));
    }
  }
}

/// Decorative art. Parent tiles own accessible book-title semantics.
class BookCover extends StatefulWidget {
  const BookCover({super.key, required this.book, required this.width,
    required this.height, this.elevation = true, this.showSeal = true});
  final BookEntry book;
  final double width;
  final double height;
  final bool elevation;
  /// Import animation supplies its own full-size '阅' seal; do not draw a
  /// second miniature title seal underneath it.
  final bool showSeal;
  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  _RasterEntry? _entry;
  String? _key;
  Future<Uint8List?>? _epubFuture;
  String? _epubId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepare();
  }

  @override
  void didUpdateWidget(BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  void _prepare() {
    final ratio = math.min(MediaQuery.devicePixelRatioOf(context), 2.0);
    final key = '${widget.book.title}|${widget.book.format}|'
        '${widget.width.toStringAsFixed(1)}|${widget.height.toStringAsFixed(1)}|'
        '$ratio|${widget.showSeal}';
    if (_key != key) {
      if (_entry != null) _RasterCache.release(_entry!);
      _key = key;
      final title = widget.book.title;
      final format = widget.book.format;
      final width = widget.width;
      final height = widget.height;
      _entry = _RasterCache.acquire(key, () async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        _CoverPainter(title, format, showSeal: widget.showSeal)
            .paint(canvas, Size(width, height));
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(
            math.max(1, (width * ratio).ceil()),
            math.max(1, (height * ratio).ceil()),
          );
        } finally {
          picture.dispose();
        }
      });
    }
    if (_epubId != widget.book.id) {
      _epubId = widget.book.id;
      _epubFuture = widget.book.isEpub ? EpubCoverCache.read(widget.book) : null;
    }
  }

  @override
  void dispose() {
    if (_entry != null) _RasterCache.release(_entry!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = coverPaletteFor(widget.book.title).background;
    const radius = BorderRadius.all(Radius.circular(HyesTokens.coverRadius));
    return ExcludeSemantics(child: RepaintBoundary(child: Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(borderRadius: radius,
        boxShadow: widget.elevation ? [
          BoxShadow(color: Colors.black.withValues(alpha: .35),
            blurRadius: 4, offset: const Offset(0, 2)),
          BoxShadow(color: (Theme.of(context).brightness == Brightness.dark
              ? Colors.black : ink).withValues(alpha: .18),
            blurRadius: 24, offset: const Offset(0, 10)),
        ] : null,
      ),
      child: ClipRRect(borderRadius: radius, child: Stack(children: [
        Positioned.fill(child: FutureBuilder<ui.Image>(
          future: _entry!.future,
          builder: (context, snapshot) => snapshot.hasData
              ? RawImage(image: snapshot.data, fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium)
              : CustomPaint(painter: _CoverPainter(
                  widget.book.title, widget.book.format,
                  showSeal: widget.showSeal)),
        )),
        if (_epubFuture != null) Positioned.fill(
          child: FutureBuilder<Uint8List?>(future: _epubFuture,
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox.shrink()
                : Stack(children: [
                    Positioned.fill(child: Image.memory(snapshot.data!,
                      // Real EPUB cover art must never crop the book title or
                      // spine details to impersonate the fallback geometry.
                      fit: BoxFit.contain,
                      cacheWidth: math.max(64, (widget.width * 2).round()),
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink())),
                    Positioned(left: 0, top: 0, bottom: 0,
                      child: Container(width: 3, decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.white.withValues(alpha: .18),
                          Colors.transparent,
                        ])))),
                  ])),
        ),
      ])),
    )));
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter(this.title, this.format, {this.showSeal = true});
  final String title;
  final String format;
  final bool showSeal;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final palette = coverPaletteFor(title);
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    // A cloth-bound spine with a narrow debossed hinge. Keep the real EPUB
    // cover untouched; this painter is only the fallback/generated art.
    final spine = Rect.fromLTWH(0, 0, math.max(7, w * .079), h);
    canvas.drawRect(spine, Paint()..shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.black.withValues(alpha: .25),
        Colors.black.withValues(alpha: .075),
        Colors.white.withValues(alpha: .06),
      ],
    ).createShader(spine));
    final hinge = Paint()
      ..color = palette.ink.withValues(alpha: .26)
      ..strokeWidth = math.max(.55, w / 260);
    canvas.drawLine(Offset(spine.right + 2, 11),
        Offset(spine.right + 2, h - 11), hinge);
    canvas.drawLine(Offset(spine.right + 5, 11),
        Offset(spine.right + 5, h - 11),
        Paint()..color = palette.ink.withValues(alpha: .10)
          ..strokeWidth = .5);
    final border = Paint()
      ..color = palette.ink.withValues(alpha: .4)
      ..strokeWidth = math.max(.6, w / 170)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTRB(8, 8, w - 8, h - 8), border);
    final inner = Paint()
      ..color = palette.ink.withValues(alpha: .13)
      ..strokeWidth = .55
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTRB(
        math.max(13, w * .082), 13, w - 13, h - 13), inner);

    // Deterministic 3% paper grain; rendered once into the LRU picture.
    final seed = stableTitleHash(title);
    final grain = Paint()..color = palette.ink.withValues(alpha: .03);
    for (var i = 0; i < math.min(180, (w * h / 115).floor()); i++) {
      final x = ((seed + i * 1733) % 997) / 997 * w;
      final y = ((seed ~/ 37 + i * 2851) % 991) / 991 * h;
      canvas.drawCircle(Offset(x, y), .5, grain);
    }

    final narrow = w < 82;
    final graphemes = title.runes.map((r) => String.fromCharCode(r))
        .where((s) => s.trim().isNotEmpty).take(16).toList();
    final columns = <List<String>>[];
    for (var start = 0; start < graphemes.length; start += 8) {
      columns.add(graphemes.skip(start).take(8).toList());
      if (columns.length == 2) break;
    }
    final rows = columns.isEmpty ? 1 : columns.first.length;
    final font = (w * (narrow ? .24 : .18))
        .clamp(narrow ? 10.0 : 14.0, narrow ? 15.0 : 23.0);
    final step = math.min(font * 1.25, (h - 56) / rows);
    final punctuation = RegExp(r'^[，。！？、；：,.;:!?]$');
    for (var col = 0; col < columns.length; col++) {
      for (var row = 0; row < columns[col].length; row++) {
        final symbol = columns[col][row];
        final punct = punctuation.hasMatch(symbol);
        final text = TextPainter(
          text: TextSpan(text: symbol, style: TextStyle(
            fontFamily: HyesTokens.serifFamily,
            fontFamilyFallback: const ['Noto Serif CJK SC', 'serif'],
            fontSize: punct ? font * .72 : font,
            fontWeight: FontWeight.w600, color: palette.ink)),
          textDirection: TextDirection.ltr, maxLines: 1,
        )..layout();
        text.paint(canvas, Offset(
          w - 20 - col * font * 1.48 - text.width / 2,
          23 + row * step + (punct ? font * .20 : 0),
        ));
        text.dispose();
      }
    }

    if (showSeal) {
      // Two-pixel round-corner, -4-degree vermilion square seal.
      final seal = math.min(w * .23, 28.0);
      canvas.save();
      canvas.translate(w - 15 - seal / 2, h - 19 - seal / 2);
      canvas.rotate(-4 * math.pi / 180);
      const accent = Color(0xFFB8412F);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(-seal / 2, -seal / 2, seal, seal),
        const Radius.circular(2)),
        Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final stamp = TextPainter(text: TextSpan(
        text: graphemes.isEmpty ? '阅' : graphemes.first,
        style: TextStyle(color: accent, fontFamily: HyesTokens.serifFamily,
          fontWeight: FontWeight.w600, fontSize: seal * .64)),
        textDirection: TextDirection.ltr)..layout();
      stamp.paint(canvas, Offset(-stamp.width / 2, -stamp.height / 2));
      stamp.dispose();
      canvas.restore();
    }

    final label = TextPainter(text: TextSpan(
      text: format.toUpperCase(),
      style: TextStyle(fontSize: math.max(6.5, w * .075), letterSpacing: 1.2,
        color: palette.ink.withValues(alpha: .84))),
      textDirection: TextDirection.ltr, maxLines: 1)..layout();
    label.paint(canvas, Offset(14, h - 16 - label.height / 2));
    label.dispose();
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, h), Paint()
      ..shader = const LinearGradient(colors: [
        Color(0x2EFFFFFF), Color(0x00FFFFFF),
      ]).createShader(Rect.fromLTWH(0, 0, 3, h)));
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      title != oldDelegate.title || format != oldDelegate.format ||
      showSeal != oldDelegate.showSeal;
}

int _averageThumbnail(Uint8List rgba) {
  var red = 0, green = 0, blue = 0, total = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (r > 238 && g > 238 && b > 238) continue;
    red += r; green += g; blue += b; total++;
  }
  if (total == 0) return 0;
  return 0xff000000 | ((red ~/ total) << 16) |
      ((green ~/ total) << 8) | (blue ~/ total);
}

/// Real EPUB cover color: 16x16 thumbnail, then isolate-side averaging.
class CoverColorCache {
  static final _colors = LinkedHashMap<String, Future<Color>>();
  static Future<Color> read(BookEntry book) {
    final previous = _colors.remove(book.id);
    if (previous != null) {
      _colors[book.id] = previous;
      return previous;
    }
    final generated = coverPaletteFor(book.title).background;
    final task = () async {
      if (!book.isEpub) return generated;
      final bytes = await EpubCoverCache.read(book);
      if (bytes == null) return generated;
      ui.Codec? codec;
      ui.Image? image;
      try {
        codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 16, targetHeight: 16);
        image = (await codec.getNextFrame()).image;
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) return generated;
        final dominant = await compute(_averageThumbnail, raw.buffer.asUint8List());
        return dominant == 0 ? generated : Color(dominant);
      } catch (_) {
        return generated;
      } finally {
        image?.dispose();
        codec?.dispose();
      }
    }();
    _colors[book.id] = task;
    if (_colors.length > 40) _colors.remove(_colors.keys.first);
    return task;
  }
}
