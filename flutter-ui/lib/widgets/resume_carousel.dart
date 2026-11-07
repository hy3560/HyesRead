import 'dart:async';

import 'package:flutter/material.dart';

import '../data/book_entry.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'book_cover.dart';
import 'paper_button.dart';

/// A PageView of books with previously saved reading sessions.
class ResumeCarousel extends StatefulWidget {
  const ResumeCarousel({super.key, required this.books, required this.onOpen});
  final List<BookEntry> books;
  final ValueChanged<BookEntry> onOpen;
  @override
  State<ResumeCarousel> createState() => _ResumeCarouselState();
}

class _ResumeCarouselState extends State<ResumeCarousel> {
  late final PageController _controller = PageController(viewportFraction: .68);
  int _current = 0;
  String? _selectedBookId;
  bool _synchronizingSelection = false;

  @override
  void initState() {
    super.initState();
    if (widget.books.isNotEmpty) _selectedBookId = widget.books.first.id;
  }

  @override
  void didUpdateWidget(covariant ResumeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Preserve the chosen book when recently-read order changes.
    final preserved = widget.books.indexWhere((b) => b.id == _selectedBookId);
    final next = preserved >= 0 ? preserved : widget.books.isEmpty
        ? 0 : _current.clamp(0, widget.books.length - 1);
    final moved = next != _current;
    _current = next;
    _selectedBookId = widget.books.isEmpty ? null : widget.books[next].id;
    if (moved) {
      _synchronizingSelection = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controller.hasClients) {
          _controller.jumpToPage(_current);
        }
        _synchronizingSelection = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_synchronizingSelection) return;
    if (index < 0 || index >= widget.books.length || index == _current) return;
    HyesMotion.selected(context);
    setState(() {
      _current = index;
      _selectedBookId = widget.books[index].id;
    });
  }

  void _moveSelection(int offset) {
    final target = _current + offset;
    if (target < 0 || target >= widget.books.length) return;
    // Use the same native page physics for buttons and swipes. No abrupt
    // teleport and no perspective distortion of book covers.
    if (_controller.hasClients) {
      if (HyesMotion.reduced(context)) {
        _controller.jumpToPage(target);
      } else {
        unawaited(_controller.animateToPage(target,
          duration: const Duration(milliseconds: 310),
          curve: Curves.easeOutCubic));
      }
    }
    _select(target);
  }

  Widget _coverItem(BookEntry book, double width, double height) {
    return GestureDetector(
      onTap: () => widget.onOpen(book),
      child: Semantics(
        button: true,
        label: '继续阅读《${book.title}》',
        child: Hero(
          tag: 'hyes-cover-${book.id}',
          child: BookCover(book: book, width: width, height: height),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HyesTokens.of(context);
    if (widget.books.isEmpty) return const SizedBox.shrink();
    final book = widget.books[_current];
    final reduced = HyesMotion.reduced(context);
    final w = MediaQuery.sizeOf(context).width;
    final compactRail = w < 360 ||
        MediaQuery.textScalerOf(context).scale(12) > 18;
    final coverWidth = (w * .46).clamp(116.0, 200.0);
    final coverHeight = coverWidth * 1.5;
    final boxHeight = coverHeight + 42;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: boxHeight, child: Stack(alignment: Alignment.topCenter,
        children: [
          Positioned(left: 32, right: 32, bottom: 13, height: 1,
            child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                tokens.divider.withValues(alpha: 0),
                tokens.divider,
                tokens.divider.withValues(alpha: 0),
              ]),
            ))),
          PageView.builder(
            key: const ValueKey('resume-cover-gallery'),
            controller: _controller,
            itemCount: widget.books.length,
            onPageChanged: _select,
            itemBuilder: (context, index) => AnimatedBuilder(
              animation: _controller,
              child: Center(child: _coverItem(
                widget.books[index], coverWidth, coverHeight)),
              builder: (context, child) {
                if (reduced) return child!;
                final offset = _controller.hasClients &&
                        _controller.positions.length == 1 &&
                        _controller.position.hasContentDimensions
                    ? (_controller.page ?? _current.toDouble())
                    : _current.toDouble();
                final distance = (index - offset).abs().clamp(0.0, 1.0);
                // Neighbors recede a little in the same plane. Book covers
                // stay upright, fully readable and free of fake perspective.
                return Transform.translate(
                  offset: Offset(0, 10 * distance),
                  child: Transform.scale(scale: 1 - .075 * distance,
                    child: child),
                );
              },
            ),
          ),
        ])),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : HyesMotion.base,
          switchInCurve: HyesMotion.enter,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: reduced ? Offset.zero : const Offset(0, .07),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(book.title, key: ValueKey(book.id),
            textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tokens.title),
        )),
      ),
      if (widget.books.length > 1) ...[
        const SizedBox(height: 6),
        Row(children: [
          IconButton(
            key: const ValueKey('resume-previous'),
            tooltip: '上一部书',
            style: IconButton.styleFrom(foregroundColor: tokens.secondary),
            onPressed: _current > 0 ? () => _moveSelection(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Expanded(child: Semantics(
            liveRegion: true,
            label: '第 ${_current + 1} 部，共 ${widget.books.length} 部',
            child: ExcludeSemantics(child: compactRail
              ? Center(child: Text(
                  '${(_current + 1).toString().padLeft(2, '0')} / '
                  '${widget.books.length.toString().padLeft(2, '0')}',
                  key: const ValueKey('resume-position'),
                  style: tokens.number.copyWith(letterSpacing: .8),
                ))
              : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.books.length; i++)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: reduced ? Duration.zero : HyesMotion.base,
                      curve: HyesMotion.enter,
                      height: 3,
                      width: i == _current ? 18 : 6,
                      decoration: BoxDecoration(
                        color: i == _current ? tokens.vermilion
                            : tokens.secondary.withValues(alpha: .30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            )),
          )),
          if (!compactRail) Text(
              '${(_current + 1).toString().padLeft(2, '0')} / '
              '${widget.books.length.toString().padLeft(2, '0')}',
              key: const ValueKey('resume-position'),
              style: tokens.number.copyWith(letterSpacing: .8)),
          IconButton(
            key: const ValueKey('resume-next'),
            tooltip: '下一部书',
            style: IconButton.styleFrom(foregroundColor: tokens.secondary),
            onPressed: _current < widget.books.length - 1
                ? () => _moveSelection(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ]),
      ],
      const SizedBox(height: 7),
      Center(child: Text(book.hasReading
          ? '已读 ${(book.progress * 100).round()}%' : '未开始',
        style: tokens.caption)),
      const SizedBox(height: 16),
      if (book.hasReading) ...[
        TweenAnimationBuilder<double>(
          key: ValueKey('progress-${book.id}'),
          tween: Tween(begin: 0, end: book.progress.clamp(0, 1)),
          duration: HyesMotion.duration(context,
              const Duration(milliseconds: 600)),
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(value: value, minHeight: 2,
              backgroundColor: tokens.divider, color: tokens.vermilion),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Center(child: PaperButton(label: '继续阅读',
        icon: Icons.arrow_forward_rounded, onPressed: () => widget.onOpen(book))),
    ]);
  }
}
