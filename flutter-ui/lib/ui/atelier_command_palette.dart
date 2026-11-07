import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_entry.dart';
import '../data/reading_progress.dart';
import '../data/text_blocks.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'app_language.dart';
import 'atelier_widgets.dart';

/// A confirmed position within the reader's *same* stable TXT/Markdown blocks.
/// Selecting this result explicitly moves the reading anchor before opening.
class AtelierTextSearchMatch {
  const AtelierTextSearchMatch({
    required this.book, required this.paragraphIndex,
    required this.textOffset, required this.paragraphCount,
    required this.progress,
    required this.preview, required this.isHeading,
  });
  final BookEntry book;
  final int paragraphIndex;
  final int textOffset;
  final int paragraphCount;
  final double progress;
  final String preview;
  final bool isHeading;
}

/// Uses the exact UTF-16 stable-block parser shared by ReaderPage.
/// No index data leaves the local device and the original files are untouched.
Future<List<AtelierTextSearchMatch>> findLocalTextMatches(
    Iterable<BookEntry> books, String query,
    {int maximum = 24}) async {
  final needle = query.trim().toLowerCase();
  if (needle.length < 2 || maximum <= 0) return [];
  final hits = <AtelierTextSearchMatch>[];
  for (final book in books) {
    if (!book.isText) continue;
    try {
      final file = File(book.path);
      if (!await file.exists() ||
          await file.length() > 20 * 1024 * 1024) continue;
      final original = utf8.decode(await file.readAsBytes());
      final paragraphs = splitTextIntoStableBlocks(original);
      final locations = TextReadingProgress(paragraphs);
      for (var paragraph = 0; paragraph < paragraphs.length; paragraph++) {
        final content = paragraphs[paragraph];
        final lower = content.toLowerCase();
        var at = lower.indexOf(needle);
        var perParagraph = 0;
        while (at >= 0 && hits.length < maximum && perParagraph < 3) {
          final begin = (at - 16).clamp(0, content.length);
          final end = (at + needle.length + 35).clamp(0, content.length);
          final preview = content.substring(begin, end)
              .replaceAll(RegExp(r'\s+'), ' ');
          hits.add(AtelierTextSearchMatch(
            book: book, paragraphIndex: paragraph,
            textOffset: at, paragraphCount: paragraphs.length,
            progress: locations.at(paragraph, at),
            preview: preview, isHeading:
              RegExp(r'^(?:第[^\n]{1,30}[章节卷篇回]|Chapter\s+\d+|#{1,6}\s)',
                  caseSensitive: false).hasMatch(content.trim()),
          ));
          perParagraph++;
          at = lower.indexOf(needle, at + needle.length);
        }
        if (hits.length >= maximum) return hits;
      }
    } on FileSystemException {
      // Damaged/missing local copies are handled by the normal reader.
    } on FormatException {
      // The reader itself only accepts UTF-8 for TXT; don't guess offsets.
    }
  }
  return hits;
}

/// Local command search: books, sections and verified TXT/Markdown content.
class AtelierCommandPalette extends StatefulWidget {
  const AtelierCommandPalette({
    super.key, required this.books, required this.language,
  });
  final List<BookEntry> books;
  final HyesLanguage language;

  @override
  State<AtelierCommandPalette> createState() =>
      _AtelierCommandPaletteState();
}

