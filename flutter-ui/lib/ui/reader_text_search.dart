import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// An exact UTF-16 offset in the reader's already-loaded stable text blocks.
/// Merely searching never changes a saved position.
class ReaderTextHit {
  const ReaderTextHit(this.paragraph, this.offset, this.preview);

  final int paragraph;
  final int offset;
  final String preview;
}

List<ReaderTextHit> searchReaderText(
  List<String> paragraphs,
  String rawQuery, {
  int maximum = 30,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.length < 2 || maximum <= 0) return const [];
  final result = <ReaderTextHit>[];
  for (var i = 0; i < paragraphs.length; i++) {
    final source = paragraphs[i];
    final normalized = source.toLowerCase();
    var at = normalized.indexOf(query);
    var foundInParagraph = 0;
    while (at >= 0 && foundInParagraph < 3) {
      final start = (at - 19).clamp(0, source.length);
      final end = (at + query.length + 53).clamp(0, source.length);
      result.add(ReaderTextHit(i, at,
        source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ')));
      if (result.length >= maximum) return result;
      foundInParagraph++;
      at = normalized.indexOf(query, at + query.length);
    }
  }
  return result;
}

/// A bounded, context-aware TXT/Markdown search. No file gets rewritten.
class ReaderTextSearchDialog extends StatefulWidget {
  const ReaderTextSearchDialog({
    super.key,
    required this.paragraphs,
    required this.english,
  });

  final List<String> paragraphs;
  final bool english;

  @override
  State<ReaderTextSearchDialog> createState() => _ReaderTextSearchDialogState();
}

class _ReaderTextSearchDialogState extends State<ReaderTextSearchDialog> {
  final _text = TextEditingController();
  final _list = ScrollController();
  List<ReaderTextHit> _hits = const [];
  Timer? _debounce;
  int _selected = 0;
  bool _searching = false;

  void _changed(String value) {
    _debounce?.cancel();
    setState(() {
      _hits = const [];
      _selected = 0;
      _searching = value.trim().length >= 2;
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 130), () {
      if (!mounted || _text.text != value) return;
      setState(() {
        _hits = searchReaderText(widget.paragraphs, value);
        _searching = false;
      });
    });
  }

  void _move(int direction) {
    if (_hits.isEmpty) return;
    setState(() {
      _selected = (_selected + direction + _hits.length) % _hits.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_list.hasClients) return;
      final desired = (_selected * 80.0 - 120)
          .clamp(0.0, _list.position.maxScrollExtent);
      _list.animateTo(desired,
        duration: HyesMotion.duration(
          context, const Duration(milliseconds: 190)),
        curve: Curves.easeOutCubic);
    });
  }

  void _choose() {
    // Enter can arrive before the 130ms debounce; it should still jump.
    if (_searching) {
      _debounce?.cancel();
      _hits = searchReaderText(widget.paragraphs, _text.text);
      _searching = false;
    }
    if (_hits.isEmpty) return;
    Navigator.of(context).pop(_hits[_selected]);
  }

  Widget _highlightedPreview(String preview, Color ink) {
    final needle = _text.text.trim();
    final at = needle.isEmpty ? -1
        : preview.toLowerCase().indexOf(needle.toLowerCase());
    final base = TextStyle(
      fontFamily: HyesTokens.serifFamily,
      fontSize: 15, color: ink, height: 1.5);
    if (at < 0) {
      return Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: base);
    }
    return Text.rich(TextSpan(children: [
      TextSpan(text: preview.substring(0, at)),
      TextSpan(text: preview.substring(at, at + needle.length),
        style: const TextStyle(
          color: Color(0xFFC64F37), fontWeight: FontWeight.w700)),
      TextSpan(text: preview.substring(at + needle.length)),
    ]), maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _list.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF24211D)
        : const Color(0xFFFCF8F0);
    final ink = dark ? const Color(0xFFF0E9DC)
        : const Color(0xFF273A30);
    const accent = Color(0xFFC64F37);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _move(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _move(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        key: const ValueKey('reader-search-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        backgroundColor: surface,
        elevation: 22,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ink.withValues(alpha: .13))),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 570),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 9, 10, 8),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 22, color: accent),
                const SizedBox(width: 13),
                Expanded(child: TextField(
                  key: const ValueKey('reader-search-input'),
                  controller: _text,
                  autofocus: true,
                  onChanged: _changed,
                  onSubmitted: (_) => _choose(),
                  style: TextStyle(color: ink, fontSize: 17),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: widget.english
                        ? 'Search within this book…' : '搜索这本书的正文…',
                    hintStyle: TextStyle(
                        color: ink.withValues(alpha: .50)),
                  ),
                )),
                IconButton(
                  tooltip: widget.english ? 'Close' : '关闭',
                  icon: Icon(Icons.close_rounded, color: ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            Divider(height: 1, color: ink.withValues(alpha: .12)),
            Flexible(child: _hits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(_searching
                      ? widget.english ? 'Searching passages…'
                          : '正在检索正文…'
                      : _text.text.trim().length < 2
                      ? widget.english
                          ? 'Type at least two characters to find passages'
                          : '输入至少两个字符查找正文'
                      : widget.english ? 'No matching passages'
                          : '没有找到匹配的正文',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ink.withValues(alpha: .64))),
                )
              : ListView.builder(
                  key: const ValueKey('reader-search-results'),
                  controller: _list,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      vertical: 7, horizontal: 8),
                  itemCount: _hits.length,
                  itemBuilder: (context, i) {
                    final hit = _hits[i];
                    final active = i == _selected;
                    return MouseRegion(
                      onEnter: (_) {
                        if (_selected != i) {
                          setState(() => _selected = i);
                        }
                      },
                      child: AnimatedContainer(
                        key: ValueKey('reader-search-hit-$i'),
                        duration: HyesMotion.duration(context,
                            const Duration(milliseconds: 180)),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          color: active
                              ? accent.withValues(alpha: .11)
                              : Colors.transparent,
                          border: Border(left: BorderSide(
                            color: active ? accent : Colors.transparent,
                            width: 3)),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            dense: true,
                            title: _highlightedPreview(hit.preview, ink),
                            subtitle: Text(widget.english
                                ? 'Paragraph ${hit.paragraph + 1}'
                                : '第 ${hit.paragraph + 1} 段',
                              style: TextStyle(
                                color: ink.withValues(alpha: .58),
                                fontSize: 12)),
                            onTap: () => Navigator.of(context).pop(hit),
                          ),
                        ),
                      ),
                    );
                  },
                )),
            Divider(height: 1, color: ink.withValues(alpha: .12)),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              child: Row(children: [
                Icon(Icons.keyboard_rounded, color: ink.withValues(alpha: .55),
                  size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.english
                    ? '↑↓ Select  ·  Enter Jump  ·  Esc Close'
                    : '↑↓ 选择  ·  回车跳转  ·  Esc 关闭',
                  style: TextStyle(
                    color: ink.withValues(alpha: .62), fontSize: 12))),
                Text('${_hits.length}',
                  style: TextStyle(
                    color: ink.withValues(alpha: .62), fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
