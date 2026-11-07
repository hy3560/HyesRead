import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One laid-out EPUB chapter viewed through successive paper windows.
///
/// Unlike a pair of scroll views this owns only one chapter widget tree.
/// Facing leaves paint adjacent, non-overlapping ranges of that tree. A click
/// on either page is translated back to the original chapter coordinates.
class EpubSpreadViewport extends SingleChildRenderObjectWidget {
  const EpubSpreadViewport({
    super.key,
    required this.pair,
    required this.starts,
    required this.onMeasured,
    this.gutter = 32,
    this.rtl = false,
    super.child,
  });

  final int pair;
  final List<double> starts;
  final double gutter;
  final bool rtl;
  final void Function(double height, double pageHeight) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEpubSpreadViewport(
        pair: pair,
        starts: starts,
        gutter: gutter,
        rtl: rtl,
        onMeasured: onMeasured,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderEpubSpreadViewport renderObject) {
    renderObject
      ..pair = pair
      ..starts = starts
      ..gutter = gutter
      ..rtl = rtl
      ..onMeasured = onMeasured;
  }
}

class RenderEpubSpreadViewport extends RenderProxyBox {
  static const double pageTop = 30;
  static const double pageBottom = 35;
  RenderEpubSpreadViewport({
    required int pair,
    required List<double> starts,
    required double gutter,
    required bool rtl,
    required void Function(double, double) onMeasured,
  })  : _pair = pair,
        _starts = starts,
        _gutter = gutter,
        _rtl = rtl,
        _onMeasured = onMeasured;

  int _pair;
  List<double> _starts;
  double _gutter;
  bool _rtl;
  void Function(double, double) _onMeasured;
  double _lastHeight = -1, _lastPageHeight = -1;

  set pair(int value) {
    if (_pair != value) {
      _pair = value;
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  set starts(List<double> value) {
    if (!identical(_starts, value)) {
      _starts = value;
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  set gutter(double value) {
    if (_gutter != value) {
      _gutter = value;
      markNeedsLayout();
    }
  }

  set rtl(bool value) {
    if (_rtl != value) {
      _rtl = value;
      markNeedsPaint();
    }
  }

  set onMeasured(void Function(double, double) callback) =>
      _onMeasured = callback;

  double get _leafWidth => (size.width - _gutter) / 2;
  double? _startForLeaf(int index) => index < 0 || index >= _starts.length
      ? null : _starts[index];

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
    final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 700.0;
    size = constraints.constrain(Size(width, height));
    child?.layout(BoxConstraints(
      minWidth: _leafWidth,
      maxWidth: _leafWidth,
      minHeight: 0,
      maxHeight: double.infinity,
    ), parentUsesSize: true);
    final contentHeight = child?.size.height ?? 0.0;
    final textHeight = (size.height - pageTop - pageBottom)
        .clamp(120.0, double.infinity);
    if ((contentHeight - _lastHeight).abs() > .5 ||
        (textHeight - _lastPageHeight).abs() > .5) {
      _lastHeight = contentHeight;
      _lastPageHeight = textHeight;
      // The parent can inspect all block RenderBoxes only after layout.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) _onMeasured(contentHeight, textHeight);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    for (var pane = 0; pane < 2; pane++) {
      final first = _startForLeaf(_pair * 2 + (_rtl ? 1 - pane : pane));
      if (first == null) continue;
      final x = pane == 0 ? 0.0 : _leafWidth + _gutter;
      context.pushClipRect(
        needsCompositing,
        offset,
        Rect.fromLTWH(x, pageTop,
            _leafWidth, size.height - pageTop - pageBottom),
        (clipContext, clipOffset) => clipContext.paintChild(
          child!,
          clipOffset + Offset(x, pageTop - first),
        ),
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;
    if (position.dy < pageTop || position.dy > size.height - pageBottom) {
      return false;
    }
    final pane = position.dx < _leafWidth ? 0
        : position.dx >= _leafWidth + _gutter && position.dx < size.width
            ? 1 : -1;
    if (pane < 0) return false;
    final first = _startForLeaf(_pair * 2 + (_rtl ? 1 - pane : pane));
    if (first == null) return false;
    final origin = pane == 0 ? 0.0 : _leafWidth + _gutter;
    return child!.hitTest(result,
      position: Offset(position.dx - origin, position.dy - pageTop + first));
  }
}
