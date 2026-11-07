import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/book_entry.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'book_cover.dart';

/// An actual library history visualization, never a reading-time estimate.
/// The varying spine heights are deterministic from the title FNV-1a hash.
class BookSpineWall extends StatelessWidget {
  const BookSpineWall({super.key, required this.books, required this.onOpen});

  final List<BookEntry> books;
  final ValueChanged<BookEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = HyesTokens.of(context);
    final reduced = HyesMotion.reduced(context);
    return SizedBox(height: 184, child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 8, bottom: 7),
      itemCount: books.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final book = books[index];
        final palette = coverPaletteFor(book.title);
        final h = 120.0 + stableTitleHash(book.title) % 49;
        final fill = book.progress.clamp(0, 1).toDouble();
        final characters = book.title.runes.map(String.fromCharCode)
            .where((ch) => ch.trim().isNotEmpty).take(8).toList();
        return Align(alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('spine-${book.id}'),
            tween: Tween(begin: 0, end: 1),
            duration: reduced ? Duration.zero :
                Duration(milliseconds: 230 + math.min(index, 9) * 18),
            curve: Curves.easeOutCubic,
            builder: (context, fraction, child) => Transform.translate(
              offset: Offset(0, reduced ? 0 : (1 - fraction) * 10),
              child: Opacity(opacity: reduced ? 1 : fraction, child: child)),
            child: _SpineHover(reduced: reduced, child: Semantics(button: true,
              label: '打开《${book.title}》，'
                  '${book.hasReading ? '已读 ${(book.progress * 100).round()}%' : '尚未开始'}',
              child: Material(type: MaterialType.transparency,
                child: InkWell(
                  onTap: () {
                    HyesMotion.selected(context);
                    onOpen(book);
                  },
                  child: Hero(tag: 'hyes-cover-${book.id}',
                    child: Container(width: 36, height: h,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: t.divider)),
                      child: Stack(children: [
                        if (fill > 0) Positioned.fill(child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(heightFactor: fill,
                            widthFactor: 1,
                            child: ColoredBox(color:
                              palette.ink.withValues(alpha: .18))))),
                        Positioned(left: 2, top: 0, bottom: 0,
                          child: Container(width: 2,
                            color: palette.ink.withValues(alpha: .22))),
                        Padding(padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              for (final ch in characters)
                                Center(child: Text(ch, style: TextStyle(
                                  fontFamily: HyesTokens.serifFamily,
                                  fontSize: 11, height: 1.38,
                                  color: palette.ink,
                                  fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            )),
          ),
        );
      },
    ));
  }
}

/// Desktop hover is subtle; shelves do not rubber-band vertically on entry.
class _SpineHover extends StatefulWidget {
  const _SpineHover({required this.child, required this.reduced});
  final Widget child;
  final bool reduced;

  @override
  State<_SpineHover> createState() => _SpineHoverState();
}

class _SpineHoverState extends State<_SpineHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: AnimatedSlide(
      offset: _hover && !widget.reduced
          ? const Offset(0, -.045) : Offset.zero,
      duration: widget.reduced ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

/// Facts only: TXT paragraph, PDF page, or opaque EPUB anchor.
String trueReadingLocation(BookEntry book) {
  if (book.isText) {
    return '第 ${book.paragraphIndex + 1} 段 · '
        '位置约 ${(book.progress * 100).round()}%';
  }
  if (book.isPdf) {
    return '第 ${book.pdfPage} 页 · '
        '位置约 ${(book.progress * 100).round()}%';
  }
  return book.hasReading
      ? '已读 ${(book.progress * 100).round()}%' : '未开始';
}

String trueRelativeOpenedAt(int epochMs, DateTime now) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final difference = now.difference(time);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes} 分钟前';
  if (difference.inHours < 24) return '${difference.inHours} 小时前';
  if (difference.inDays == 1) return '昨天';
  if (difference.inDays < 30) return '${difference.inDays} 天前';
  return '${time.year}年${time.month}月${time.day}日';
}
