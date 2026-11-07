import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../content/chapter_parser.dart';
import '../content/content_model.dart';
import '../parser/epub_book.dart';
import '../parser/epub_path.dart';
import '../render/block_view.dart';
import 'epub_location.dart';
import 'reader_controller.dart';
import 'reader_settings.dart';

/// How chapters are laid out.
enum EpubReaderMode {
  /// One continuous vertical scroll through the whole book.
  scroll,

  /// One chapter per page, swiped horizontally in the book's reading
  /// direction (right-to-left books advance with a right swipe). Each page
  /// scrolls vertically.
  paginated,

  /// Two consecutive paper viewports of one chapter. Turning advances
  /// a facing pair, rather than the entire spine chapter.
  spread,
}

/// Shows an [EpubBook] with native Flutter widgets (no WebView).
///
/// The reading direction comes from the spine `page-progression-direction`
/// (or the book language when it is not declared) and each block's `dir`.
class EpubReaderView extends StatefulWidget {
  /// Creates a reader.
  const EpubReaderView({
    super.key,
    required this.book,
    this.controller,
    this.mode = EpubReaderMode.scroll,
    this.settings = const EpubReaderSettings(),
    this.initialLocation,
    this.onLocationChanged,
    this.onExternalLink,
  });

  /// The book to show.
  final EpubBook book;

  /// Controls navigation and exposes the location. One is created
  /// internally when null.
  final EpubReaderController? controller;

  /// Scroll or paginated layout.
  final EpubReaderMode mode;

  /// Typography and colours.
  final EpubReaderSettings settings;

  /// Where to open the book; defaults to the start.
  final EpubLocation? initialLocation;

  /// Called when the reading position changes (after scrolling settles,
  /// after a page swipe and after jumps).
  final ValueChanged<EpubLocation>? onLocationChanged;