class _AtelierCommandPaletteState extends State<AtelierCommandPalette> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  Future<List<AtelierTextSearchMatch>>? _textSearch;
  List<AtelierTextSearchMatch> _matches = const [];
  int _selected = 0;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _textSearch = null;
      _matches = const [];
      _selected = 0;
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 190), () {
      if (!mounted || _query.text != value) return;
      setState(() {
        _textSearch = findLocalTextMatches(widget.books, value);
      });
      _textSearch!.then((matches) {
        if (!mounted || _query.text != value) return;
        setState(() => _matches = matches);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = HyesCopy(widget.language);
    final ink = AtelierColor.foreground(context);
    final accent = AtelierColor.accent(context);
    final q = _query.text.trim().toLowerCase();
    final books = widget.books.where((book) =>
      q.isEmpty || ('${book.title} ${book.format}')
          .toLowerCase().contains(q)).take(12).toList();
    final pages = <({String title, IconData icon, int tab})>[
      (title: words.tr('续读'), icon: Icons.auto_stories_outlined, tab: 0),
      (title: words.tr('书架'), icon: Icons.collections_bookmark_outlined, tab: 1),
      (title: words.tr('记录'), icon: Icons.timeline_outlined, tab: 2),
      (title: words.tr('设置'), icon: Icons.tune_rounded, tab: 3),
    ].where((entry) => q.isEmpty ||
      entry.title.toLowerCase().contains(q)).toList();

    Object? selectedResult() {
      var index = _selected;
      if (index < books.length) return books[index];
      index -= books.length;
      if (index < pages.length) return pages[index].tab;
      index -= pages.length;
      if (index < _matches.length) return _matches[index];
      return null;
    }

    final total = books.length + pages.length + _matches.length;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowDown => 1,
          LogicalKeyboardKey.arrowUp => -1,
          _ => 0,
        };
        if (delta != 0 && total > 0) {
          setState(() => _selected = (_selected + delta + total) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
      key: const ValueKey('atelier-command-dialog'),
      elevation: 0,
      backgroundColor: AtelierColor.sheet(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: ink.withValues(alpha: .10))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 615),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(17, 11, 13, 10),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 23, color: accent),
              const SizedBox(width: 13),
              Expanded(child: TextField(
                key: const ValueKey('atelier-command-input'),
                autofocus: true,
                controller: _query,
                onChanged: _onQueryChanged,
                onSubmitted: (_) async {
                  final target = selectedResult();
                  if (target != null) {
                    Navigator.pop(context, target);
                  }
                },
                style: TextStyle(color: ink, fontSize: 17),
                decoration: InputDecoration(
                  hintText: widget.language == HyesLanguage.english
                      ? 'Search books, text or commands…'
                      : '搜索书名、章节、正文或操作…',
                  hintStyle: TextStyle(color:
                    AtelierColor.secondary(context), fontSize: 16),
                  border: InputBorder.none, isDense: true),
              )),
              IconButton(
                tooltip: widget.language == HyesLanguage.english
                    ? 'Close search' : '关闭搜索',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, size: 21)),
            ]),
          ),
          Divider(height: 1, color: ink.withValues(alpha: .12)),
          ConstrainedBox(constraints:
            const BoxConstraints(maxHeight: 390),
            child: total == 0 && q.length < 2 ? Padding(
              padding: const EdgeInsets.all(30),
              child: Text(widget.language == HyesLanguage.english
                ? 'No matching books or commands'
                : '没有匹配的书籍或操作',
                style: TextStyle(color: AtelierColor.secondary(context))),
            ) : ListView(
              key: const ValueKey('atelier-command-results'),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (books.isNotEmpty) ...[
                  _section(context, words.tr('书架')),
                  for (var i = 0; i < books.length; i++)
                    _result(context,
                      icon: Icons.menu_book_outlined,
                      title: books[i].title,
                      subtitle: books[i].format.toUpperCase(),
                      index: i, selected: _selected == i,
                      onTap: () => Navigator.pop(context, books[i])),
                ],
                if (pages.isNotEmpty) ...[
                  _section(context, widget.language == HyesLanguage.english
                    ? 'Navigate' : '导航'),
                  for (var i = 0; i < pages.length; i++)
                    _result(context, icon: pages[i].icon,
                      title: pages[i].title,
                      index: books.length + i,
                      selected: _selected == books.length + i,
                      subtitle: widget.language == HyesLanguage.english
                        ? 'Open page' : '打开页面',
                      onTap: () => Navigator.pop(context, pages[i].tab)),
                ],
                if (q.length >= 2)
                  _textResults(context, books.length + pages.length),
              ],
            ),
          ),
          Divider(height: 1, color: ink.withValues(alpha: .12)),
          Padding(padding: const EdgeInsets.symmetric(
              horizontal: 19, vertical: 12),
            child: Row(children: [
              Icon(Icons.keyboard_return_rounded, size: 17,
                color: AtelierColor.secondary(context)),
              const SizedBox(width: 6),
              Text(widget.language == HyesLanguage.english
                  ? '↑↓ Select  ·  Enter Open  ·  Esc Close'
                  : '↑↓ 选择  ·  回车打开  ·  Esc 关闭',
                style: TextStyle(fontSize: 12,
                  color: AtelierColor.secondary(context))),
            ]),
          ),
        ]),
      ),
    ));
  }

  Widget _section(BuildContext context, String title) =>
      Padding(padding: const EdgeInsets.fromLTRB(22, 13, 16, 6),
        child: Text(title.toUpperCase(), style: TextStyle(
          color: AtelierColor.secondary(context),
          fontSize: 12, letterSpacing: 1.1)));

  Widget _textResults(BuildContext context, int indexOffset) =>
      FutureBuilder<List<AtelierTextSearchMatch>>(
        future: _textSearch,
        builder: (context, snapshot) {
          if (_textSearch == null ||
              snapshot.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 17),
                const SizedBox(width: 12),
                Text(widget.language == HyesLanguage.english
                  ? 'Searching local text…' : '正在检索本机正文…',
                  style: TextStyle(
                    color: AtelierColor.secondary(context))),
              ]),
            );
          }
          final hits = snapshot.data ?? const <AtelierTextSearchMatch>[];
          if (hits.isEmpty) return Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
            child: Text(widget.language == HyesLanguage.english
              ? 'No matching TXT / Markdown text'
              : 'TXT / Markdown 中没有匹配的正文',
              style: TextStyle(color: AtelierColor.secondary(context))),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _section(context, widget.language == HyesLanguage.english
                ? 'Chapters and text' : '章节与正文'),
              for (var i = 0; i < hits.length; i++)
                _result(context,
                  icon: hits[i].isHeading
                      ? Icons.segment_rounded : Icons.text_snippet_outlined,
                  title: hits[i].preview,
                  subtitle: widget.language == HyesLanguage.english
                    ? '${hits[i].book.title} · Paragraph ${hits[i].paragraphIndex + 1}'
                    : '${hits[i].book.title} · 第 ${hits[i].paragraphIndex + 1} 段',
                  index: indexOffset + i,
                  selected: _selected == indexOffset + i,
                  onTap: () => Navigator.pop(context, hits[i])),
            ],
          );
        },
      );

  Widget _result(BuildContext context, {
    required IconData icon, required String title,
    required String subtitle, required VoidCallback onTap,
    required int index, required bool selected,
  }) => MouseRegion(
    onEnter: (_) {
      if (mounted && _selected != index) {
        setState(() => _selected = index);
      }
    },
    child: AnimatedContainer(
      key: ValueKey('atelier-result-$index'),
      duration: HyesMotion.duration(
        context, const Duration(milliseconds: 170)),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? AtelierColor.accent(context).withValues(alpha: .095)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border(left: BorderSide(width: 3, color: selected
            ? AtelierColor.accent(context) : Colors.transparent)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 19),
          dense: true,
          hoverColor: AtelierColor.accent(context).withValues(alpha: .12),
          leading: Icon(icon, size: 19, color: AtelierColor.accent(context)),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: HyesTokens.serifFamily,
              fontWeight: FontWeight.w600, fontSize: 16,
              color: AtelierColor.foreground(context))),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 12,
            color: AtelierColor.secondary(context))),
          onTap: onTap,
        ),
      ),
    ),
  );
}
