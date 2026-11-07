import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../ui/text_page_layout.dart';
import '../ui/reader_typography.dart';

/// A real, lazy sheet-by-sheet TXT/Markdown reader. Horizontal gestures,
/// mouse wheel, keyboard arrows and the visible controls all change content.
/// No continuous animation is active when the reader is idle.
class TextPageReader extends StatefulWidget {
  const TextPageReader({super.key, required this.paragraphs,
    required this.initialCursor, required this.title,
    required this.paper, required this.ink, required this.contentWidth,
    required this.fontSize, required this.lineHeight,
    required this.paragraphSpacing, required this.justify,
    required this.topInset, required this.onPositionChanged,
    this.minimalChrome = false, this.surround, this.fontFamily});

  final List<String> paragraphs;
  final TextPageCursor initialCursor;
  final String title;
  final Color paper, ink;
  final double contentWidth, fontSize, lineHeight, paragraphSpacing, topInset;
  final bool justify;
  final ValueChanged<TextPageCursor> onPositionChanged;
  final bool minimalChrome;
  final Color? surround;
  final String? fontFamily;

  @override
  State<TextPageReader> createState() => TextPageReaderState();
}

class TextPageReaderState extends State<TextPageReader>
    with SingleTickerProviderStateMixin {
  late TextPageCursor _cursor = widget.initialCursor;
  final List<TextPageCursor> _history = [];
  final List<TextPageCursor> _forward = [];
  TextPageLayouter? _layouter;
  TextPageResult? _page;
  TextPageResult? _rightPage;
  TextPageCursor? _spreadNext;
  bool _spread = false;
  Object? _layoutSignature;
  int _lastDirection = 1;
  int _epoch = 0;
  int? _dragPointer;
  Offset? _dragStart, _dragLast;
  PointerDeviceKind? _dragKind;
  DateTime? _wheelTurnAt;
  // Drag-driven transform runs without rebuilding measured Chinese text.
  late final AnimationController _dragPreview;
  int _previewDirection = 1;
  // Mouse-only affordance; 0 when the pointer is away from either page edge.
  int _hoverEdge = 0;

  @override
  void initState() {
    super.initState();
    _dragPreview = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _dragPreview.dispose();
    super.dispose();
  }

  void _settleDragPreview() {
    if (_dragPreview.value <= 0) return;
    if (HyesMotion.reduced(context)) {
      _dragPreview.value = 0;
    } else {
      _dragPreview.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  void _setHoverEdge(int edge) {
    if (_hoverEdge != edge && mounted) {
      setState(() => _hoverEdge = edge);
    }
  }

  void _onPaperHover(PointerHoverEvent event, double sheetWidth) {
    if (HyesMotion.reduced(context) ||
        event.kind != PointerDeviceKind.mouse ||
        _dragPointer != null) {
      _setHoverEdge(0);
      return;
    }
    final x = event.localPosition.dx;
    final edge = x <= 58 && canGoBack
        ? -1 : x >= sheetWidth - 58 && canGoForward ? 1 : 0;
    _setHoverEdge(edge);
  }

  bool _mouseStartsAtPaperEdge(double x, double viewportWidth) {
    if (viewportWidth <= 0) return false;
    final sheetWidth = _sheetWidth(viewportWidth, _spread);
    final left = (viewportWidth - sheetWidth) / 2;
    final right = left + sheetWidth;
    return x >= left && x <= right &&
        (x - left <= 72 || right - x <= 72);
  }

  // Two facing pages only when both columns remain legible. A saved cursor
  // is device-independent, so resizing never modifies persisted page numbers.
  bool _canShowSpread(double width, double height, TextScaler scaler) =>
      width >= 760 && height >= 440 &&
      scaler.scale(widget.fontSize) <= 29;

  double _sheetWidth(double viewportWidth, bool spread) => math.min(
      viewportWidth - (viewportWidth >= 680 ? 48 : 0),
      spread ? 2 * (widget.contentWidth + 48) + 32
          : widget.contentWidth + 48).clamp(220.0, double.infinity);

  @override
  void didUpdateWidget(covariant TextPageReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent only updates initialCursor on a deliberate new book / jump.
    // Normal page turns are driven by this widget and reported to the parent.
    if (!identical(widget.paragraphs, oldWidget.paragraphs)) {
      _dragPreview.value = 0;
      _cursor = widget.initialCursor;
      _history.clear();
      _forward.clear();
      _layoutSignature = null;
    }
  }

  TextPageCursor get currentCursor => _cursor;

  void jumpTo(TextPageCursor position) {
    if (_layouter == null) return;
    final target = _layouter!.normalize(position);
    if (target == _cursor) return;
    _dragPreview.value = 0;
    setState(() {
      _cursor = target;
      _history.clear();
      _forward.clear();
      _epoch++;
    });
    widget.onPositionChanged(target);
  }

  bool get canGoForward => _forward.isNotEmpty || _spreadNext != null;
  bool get canGoBack => _history.isNotEmpty ||
      _cursor.paragraph > 0 || _cursor.offset > 0;

  void nextPage() => _turn(1);
  void previousPage() => _turn(-1);

  void _turn(int direction) {
    if (_layouter == null || _page == null) return;
    _dragPreview.value = 0;
    TextPageCursor? target;
    if (direction > 0) {
      target = _forward.isNotEmpty ? _forward.removeLast() : _spreadNext;
      if (target == null) return;
      _history.add(_cursor);
    } else {
      final hasHistory = _history.isNotEmpty;
      target = hasHistory
          ? _history.removeLast() : _layouter!.approximatePrevious(_cursor);
      if (!hasHistory && _spread && target != null) {
        // Approximate the preceding pair only for a reopened position that
        // has no navigation history. Normal turns always use exact anchors.
        target = _layouter!.approximatePrevious(target) ?? target;
      }
      if (target == null || target == _cursor) return;
      _forward.add(_cursor);
    }
    setState(() {
      _cursor = target!;
      _lastDirection = direction;
      _epoch++;
      // Recomputed on the next build with the latest page size and typography.
      _page = null;
    });
    widget.onPositionChanged(target);
  }

  void _onWheel(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    final dy = signal.scrollDelta.dy;
    if (dy.abs() < 6) return;
    final now = DateTime.now();
    if (_wheelTurnAt != null &&
        now.difference(_wheelTurnAt!) < const Duration(milliseconds: 280)) {
      return;
    }
    _wheelTurnAt = now;
    _turn(dy > 0 ? 1 : -1);
  }

  // Passive pointer tracking survives the selection gesture arena. A swipe
  // still turns a real page on touch; mouse drags only turn from the edges so
  // ordinary desktop text selection remains possible.
  void _pointerDown(PointerDownEvent event) {
    if (_dragPointer != null) return;
    _setHoverEdge(0);
    _dragPreview.stop();
    _dragPreview.value = 0;
    _dragPointer = event.pointer;
    _dragStart = event.localPosition;
    _dragLast = event.localPosition;
    _dragKind = event.kind;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer) return;
    _dragLast = event.localPosition;
    if (HyesMotion.reduced(context)) return;
    final start = _dragStart;
    if (start == null) return;
    final dx = event.localPosition.dx - start.dx;
    final dy = event.localPosition.dy - start.dy;
    final width = context.size?.width ?? 0;
    // Preserve mouse text selection except at the outer 72px page edges.
    final mouseInBody = _dragKind == PointerDeviceKind.mouse &&
        !_mouseStartsAtPaperEdge(start.dx, width);
    final direction = dx < 0 ? 1 : -1;
    if (mouseInBody || dx.abs() < 12 || dx.abs() < dy.abs() * 1.5 ||
        (direction > 0 ? !canGoForward : !canGoBack)) {
      _dragPreview.value = 0;
      return;
    }
    _previewDirection = direction;
    final extent = math.max(220.0,
        math.min(widget.contentWidth, width > 0 ? width : 360.0));
    _dragPreview.value = ((dx.abs() - 12) / (extent * .55))
        .clamp(0.0, 1.0);
  }

  void _pointerUp(PointerEvent event) {
    if (event.pointer != _dragPointer) return;
    final start = _dragStart;
    final end = _dragLast;
    final kind = _dragKind;
    _dragPointer = null;
    _dragStart = null;
    _dragLast = null;
    _dragKind = null;
    if (start == null || end == null) {
      _settleDragPreview();
      return;
    }
    final dx = end.dx - start.dx, dy = end.dy - start.dy;
    if (dx.abs() < 65 || dx.abs() < dy.abs() * 1.5) {
      _settleDragPreview();
      return;
    }
    final width = context.size?.width ?? 0;
    if (kind == PointerDeviceKind.mouse &&
        !_mouseStartsAtPaperEdge(start.dx, width)) {
      _settleDragPreview();
      return;
    }
    final direction = dx < 0 ? 1 : -1;
    if (direction > 0 ? canGoForward : canGoBack) {
      if (kind == PointerDeviceKind.touch ||
          kind == PointerDeviceKind.stylus) {
        HyesMotion.selected(context);
      }
      _turn(direction);
    } else {
      _settleDragPreview();
    }
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _dragPointer) return;
    _dragPointer = null;
    _dragStart = null;
    _dragLast = null;
    _dragKind = null;
    _settleDragPreview();
  }

  /// Each leaf has a separate selection boundary. The second starts at the
  /// first leaf's exact next cursor; the page measure is never guessed.
  Widget _leafText(TextPageResult page, {
    required String identity,
    required TextStyle bodyStyle,
    required TextStyle headingStyle,
    required TextStyle chapterStyle,
    required Color accent,
  }) => SelectionArea(
    key: ValueKey('paper-page-$identity'),
    child: Align(alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final piece in page.pieces) ...[
            if (piece.chapter)
              const SizedBox(height: 64)
            else if (piece.heading)
              SizedBox(height: headingStyle.fontSize! * 1.8),
            Padding(
              padding: EdgeInsets.only(bottom: piece.endsParagraph
                  ? piece.heading ? widget.fontSize * .7
                      : widget.paragraphSpacing : 0),
              child: piece.heading && !piece.chapter
                  ? Row(crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(width: 3, height: widget.fontSize,
                          color: accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text(piece.text, style: headingStyle)),
                      ])
                  : Text(piece.indent
                        ? '\u3000\u3000${piece.text}' : piece.text,
                      textAlign: piece.chapter
                          ? TextAlign.center
                          : widget.justify ? TextAlign.justify : TextAlign.start,
                      style: piece.chapter ? chapterStyle : bodyStyle),
            ),
            if (piece.chapter) ...[
              const SizedBox(height: 18),
              Center(child: SizedBox(width: 24, height: 2,
                child: ColoredBox(color: accent))),
            ],
          ],
        ],
      )),
  );

  @override
  Widget build(BuildContext context) {
    final reduced = HyesMotion.reduced(context);
    final tokens = HyesTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 680;

    return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowRight): nextPage,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): previousPage,
      const SingleActivator(LogicalKeyboardKey.pageDown): nextPage,
      const SingleActivator(LogicalKeyboardKey.pageUp): previousPage,
    }, child: Focus(
      autofocus: true,
      child: Listener(onPointerSignal: _onWheel,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        behavior: HitTestBehavior.translucent,
        child: ColoredBox(color: widget.surround ?? tokens.background,
            child: LayoutBuilder(builder: (context, bounds) {
              final spread = _canShowSpread(
                  bounds.maxWidth, bounds.maxHeight, scaler);
              final width = _sheetWidth(bounds.maxWidth, spread);
              final height = math.max(220.0,
                  bounds.maxHeight - widget.topInset);
              final availableHeight = math.max(120.0,
                  height - (widget.minimalChrome ? 60 : 150));
              // Exactly match the flex widths in the facing-page body row.
              const gutter = 30.0;
              final contentAreaWidth = width - (wide ? 104 : 44);
              final textWidth = math.max(140.0, spread
                  ? (contentAreaWidth - gutter) / 2 : contentAreaWidth);
              final bodyStyle = TextStyle(color: widget.ink,
                fontFamily: widget.fontFamily ?? HyesTokens.serifFamily,
                fontFamilyFallback: readerFontFallback,
                fontSize: widget.fontSize, height: widget.lineHeight,
                letterSpacing: widget.fontSize * .02,
                fontFeatures: const [FontFeature.enable('palt')]);
              final headingStyle = bodyStyle.copyWith(
                fontFamily: HyesTokens.serifFamily,
                fontSize: widget.fontSize * 1.12,
                height: 1.5, fontWeight: FontWeight.w600,
                letterSpacing: .5);
              final chapterStyle = headingStyle.copyWith(
                fontSize: widget.fontSize * 1.3, height: 1.4);
              final signature = Object.hash(width, availableHeight, spread,
                widget.fontSize, widget.lineHeight, widget.paragraphSpacing,
                widget.justify, widget.fontFamily,
                scaler.scale(20), textDirection);
              if (_layoutSignature != signature) {
                _layoutSignature = signature;
                _history.clear();
                _forward.clear();
              }
              _layouter = TextPageLayouter(paragraphs: widget.paragraphs,
                width: textWidth, height: availableHeight,
                bodyStyle: bodyStyle, headingStyle: headingStyle,
                chapterStyle: chapterStyle,
                textScaler: scaler, direction: textDirection,
                paragraphSpacing: widget.paragraphSpacing);
              _cursor = _layouter!.normalize(_cursor);
              final page = _layouter!.layout(_cursor);
              _page = page;
              _spread = spread;
              _rightPage = spread && page.next != null
                  ? _layouter!.layout(page.next!) : null;
              // A final right leaf has no successor. Do not fall back to its
              // start cursor and show the last page twice.
              _spreadNext = spread ? _rightPage?.next : page.next;

              return Center(child: Padding(
                padding: EdgeInsets.only(top: widget.topInset),
                child: SizedBox(width: width, height: height,
                  child: MouseRegion(
                    key: const ValueKey('paper-edge-hover-region'),
                    onHover: (event) => _onPaperHover(event, width),
                    onExit: (_) => _setHoverEdge(0),
                    cursor: _hoverEdge == 0
                        ? MouseCursor.defer : SystemMouseCursors.grab,
                    child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.paper,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: widget.ink.withValues(
                          alpha: wide ? .065 : 0)),
                      boxShadow: wide ? [BoxShadow(
                        color: Colors.black.withValues(alpha: .04),
                        blurRadius: 18, offset: const Offset(0, 6)),
                      ] : null,
                    ),
                    child: Stack(children: [
                      // A slender binding edge, not a fake 3D animation loop.
                      Positioned(left: 0, top: 0, bottom: 0,
                        child: Container(width: 7, decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(colors: [
                            widget.ink.withValues(alpha: .12),
                            widget.ink.withValues(alpha: .035),
                            Colors.transparent,
                          ]),
                        ))),
                      Padding(
                        padding: EdgeInsets.fromLTRB(wide ? 52 : 22,
                            widget.minimalChrome ? 28 : 14,
                            wide ? 52 : 22, widget.minimalChrome ? 24 : 8),
                        child: Column(children: [
                          if (!widget.minimalChrome) ...[
                          SizedBox(height: 38, child: Row(children: [
                            Text('HYESREAD',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(color: tokens.vermilion,
                                letterSpacing: 2.3, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                            const SizedBox(width: 13),
                            Expanded(child: Text(widget.title,
                              textScaler: TextScaler.noScaling,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 12,
                                color: widget.ink.withValues(alpha: .65),
                                fontFamily: HyesTokens.serifFamily))),
                          ])),
                          Divider(height: 1,
                            color: widget.ink.withValues(alpha: .13)),
                          const SizedBox(height: 18),
                          ],
                          Expanded(child: ClipRect(child: _GestureLeafPreview(
                            animation: _dragPreview,
                            direction: () => _previewDirection,
                            reduced: reduced,
                            paper: widget.paper,
                            ink: widget.ink,
                            child: AnimatedSwitcher(
                            // Reflow instantly on resize/type-scale changes:
                            // a departing two-column tree must never be
                            // squeezed into a one-column sheet.
                            key: ValueKey('paper-layout-$signature'),
                            duration: reduced ? Duration.zero
                                : const Duration(milliseconds: 290),
                            layoutBuilder: (current, previous) => Stack(
                              fit: StackFit.expand,
                              children: [...previous, ?current]),
                            transitionBuilder: (child, animation) =>
                              AnimatedBuilder(animation: animation,
                                builder: (context, _) {
                                  // Both a leaf and a spread stay anchored.
                                  // No theatrical 70-degree whole-page flip.
                                  final outgoing = animation.status ==
                                      AnimationStatus.reverse;
                                  final t = animation.value;
                                  final angle = (1 - t) *
                                      (spread ? .042 : .075) *
                                      (outgoing ? 1 : -1);
                                  final matrix = Matrix4.identity();
                                  if (!reduced) {
                                    matrix.setEntry(3, 2, .00085);
                                    matrix.rotateY(angle *
                                        (_lastDirection > 0 ? 1 : -1));
                                  }
                                  // Hand the paper over in sequence. The
                                  // previous crossfade made both text pages
                                  // readable on top of each other mid-turn.
                                  const handoff = .46;
                                  final phase = outgoing
                                      ? ((1 - t) / handoff).clamp(0.0, 1.0)
                                      : ((t - handoff) / (1 - handoff))
                                          .clamp(0.0, 1.0);
                                  final opacity = reduced ? 1.0
                                      : outgoing
                                          ? 1 - Curves.easeInCubic.transform(phase)
                                          : Curves.easeOutCubic.transform(phase);
                                  final fold = reduced ? 0.0
                                      : math.sin(math.pi * t)
                                          .clamp(0.0, 1.0).toDouble();
                                  return IgnorePointer(ignoring: outgoing,
                                    child: Transform(
                                      alignment: spread ? Alignment.center
                                          : _lastDirection > 0
                                              ? Alignment.centerLeft
                                              : Alignment.centerRight,
                                      transform: matrix,
                                      child: Opacity(
                                        key: const ValueKey('reader-leaf-handoff'),
                                        opacity: opacity,
                                        child: Transform.translate(
                                          offset: Offset(
                                            (outgoing ? 1 : -1) *
                                                (_lastDirection > 0 ? 1 : -1) *
                                                (spread ? 5 : 8) * (1 - t),
                                            -2 * fold),
                                          child: Stack(fit: StackFit.expand,
                                            children: [
                                              child,
                                              if (fold > .005)
                                                Positioned.fill(child: IgnorePointer(
                                                  child: DecoratedBox(
                                                    key: const ValueKey('reader-leaf-turn-shade'),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: _lastDirection > 0
                                                            ? Alignment.centerRight
                                                            : Alignment.centerLeft,
                                                        end: _lastDirection > 0
                                                            ? Alignment.centerLeft
                                                            : Alignment.centerRight,
                                                        stops: const [0, .09, .45, 1],
                                                        colors: [
                                                          widget.ink.withValues(alpha: .17 * fold),
                                                          widget.ink.withValues(alpha: .075 * fold),
                                                          widget.paper.withValues(alpha: .015 * fold),
                                                          Colors.transparent,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                )),
                                              if (fold > .005)
                                                Positioned(
                                                  left: _lastDirection > 0 ? null : 0,
                                                  right: _lastDirection > 0 ? 0 : null,
                                                  top: 0, bottom: 0, width: 2.5,
                                                  child: IgnorePointer(
                                                    child: DecoratedBox(
                                                      key: const ValueKey('reader-leaf-turn-glint'),
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: _lastDirection > 0
                                                              ? Alignment.centerLeft
                                                              : Alignment.centerRight,
                                                          end: _lastDirection > 0
                                                              ? Alignment.centerRight
                                                              : Alignment.centerLeft,
                                                          colors: [
                                                            widget.paper.withValues(alpha: .34 * fold),
                                                            widget.ink.withValues(alpha: .11 * fold),
                                                            Colors.transparent,
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            child: spread
                                ? KeyedSubtree(
                                    key: ValueKey('paper-spread-${_cursor.paragraph}-${_cursor.offset}-$_epoch'),
                                    child: Row(
                                      key: const ValueKey('paper-facing-pages'),
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: _leafText(page,
                                          identity: 'left-${_cursor.paragraph}-${_cursor.offset}-$_epoch',
                                          bodyStyle: bodyStyle,
                                          headingStyle: headingStyle,
                                          chapterStyle: chapterStyle,
                                          accent: tokens.vermilion)),
                                        SizedBox(width: gutter,
                                          child: IgnorePointer(child: DecoratedBox(
                                            decoration: BoxDecoration(gradient: LinearGradient(
                                              colors: [
                                                widget.ink.withValues(alpha: .01),
                                                widget.ink.withValues(alpha: .035),
                                                widget.ink.withValues(alpha: .075),
                                                widget.ink.withValues(alpha: .018),
                                              ],
                                              stops: const [0, .44, .5, 1],
                                            )),
                                            child: Center(child: Container(
                                              width: 1, color: widget.ink.withValues(alpha: .09))),
                                          ))),
                                        Expanded(child: _rightPage == null
                                            ? const SizedBox.shrink()
                                            : _leafText(_rightPage!,
                                              identity: 'right-${page.next?.paragraph}-${page.next?.offset}-$_epoch',
                                              bodyStyle: bodyStyle,
                                              headingStyle: headingStyle,
                                              chapterStyle: chapterStyle,
                                              accent: tokens.vermilion)),
                                      ],
                                    ))
                                : _leafText(page,
                                    identity: '${_cursor.paragraph}-${_cursor.offset}-$_epoch',
                                    bodyStyle: bodyStyle,
                                    headingStyle: headingStyle,
                                    chapterStyle: chapterStyle,
                                    accent: tokens.vermilion),
                          )))),
                          if (!widget.minimalChrome) ...[
                          Divider(height: 1,
                            color: widget.ink.withValues(alpha: .10)),
                          const SizedBox(height: 2),
                          SizedBox(height: 48, child: Row(children: [
                            IconButton(
                              key: const ValueKey('paper-previous-page'),
                              tooltip: '上一页', onPressed: canGoBack ? previousPage : null,
                              icon: const Icon(Icons.chevron_left_rounded),
                              color: widget.ink,
                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                            Expanded(child: Semantics(liveRegion: true,
                              label: '当前从第 ${_cursor.paragraph + 1} 段开始',
                              child: Text('第 ${_cursor.paragraph + 1} / '
                                  '${widget.paragraphs.length} 段',
                                key: const ValueKey('paper-page-position'),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: widget.ink.withValues(alpha: .7),
                                    fontSize: 12, fontFeatures: const [
                                      FontFeature.tabularFigures()])))),
                            IconButton(
                              key: const ValueKey('paper-next-page'),
                              tooltip: '下一页', onPressed: canGoForward ? nextPage : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                              color: widget.ink,
                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                          ])),
                          ],
                        ]),
                      ),
                      if (wide) ...[
                        Positioned(
                          right: 0, bottom: 0,
                          child: _PageCornerFold(
                            key: const ValueKey('paper-corner-next'),
                            visible: !reduced && _hoverEdge == 1 &&
                                canGoForward && _dragPreview.value == 0,
                            forward: true,
                            paper: widget.paper,
                            ink: widget.ink,
                          ),
                        ),
                        Positioned(
                          left: 0, bottom: 0,
                          child: _PageCornerFold(
                            key: const ValueKey('paper-corner-previous'),
                            visible: !reduced && _hoverEdge == -1 &&
                                canGoBack && _dragPreview.value == 0,
                            forward: false,
                            paper: widget.paper,
                            ink: widget.ink,
                          ),
                        ),
                      ],
                    ]),
                  ),
                  ),
                ),
              ));
            }),
          ),
      ),
    ));
  }
}

/// Finger-coupled page-edge feedback. The real cursor only changes on release.
/// AnimatedBuilder.child avoids remeasuring the paragraph tree on drag frames.
class _GestureLeafPreview extends StatelessWidget {
  const _GestureLeafPreview({
    required this.animation,
    required this.direction,
    required this.reduced,
    required this.paper,
    required this.ink,
    required this.child,
  });

  final Animation<double> animation;
  final int Function() direction;
  final bool reduced;
  final Color paper, ink;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final p = reduced ? 0.0 : animation.value;
      if (p < .001) return child!;
      final forward = direction() > 0;
      final fold = Curves.easeOutCubic.transform(p);
      final matrix = Matrix4.identity()
        ..setEntry(3, 2, .00085)
        ..rotateY((forward ? 1 : -1) * fold * .11);
      return Stack(fit: StackFit.expand, children: [
        Transform.translate(
          offset: Offset((forward ? -1 : 1) * p * 6, -p * 1.5),
          child: Transform(
            alignment: forward ? Alignment.centerLeft : Alignment.centerRight,
            transform: matrix,
            child: child,
          ),
        ),
        IgnorePointer(child: DecoratedBox(
          key: const ValueKey('reader-live-drag-shade'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: forward ? Alignment.centerRight : Alignment.centerLeft,
              end: forward ? Alignment.centerLeft : Alignment.centerRight,
              stops: const [0, .08, .4, 1],
              colors: [
                ink.withValues(alpha: .18 * p),
                ink.withValues(alpha: .07 * p),
                paper.withValues(alpha: .02 * p),
                Colors.transparent,
              ],
            ),
          ),
        )),
        Positioned(
          right: forward ? 0 : null,
          left: forward ? null : 0,
          top: 0, bottom: 0, width: 3,
          child: IgnorePointer(child: ColoredBox(
            key: const ValueKey('reader-live-drag-edge'),
            color: paper.withValues(alpha: .45 * p),
          )),
        ),
      ]);
    },
  );
}

/// A quiet desktop-only fold at the paper corner. Purely decorative: dragging
/// the actual paper edge remains the action, and this paints no text overlay.
class _PageCornerFold extends StatelessWidget {
  const _PageCornerFold({
    super.key,
    required this.visible,
    required this.forward,
    required this.paper,
    required this.ink,
  });

  final bool visible;
  final bool forward;
  final Color paper, ink;

  @override
  Widget build(BuildContext context) {
    final duration = HyesMotion.reduced(context)
        ? Duration.zero : const Duration(milliseconds: 180);
    return IgnorePointer(child: AnimatedOpacity(
      key: const ValueKey('paper-corner-fold-opacity'),
      opacity: visible ? 1 : 0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: visible ? 1 : .74,
        alignment: forward ? Alignment.bottomRight : Alignment.bottomLeft,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: SizedBox.square(
          dimension: 48,
          child: CustomPaint(
            painter: _CornerFoldPainter(
              forward: forward, paper: paper, ink: ink),
          ),
        ),
      ),
    ));
  }
}

class _CornerFoldPainter extends CustomPainter {
  const _CornerFoldPainter({
    required this.forward, required this.paper, required this.ink,
  });

  final bool forward;
  final Color paper, ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (!forward) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width, h = size.height;
    final leaf = Path()
      ..moveTo(w, h - 41)
      ..quadraticBezierTo(w - 5, h - 11, w - 41, h)
      ..lineTo(w, h)
      ..close();
    canvas.drawShadow(leaf, ink.withValues(alpha: .32), 3, true);
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color.lerp(paper, Colors.white, .7)!,
          Color.lerp(paper, ink, .07)!,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(leaf, fill);
    final crease = Path()
      ..moveTo(w, h - 41)
      ..quadraticBezierTo(w - 5, h - 11, w - 41, h);
    canvas.drawPath(crease, Paint()
      ..color = ink.withValues(alpha: .27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8);
  }

  @override
  bool shouldRepaint(covariant _CornerFoldPainter oldDelegate) =>
      forward != oldDelegate.forward ||
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}