  /// Called with the URL of a tapped link that points outside the book.
  final ValueChanged<String>? onExternalLink;

  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _Parsed {
  _Parsed(this.chapter, this.error);
  final EpubChapter? chapter;
  final Object? error;
}

class _EpubReaderViewState extends State<EpubReaderView>
    with SingleTickerProviderStateMixin
    implements EpubReaderNavigator {
  static const _chapterCacheSize = 8;
  static const _imageCacheSize = 24;

  late EpubReaderController _controller;
  EpubReaderController? _ownController;

  final LinkedHashMap<int, _Parsed> _parsed = LinkedHashMap();
  final LinkedHashMap<String, Uint8List?> _images = LinkedHashMap();
  final Map<int, _ChapterBodyState> _chapters = {};

  int _anchor = 0;
  ScrollController _scroll = ScrollController();
  PageController? _pages;
  int _jumpToken = 0;
  bool _jumping = false;
  EpubLocation? _lastReported;
  int _spreadPair = 0;
  List<double> _spreadStarts = const [0.0];
  double _spreadPageHeight = 0;
  double _spreadPageWidth = 0;
  double _spreadContentHeight = 0;
  int _spreadMeasuredSpine = -1;
  final ScrollController _spreadLeftScroll =
      ScrollController(keepScrollOffset: false);
  final ScrollController _spreadRightScroll =
      ScrollController(keepScrollOffset: false);
  late final AnimationController _paperTurn;
  final ValueNotifier<Offset?> _paperHover = ValueNotifier(null);
  double _paperDragDistance = 0;
  int _paperTurnDirection = 1;
  bool _turning = false;
  int? _spreadPointer;
  Offset? _spreadPointerStart;
  Duration? _spreadPointerStartTime;

  @override
  int get chapterCount => widget.book.spine.items.length;

  @override
  int? get facingPairIndex =>
      widget.mode == EpubReaderMode.spread ? _spreadPair : null;

  @override
  int? get facingPairCount => widget.mode == EpubReaderMode.spread
      ? (_spreadStarts.length + 1) ~/ 2 : null;

  @override
  bool canTurnScreen(int direction) => widget.mode == EpubReaderMode.spread
      && (direction > 0
          ? (_spreadPair + 1) * 2 < _spreadStarts.length ||
              _anchor + 1 < chapterCount
          : direction < 0 && (_spreadPair > 0 || _anchor > 0));

  TextDirection get _bookDirection =>
      widget.book.isRtl ? TextDirection.rtl : TextDirection.ltr;

  @override
  void initState() {
    super.initState();
    _paperTurn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260));
    _attach();
    final initial = _clamp(widget.initialLocation ?? EpubLocation.start);
    _anchor = initial.spineIndex;
    _pages = PageController(initialPage: initial.spineIndex);
    _controller.updateLocation(initial);
    _afterFirstFrame(initial);
  }

  void _attach() {
    if (widget.controller == null) {
      _ownController ??= EpubReaderController();
      _controller = _ownController!;
    } else {
      _controller = widget.controller!;
    }
    _controller.attach(this);
  }

  void _afterFirstFrame(EpubLocation location) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) jumpTo(location);
    });
  }

  @override
  void didUpdateWidget(EpubReaderView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.detach(this);
      _attach();
    }
    if (old.book != widget.book) {
      _parsed.clear();
      _images.clear();
      _lastReported = null;
      final start = _clamp(widget.initialLocation ?? EpubLocation.start);
      _resetLayout(start);
      _afterFirstFrame(start);
      return;
    }
    if (old.mode != widget.mode) {
      final here = _controller.location;
      _resetLayout(here);
      _afterFirstFrame(here);
    } else if (widget.settings.affectsLayout(old.settings)) {
      _afterFirstFrame(_controller.location);
    }
  }

  void _resetLayout(EpubLocation at) {
    _anchor = at.spineIndex;
    _spreadPair = 0;
    _spreadStarts = const [0.0];
    _spreadPageHeight = 0;
    _spreadPageWidth = 0;
    _spreadContentHeight = 0;
    _spreadMeasuredSpine = -1;
    _pages?.dispose();
    _pages = PageController(initialPage: at.spineIndex);
    _scroll.dispose();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _paperTurn.dispose();
    _paperHover.dispose();
    _spreadLeftScroll.dispose();
    _spreadRightScroll.dispose();
    _controller.detach(this);
    _ownController?.dispose();
    _pages?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  EpubLocation _clamp(EpubLocation l) {
    if (chapterCount == 0) return EpubLocation.start;
    final spine = l.spineIndex.clamp(0, chapterCount - 1);
    return spine == l.spineIndex ? l : EpubLocation(spineIndex: spine);
  }

  // Content ------------------------------------------------------------------

  _Parsed _chapter(int spine) {
    final hit = _parsed.remove(spine);
    if (hit != null) {
      _parsed[spine] = hit;
      return hit;
    }
    _Parsed parsed;
    try {
      parsed = _Parsed(EpubChapter.fromBook(widget.book, spine), null);
    } on Object catch (e) {
      parsed = _Parsed(null, e);
    }
    _parsed[spine] = parsed;
    while (_parsed.length > _chapterCacheSize) {
      _parsed.remove(_parsed.keys.first);
    }
    return parsed;
  }

  Uint8List? _loadImage(String src) {
    if (_images.containsKey(src)) {
      final bytes = _images.remove(src);
      _images[src] = bytes;
      return bytes;
    }
    Uint8List? bytes;
    try {
      bytes = widget.book.readBytes(src);
    } on Exception {
      bytes = null;
    }
    _images[src] = bytes;
    while (_images.length > _imageCacheSize) {
      _images.remove(_images.keys.first);
    }
    return bytes;
  }

  void _onLink(String href) {
    if (EpubPath.isExternal(href)) {
      widget.onExternalLink?.call(href);
    } else {
      jumpToHref(href);
    }
  }

  // Navigation ---------------------------------------------------------------

  Future<void> _nextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
    SchedulerBinding.instance.ensureVisualUpdate();
    return completer.future;
  }

  @override
  Future<bool> jumpToHref(String href) async {
    final spine = widget.book.spineIndexOfHref(href);
    if (spine < 0) return false;
    final fragment = EpubPath.fragment(href);
    final element = fragment == null
        ? 0
        : (_chapter(spine).chapter?.anchors[fragment] ?? 0);
    await jumpTo(EpubLocation(spineIndex: spine, elementIndex: element));
    return true;
  }

  @override
  Future<void> jumpTo(EpubLocation location) async {
    if (!mounted || chapterCount == 0) return;
    final target = _clamp(location);
    final token = ++_jumpToken;
    _jumping = true;
    try {
      if (widget.mode == EpubReaderMode.spread) {
        if (_anchor != target.spineIndex) {
          setState(() {
            _anchor = target.spineIndex;
            _spreadPair = 0;
            _spreadStarts = const [0.0];
            _spreadPageHeight = 0;
            _spreadPageWidth = 0;
            _spreadContentHeight = 0;
            _spreadMeasuredSpine = -1;
          });
        }
        await _nextFrame();
        if (!mounted || token != _jumpToken) return;
        await _nextFrame();
        if (!mounted || token != _jumpToken) return;
        final leaf = _spreadLeafAt(_spreadBlockOffset(target));
        if (leaf ~/ 2 != _spreadPair) {
          setState(() => _spreadPair = leaf ~/ 2);
        }
      } else if (widget.mode == EpubReaderMode.paginated) {
        final pages = _pages!;
        if (pages.hasClients &&
            (pages.page?.round() ?? -1) != target.spineIndex) {
          pages.jumpToPage(target.spineIndex);
        }
        await _nextFrame();
        if (!mounted || token != _jumpToken) return;
        _reveal(target);
      } else {
        var revealed =
            _chapters.containsKey(target.spineIndex) && _reveal(target);
        if (revealed) {
          await _nextFrame();
          if (!mounted || token != _jumpToken) return;
          // Clamped by the end of the scroll range: re-anchor instead.
          revealed = _locate()?.spineIndex == target.spineIndex;
        }
        if (!revealed) {
          setState(() => _anchor = target.spineIndex);
          await _nextFrame();
          if (!mounted || token != _jumpToken) return;
          if (_scroll.hasClients) _scroll.jumpTo(0);
          await _nextFrame();
          if (!mounted || token != _jumpToken) return;
          _reveal(target);
        }
      }
      await _nextFrame();
      if (!mounted || token != _jumpToken) return;
    } finally {
      if (token == _jumpToken) _jumping = false;
    }
    _report(widget.mode == EpubReaderMode.spread
        ? _spreadLocation() : _locate() ?? target);
  }

  double _spreadBlockOffset(EpubLocation location) {
    final chapter = _chapters[location.spineIndex];
    if (chapter == null || chapter.keys.isEmpty) return 0;
    final box = chapter.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    final index = location.elementIndex.clamp(0, chapter.keys.length - 1);
    final target = chapter.keys[index].currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return 0;
    final y = target.localToGlobal(Offset.zero, ancestor: box).dy;
    return y + target.size.height * location.fraction.clamp(0.0, 1.0);
  }

  int _spreadLeafAt(double offset) {
    for (var i = _spreadStarts.length - 1; i >= 0; i--) {
      if (offset >= _spreadStarts[i] - .5) return i;
    }
    return 0;
  }

  EpubLocation _spreadLocation() {
    final chapter = _chapters[_anchor];
    if (chapter == null || chapter.keys.isEmpty) {
      return EpubLocation(spineIndex: _anchor);
    }
    final offset = _spreadStarts[(_spreadPair * 2)
        .clamp(0, _spreadStarts.length - 1)];
    final box = chapter.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return EpubLocation(spineIndex: _anchor);
    }
    var index = 0;
    var top = 0.0, height = 1.0;
    for (var i = 0; i < chapter.keys.length; i++) {
      final current = chapter.keys[i].currentContext?.findRenderObject();
      if (current is! RenderBox || !current.hasSize) continue;
      final y = current.localToGlobal(Offset.zero, ancestor: box).dy;
      if (y <= offset + .5) {
        index = i;
        top = y;
        height = current.size.height;
      } else {
        break;
      }
    }
    final fraction = ((offset - top) / height.clamp(1.0, double.infinity))
        .clamp(0.0, 1.0);
    return EpubLocation(
      spineIndex: _anchor,
      elementIndex: index,
      fraction: double.parse(fraction.toStringAsFixed(4)));
  }

  @override
  Future<void> turnScreen(int direction) async {
    if (!mounted || chapterCount == 0 || direction == 0) return;
    if (widget.mode != EpubReaderMode.spread) {
      await jumpTo(EpubLocation(
        spineIndex: (_controller.location.spineIndex + direction)
            .clamp(0, chapterCount - 1)));
      return;
    }
    if (_turning || !canTurnScreen(direction)) return;
    _turning = true;
    _paperTurnDirection = direction > 0 ? 1 : -1;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduced) {
      try {
        await _paperTurn.animateTo(1,
          duration: const Duration(milliseconds: 145),
          curve: Curves.easeOutCubic);
      } on TickerCanceled {
        _turning = false;
        return;
      }
    }
    if (!mounted) return;
    final next = _spreadPair + (direction > 0 ? 1 : -1);
    if (next >= 0 && next * 2 < _spreadStarts.length) {
      setState(() => _spreadPair = next);
      _report(_spreadLocation());
    } else if (direction > 0 && _anchor + 1 < chapterCount) {
      await jumpTo(EpubLocation(spineIndex: _anchor + 1));
    } else if (direction < 0 && _anchor > 0) {
      await jumpTo(EpubLocation(spineIndex: _anchor - 1));
      if (!mounted) return;
      setState(() => _spreadPair = (_spreadStarts.length - 1) ~/ 2);
      _report(_spreadLocation());
    }
    if (mounted) {
      if (reduced) {
        _paperTurn.value = 0;
      } else {
        try {
          await _paperTurn.animateBack(0,
            duration: const Duration(milliseconds: 215),
            curve: Curves.easeOutCubic);
        } on TickerCanceled {
          // Disposing the reader while leaving is a normal navigation action.
        }
      }
    }
    _paperDragDistance = 0;
    _turning = false;
  }

  void _onSpreadPointerDown(PointerDownEvent event) {
    if (_turning || _spreadPointer != null) return;
    final render = context.findRenderObject();
    final width = render is RenderBox && render.hasSize
        ? render.size.width : 0.0;
    // Edge-only dragging leaves the central text selection and link gestures
    // untouched. Both touch and mouse can turn a page from the paper edge.
    if (width <= 0 || (event.localPosition.dx > 58 &&
        event.localPosition.dx < width - 58)) return;
    _spreadPointer = event.pointer;
    _spreadPointerStart = event.localPosition;
    _spreadPointerStartTime = event.timeStamp;
    _paperDragDistance = 0;
  }

  void _onSpreadPointerMove(PointerMoveEvent event) {
    if (_turning || event.pointer != _spreadPointer) return;
    final start = _spreadPointerStart;
    if (start == null) return;
    _paperDragDistance = event.localPosition.dx - start.dx;
    if (_paperDragDistance.abs() < 8) return;
    _paperTurnDirection =
        (_paperDragDistance < 0) != widget.book.isRtl ? 1 : -1;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduced) {
      _paperTurn.value = (_paperDragDistance.abs() / 190).clamp(0.0, .85);
    }
  }

  void _finishSpreadPointer(PointerEvent event, {bool cancelled = false}) {
    if (event.pointer != _spreadPointer) return;
    final start = _spreadPointerStart;
    final distance = _paperDragDistance;
    final elapsed = (event.timeStamp -
        (_spreadPointerStartTime ?? event.timeStamp)).inMicroseconds /
        Duration.microsecondsPerSecond;
    final velocity = elapsed > 0 ? distance / elapsed : 0.0;
    final direction = (distance.abs() > 12 ? distance : velocity) < 0
        != widget.book.isRtl ? 1 : -1;
    final accept = !cancelled &&
        (distance.abs() >= 58 || velocity.abs() >= 380);
    final render = context.findRenderObject();
    final bounds = render is RenderBox && render.hasSize
        ? render.size : Size.zero;
    // Lower paper corners can be tapped; normal book text stays selectable.
    final tappedCorner = !cancelled && start != null &&
        start.dy > bounds.height - 94 &&
        (event.localPosition - start).distance < 12 &&
        elapsed <= .55 && bounds.width > 0;
    final cornerDirection = start == null ? 0 :
        (start.dx > bounds.width / 2) != widget.book.isRtl ? 1 : -1;
    _spreadPointer = null;
    _spreadPointerStart = null;
    _spreadPointerStartTime = null;
    _paperDragDistance = 0;
    if (accept && canTurnScreen(direction)) {
      unawaited(turnScreen(direction));
    } else if (tappedCorner && canTurnScreen(cornerDirection)) {
      unawaited(turnScreen(cornerDirection));
    } else {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _paperTurn.value = 0;
      } else {
        unawaited(_paperTurn.animateBack(0,
            duration: const Duration(milliseconds: 185),
            curve: Curves.easeOutCubic));
      }
    }
  }

  void _onSpreadPointerUp(PointerUpEvent event) =>
      _finishSpreadPointer(event);

  void _onSpreadPointerCancel(PointerCancelEvent event) =>
      _finishSpreadPointer(event, cancelled: true);

  /// Derive physical leaf boundaries from measured native block positions.
  /// Illustrations that fit the page are never cut at its bottom edge.
  void _spreadMeasured(double height, double pageHeight, double pageWidth) {
    if (!mounted || pageHeight <= 0) return;
    if ((height - _spreadContentHeight).abs() < .5 &&
        (pageHeight - _spreadPageHeight).abs() < .5 &&
        (pageWidth - _spreadPageWidth).abs() < .5 &&
        _spreadMeasuredSpine == _anchor) return;
    _spreadContentHeight = height;
    _spreadPageHeight = pageHeight;
    _spreadPageWidth = pageWidth;
    _spreadMeasuredSpine = _anchor;
    final chapter = _chapters[_anchor];
    final blocks = _chapter(_anchor).chapter?.blocks;
    final chapterBox = chapter?.context.findRenderObject();
    final measurements = <(double, double, bool)>[];
    if (chapter != null && chapterBox is RenderBox &&
        chapterBox.hasSize && blocks != null) {
      for (var i = 0; i < chapter.keys.length && i < blocks.length; i++) {
        final box = chapter.keys[i].currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero, ancestor: chapterBox).dy;
        measurements.add((y, y + box.size.height,
            blocks[i] is EpubImageBlock));
      }
    }
    final next = <double>[0];
    var start = 0.0;
    final lineStep = (widget.settings.fontSize * widget.settings.lineHeight)
        .clamp(14.0, 80.0);
    for (var i = 0; i < 4000 && start + pageHeight < height - .5; i++) {
      final limit = start + pageHeight;
      var cut = limit;
      for (final (top, bottom, image) in measurements) {
        if (top >= limit || bottom <= limit) continue;
        if (image && bottom - top <= pageHeight * .95 &&
            top >= start + pageHeight * .35) {
          cut = top;
        } else if (!image) {
          final lines = ((limit - top) / lineStep).floor();
          final aligned = top + lines * lineStep;
          if (aligned > start + pageHeight * .45 &&
              aligned <= limit) cut = aligned;
        }
        break;
      }
      if (cut <= start + 1) cut = limit;
      next.add(cut);
      start = cut;
    }
    setState(() {
      _spreadStarts = next;
      _spreadPair = _spreadPair.clamp(0, (next.length - 1) ~/ 2);
    });
  }

  int _spreadLeafForPane({required bool right}) {
    final first = _spreadPair * 2;
    if (widget.book.isRtl) return first + (right ? 0 : 1);
    return first + (right ? 1 : 0);
  }

  void _syncSpreadScrolls() {
    if (!mounted || widget.mode != EpubReaderMode.spread) return;
    void align(ScrollController controller, int leaf) {
      if (!controller.hasClients || leaf >= _spreadStarts.length) return;
      final position = controller.position;
      if (!position.hasContentDimensions) return;
      final target = _spreadStarts[leaf]
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((position.pixels - target).abs() > .5) controller.jumpTo(target);
    }
    align(_spreadLeftScroll, _spreadLeafForPane(right: false));
    align(_spreadRightScroll, _spreadLeafForPane(right: true));
  }

  Widget _spreadLeaf(EpubRenderScope scope, ScrollController controller,
      double pageHeight, {required bool right, required int leaf}) {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 35),
      child: SizedBox(height: pageHeight, child: ClipRect(
        child: SingleChildScrollView(
          key: ValueKey(right ? 'epub-right-leaf' : 'epub-left-leaf'),
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          child: Column(children: [
            _chapterBody(_anchor, scope, facingRight: right,
                registerChapter: leaf.isEven),
            // The last leaf still needs to reach its exact top, rather than
            // being clamped back into the previous leaf by scroll extents.
            SizedBox(height: pageHeight),
          ]),
        ),
      )),
    );
  }

  /// Scrolls the block of [location] to the top of its viewport.
  bool _reveal(EpubLocation location) {
    final chapter = _chapters[location.spineIndex];
    if (chapter == null) return false;
    final keys = chapter.keys;
    if (keys.isEmpty) return true;
    final context =
        keys[location.elementIndex.clamp(0, keys.length - 1)].currentContext;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.hasSize) return false;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) return false;
    // ensureVisible aligns the block's top edge with the viewport's top.
    Scrollable.ensureVisible(context, alignment: 0, duration: Duration.zero);
    if (location.fraction > 0) {
      final offset = position.pixels + location.fraction * box.size.height;
      position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    return true;
  }

  /// The block at the top of the visible viewport.
  EpubLocation? _locate() {
    final Iterable<_ChapterBodyState> candidates;
    if (widget.mode == EpubReaderMode.paginated) {
      final pages = _pages!;
      final page = pages.hasClients ? pages.page?.round() : null;
      final chapter = page == null ? null : _chapters[page];
      if (chapter == null) {
        return page == null ? null : EpubLocation(spineIndex: page);
      }
      candidates = [chapter];
    } else {
      candidates = (_chapters.keys.toList()..sort()).map((k) => _chapters[k]!);
    }
    EpubLocation? best;
    double? bestTop;
    EpubLocation? first;
    for (final chapter in candidates) {
      final keys = chapter.keys;
      // The chapter's own top (above its padding) counts as the start of
      // block 0, so a chapter whose top is at the viewport top wins.
      double? chapterTop;
      final chapterBox = chapter.context.findRenderObject();
      if (chapterBox is RenderBox &&
          chapterBox.attached &&
          chapterBox.hasSize) {
        chapterTop = RenderAbstractViewport.maybeOf(chapterBox)
            ?.getOffsetToReveal(chapterBox, 0)
            .offset;
      }
      for (var i = 0; i < keys.length; i++) {
        final context = keys[i].currentContext;
        final box = context?.findRenderObject();
        if (context == null ||
            box is! RenderBox ||
            !box.hasSize ||
            !box.attached) {
          continue;
        }
        final viewport = RenderAbstractViewport.maybeOf(box);
        final position = Scrollable.maybeOf(context)?.position;
        if (viewport == null || position == null || !position.hasPixels) {
          continue;
        }
        final top = viewport.getOffsetToReveal(box, 0).offset;
        final height = box.size.height;
        final start =
            i == 0 && chapterTop != null && chapterTop < top ? chapterTop : top;
        first ??= EpubLocation(spineIndex: chapter.widget.spineIndex);
        if (start <= position.pixels + 0.5 &&
            (bestTop == null || start >= bestTop)) {
          bestTop = start;
          final fraction = height <= 0
              ? 0.0
              : ((position.pixels - top) / height).clamp(0.0, 1.0);
          best = EpubLocation(
            spineIndex: chapter.widget.spineIndex,
            elementIndex: i,
            fraction: double.parse(fraction.toStringAsFixed(4)),
          );
        }
      }
    }
    return best ?? first;
  }

  void _report(EpubLocation location) {
    _controller.updateLocation(location);
    if (location != _lastReported) {
      _lastReported = location;
      widget.onLocationChanged?.call(location);
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (widget.mode == EpubReaderMode.spread) return false;
    if (n is ScrollEndNotification && !_jumping) {
      final location = _locate();
      if (location != null) _report(location);
    }
    return false;
  }

  void _register(_ChapterBodyState state) =>
      _chapters[state.widget.spineIndex] = state;

  void _unregister(_ChapterBodyState state) {
    if (identical(_chapters[state.widget.spineIndex], state)) {
      _chapters.remove(state.widget.spineIndex);
    }
  }

  // Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final scope = EpubRenderScope(
      settings: settings,
      defaultDirection: _bookDirection,
      onLink: _onLink,
      loadImage: _loadImage,
    );
    Widget body;
    if (chapterCount == 0) {
      body = const SizedBox.expand();
    } else if (widget.mode == EpubReaderMode.spread) {
      body = LayoutBuilder(builder: (context, constraints) {
        final pageHeight = (constraints.maxHeight - 65)
            .clamp(120.0, double.infinity);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.mode != EpubReaderMode.spread) return;
          final box = _chapters[_anchor]?.context.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            _spreadMeasured(box.size.height, pageHeight,
                (constraints.maxWidth - 32) / 2);
          }
          _syncSpreadScrolls();
        });
        final spreadScope = EpubRenderScope(
          settings: settings,
          defaultDirection: _bookDirection,
          onLink: _onLink,
          loadImage: _loadImage,
          maxImageHeight: constraints.maxHeight * .83,
        );
        return Stack(children: [
          Positioned.fill(child: MouseRegion(
            onHover: (event) => _paperHover.value = event.localPosition,
            onExit: (_) => _paperHover.value = null,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onSpreadPointerDown,
              onPointerMove: _onSpreadPointerMove,
              onPointerUp: _onSpreadPointerUp,
              onPointerCancel: _onSpreadPointerCancel,
              child: Row(
                key: const ValueKey('epub-facing-pages'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _spreadLeafForPane(right: false) <
                          _spreadStarts.length
                      ? _spreadLeaf(spreadScope, _spreadLeftScroll,
                          (constraints.maxHeight - 65)
                              .clamp(120.0, double.infinity),
                          right: false,
                          leaf: _spreadLeafForPane(right: false))
                      : const SizedBox.shrink()),
                  const SizedBox(width: 32),
                  Expanded(child: _spreadLeafForPane(right: true) <
                          _spreadStarts.length
                      ? _spreadLeaf(spreadScope, _spreadRightScroll,
                          (constraints.maxHeight - 65)
                              .clamp(120.0, double.infinity),
                          right: true,
                          leaf: _spreadLeafForPane(right: true))
                      : const SizedBox.shrink()),
                ],
              ),
            ),
          )),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            key: const ValueKey('epub-spread-engraving'),
            painter: _EpubSpreadEngraving(
              ink: settings.theme.textColor,
              accent: settings.headingAccent,
            ),
          ))),
          Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(
            animation: Listenable.merge([_paperTurn, _paperHover]),
            builder: (context, _) => CustomPaint(
              key: const ValueKey('epub-gesture-paper-finish'),
              painter: _EpubPaperTurnPainter(
                progress: _paperTurn.value,
                direction: _paperTurnDirection,
                hover: _paperHover.value,
                rtl: widget.book.isRtl,
                ink: settings.theme.textColor,
                paper: settings.theme.backgroundColor,
              ),
            ),
          ))),
          Positioned(top: 0, bottom: 0,
            left: (constraints.maxWidth - 32) / 2, width: 32,
            child: IgnorePointer(child: DecoratedBox(
              key: const ValueKey('epub-paper-gutter'),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [
                settings.theme.textColor.withValues(alpha: .008),
                settings.theme.textColor.withValues(alpha: .055),
                settings.theme.textColor.withValues(alpha: .1),
                settings.theme.textColor.withValues(alpha: .018),
              ], stops: const [0, .43, .5, 1])),
            )),
          ),
          Positioned(top: 7, left: 30, right: 30,
            child: IgnorePointer(child: Row(children: [
              Expanded(child: Text('HYESREAD  /  FACING PAGES',
                style: TextStyle(fontSize: 9, letterSpacing: 1.8,
                  color: settings.theme.textColor.withValues(alpha: .4)))),
              const SizedBox(width: 42),
              Expanded(child: Text(_chapter(_anchor).chapter?.title ?? '',
                textAlign: TextAlign.end, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, letterSpacing: .5,
                  color: settings.theme.textColor.withValues(alpha: .5)))),
            ])),
          ),
          Positioned(bottom: 7, left: 35, right: 35,
            child: IgnorePointer(child: Row(children: [
              Text(_spreadLeafForPane(right: false) < _spreadStarts.length
                    ? '${_spreadLeafForPane(right: false) + 1}'.padLeft(2, '0')
                    : '—',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4,
                  color: settings.theme.textColor.withValues(alpha: .5))),
              Expanded(child: Center(child: Row(
                mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 19, height: 1,
                    color: settings.headingAccent.withValues(alpha: .5)),
                  const SizedBox(width: 9),
                  Text('本章 ${_spreadStarts.length} 页 · 双页阅读',
                    style: TextStyle(fontSize: 10, letterSpacing: .7,
                      color: settings.theme.textColor.withValues(alpha: .46))),
                  const SizedBox(width: 9),
                  Container(width: 19, height: 1,
                    color: settings.headingAccent.withValues(alpha: .5)),
                ],
              ))),
              Text(_spreadLeafForPane(right: true) < _spreadStarts.length
                    ? '${_spreadLeafForPane(right: true) + 1}'.padLeft(2, '0')
                    : '—',
                style: TextStyle(fontSize: 11, letterSpacing: 1.4,
                  color: settings.theme.textColor.withValues(alpha: .5))),
            ])),
          ),
        ]);
      });
    } else if (widget.mode == EpubReaderMode.paginated) {
      body = Directionality(
        textDirection: _bookDirection,
        child: PageView.builder(
          controller: _pages,
          itemCount: chapterCount,
          itemBuilder: (context, i) => SingleChildScrollView(
            key: PageStorageKey<int>(i),
            child: _chapterBody(i, scope),
          ),
        ),
      );
    } else {
      final centerKey = ValueKey<String>('epub-center-$_anchor');
      body = CustomScrollView(
        controller: _scroll,
        center: centerKey,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) =>
                  _chapterBody(_anchor - 1 - i, scope, separator: true),
              childCount: _anchor,
            ),
          ),
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
              (context, i) => _chapterBody(_anchor + i, scope,
                  separator: _anchor + i < chapterCount - 1),
              childCount: chapterCount - _anchor,
            ),
          ),
        ],
      );
    }
    return ColoredBox(
      color: settings.theme.backgroundColor,
      child: DefaultTextStyle(
        style: scope.baseStyle.copyWith(decoration: TextDecoration.none),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: body,
        ),
      ),
    );
  }

  Widget _chapterBody(int spine, EpubRenderScope scope,
      {bool separator = false, bool facingRight = false,
      bool registerChapter = true}) {
    final parsed = _chapter(spine);
    return _ChapterBody(
      key: ValueKey<String>('epub-chapter-$spine'
          '${facingRight ? '-facing-right' : ''}'),
      spineIndex: spine,
      chapter: parsed.chapter,
      error: parsed.error,
      scope: scope,
      separator: separator,
      register: registerChapter ? _register : (_) {},
      unregister: registerChapter ? _unregister : (_) {},
    );
  }
}

class _ChapterBody extends StatefulWidget {
  const _ChapterBody({
    super.key,
    required this.spineIndex,
    required this.chapter,
    required this.error,
    required this.scope,
    required this.separator,
    required this.register,
    required this.unregister,
  });

  final int spineIndex;
  final EpubChapter? chapter;
  final Object? error;
  final EpubRenderScope scope;
  final bool separator;
  final void Function(_ChapterBodyState) register;
  final void Function(_ChapterBodyState) unregister;

  @override
  State<_ChapterBody> createState() => _ChapterBodyState();
}

class _ChapterBodyState extends State<_ChapterBody> {
  List<GlobalKey> keys = const [];

  void _makeKeys() {
    final count = widget.chapter?.blocks.length ?? 0;
    keys = List.generate(
        count, (i) => GlobalKey(debugLabel: 'epub-${widget.spineIndex}-$i'));
  }

  @override
  void initState() {
    super.initState();
    _makeKeys();
    widget.register(this);
  }

  @override
  void didUpdateWidget(_ChapterBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.chapter, widget.chapter)) _makeKeys();
    if (old.spineIndex != widget.spineIndex) {
      old.unregister(this);
      widget.register(this);
    }
  }

  @override
  void dispose() {
    widget.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final chapter = widget.chapter;
    final Widget content;
    if (chapter == null) {
      content = EpubChapterError(error: widget.error, scope: scope);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < chapter.blocks.length; i++)
            KeyedSubtree(
              key: keys[i],
              child: EpubBlockView(block: chapter.blocks[i], scope: scope),
            ),
        ],
      );
    }
    return Padding(
      padding: scope.settings.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (widget.separator)
            Padding(
              padding: EdgeInsets.symmetric(vertical: scope.settings.fontSize),
              child: Center(
                child: SizedBox(
                  width: 80,
                  height: 1,
                  child: ColoredBox(color: scope.settings.theme.secondaryColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in place of a chapter that could not be parsed.
class EpubChapterError extends StatelessWidget {
  /// Creates the placeholder.
  const EpubChapterError({super.key, required this.error, required this.scope});

  /// What went wrong.
  final Object? error;

  /// Rendering scope.
  final EpubRenderScope scope;

  @override
  Widget build(BuildContext context) => Text(
        '$error',
        style: scope.baseStyle.copyWith(
            fontSize: scope.settings.fontSize * 0.8,
            fontStyle: FontStyle.italic),
      );
}

/// Still editorial ornament, printed in the margins rather than animated over
/// the reading ink. Keeping this painter static avoids an idle GPU workload.
class _EpubSpreadEngraving extends CustomPainter {
  const _EpubSpreadEngraving({required this.ink, required this.accent});

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 240 || size.height < 200) return;
    final edge = Paint()
      ..color = ink.withValues(alpha: .072)
      ..strokeWidth = .8;
    final rule = Paint()
      ..color = accent.withValues(alpha: .34)
      ..strokeWidth = 1;
    final half = size.width / 2;
    // Open-book edge hairlines are deliberately outside the text columns.
    for (final x in [12.0, size.width - 12]) {
      canvas.drawLine(Offset(x, 25), Offset(x, size.height - 26), edge);
    }
    for (final x in [23.0, size.width - 23]) {
      final toward = x < half ? 1.0 : -1.0;
      canvas.drawLine(Offset(x, 23),
          Offset(x + toward * 38, 23), edge);
      canvas.drawLine(Offset(x, size.height - 24),
          Offset(x + toward * 38, size.height - 24), edge);
      canvas.drawCircle(Offset(x, size.height - 24), 1.5,
          Paint()..color = accent.withValues(alpha: .35));
    }
    // The short vermilion gilding anchors the optical book spine.
    canvas.drawLine(Offset(half, 19), Offset(half, 42), rule);
    canvas.drawLine(Offset(half, size.height - 42),
        Offset(half, size.height - 19), rule);
  }

  @override
  bool shouldRepaint(covariant _EpubSpreadEngraving old) =>
      old.ink != ink || old.accent != accent;
}

/// A changing fold of reflected light over still, readable paper.
class _EpubPaperTurnPainter extends CustomPainter {
  const _EpubPaperTurnPainter({
    required this.progress,
    required this.direction,
    required this.hover,
    required this.rtl,
    required this.ink,
    required this.paper,
  });

  final double progress;
  final int direction;
  final Offset? hover;
  final bool rtl;
  final Color ink, paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final p = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    if (p > .001) {
      final fromRight = (direction > 0) != rtl;
      final leafWidth = ((w - 32) / 2).clamp(0.0, w);
      final foldWidth = leafWidth * p;
      final edgeX = fromRight ? w - foldWidth : foldWidth;
      final flap = Path();
      if (fromRight) {
        flap.moveTo(w, 0);
        flap.lineTo(edgeX, 0);
        flap.cubicTo(edgeX + foldWidth * .2, h * .26,
            edgeX - foldWidth * .13, h * .72, edgeX, h);
        flap.lineTo(w, h);
      } else {
        flap.moveTo(0, 0);
        flap.lineTo(edgeX, 0);
        flap.cubicTo(edgeX - foldWidth * .2, h * .26,
            edgeX + foldWidth * .13, h * .72, edgeX, h);
        flap.lineTo(0, h);
      }
      flap.close();
      final flapRect = fromRight
          ? Rect.fromLTRB(edgeX, 0, w, h)
          : Rect.fromLTRB(0, 0, edgeX, h);
      canvas.drawShadow(flap, ink.withValues(alpha: .2 * p), 12 * p, true);
      canvas.drawPath(flap, Paint()..shader = LinearGradient(
        begin: fromRight ? Alignment.centerLeft : Alignment.centerRight,
        end: fromRight ? Alignment.centerRight : Alignment.centerLeft,
        colors: [
          paper.withValues(alpha: .96),
          Color.lerp(paper, const Color(0xFFFFFFFF), .32)!
              .withValues(alpha: .9),
          ink.withValues(alpha: .08 * p),
        ],
        stops: const [0, .78, 1],
      ).createShader(flapRect));
      final foldEdge = Path()
        ..moveTo(edgeX, 0)
        ..cubicTo(edgeX + (fromRight ? 1 : -1) * foldWidth * .2,
            h * .26,
            edgeX - (fromRight ? 1 : -1) * foldWidth * .13,
            h * .72, edgeX, h);
      canvas.drawPath(foldEdge, Paint()
        ..color = ink.withValues(alpha: .2 * p)
        ..strokeWidth = 5 * p
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * p));
      canvas.drawPath(foldEdge, Paint()
        ..color = paper.withValues(alpha: .72 * p)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke);
    }
    final at = hover;
    if (at == null || p > .05) return;
    final right = at.dx > w - 70;
    final left = at.dx < 70;
    final top = at.dy < 90;
    final bottom = at.dy > h - 90;
    if ((!right && !left) || (!top && !bottom)) return;
    final proximity = right ? (w - at.dx) : at.dx;
    final strength = ((70 - proximity) / 70).clamp(0.0, 1.0);
    if (strength <= 0) return;
    final corner = Path();
    const cornerSize = 34.0;
    if (right && bottom) {
      corner.moveTo(w, h - 28 * strength);
      corner.quadraticBezierTo(w - 7 * strength,
          h - 8 * strength, w - cornerSize * strength, h);
      corner.lineTo(w, h);
    } else if (!right && bottom) {
      corner.moveTo(0, h - 28 * strength);
      corner.quadraticBezierTo(7 * strength,
          h - 8 * strength, cornerSize * strength, h);
      corner.lineTo(0, h);
    } else if (right) {
      corner.moveTo(w, cornerSize * strength);
      corner.quadraticBezierTo(w - 7 * strength,
          8 * strength, w - cornerSize * strength, 0);
      corner.lineTo(w, 0);
    } else {
      corner.moveTo(0, cornerSize * strength);
      corner.quadraticBezierTo(7 * strength,
          8 * strength, cornerSize * strength, 0);
      corner.lineTo(0, 0);
    }
    corner.close();
    canvas.drawShadow(corner, ink.withValues(alpha: .23 * strength),
        4, true);
    canvas.drawPath(corner, Paint()..shader = LinearGradient(
      begin: top ? Alignment.topLeft : Alignment.bottomLeft,
      end: top ? Alignment.bottomRight : Alignment.topRight,
      colors: [
        Color.lerp(paper, const Color(0xFFFFFFFF), .6)!,
        paper,
      ],
    ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant _EpubPaperTurnPainter old) =>
      old.progress != progress || old.direction != direction ||
      old.hover != hover || old.rtl != rtl ||
      old.ink != ink || old.paper != paper;
}
