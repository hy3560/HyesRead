import 'package:flutter/material.dart';

import '../parser/epub_book.dart';
import '../parser/epub_models.dart';
import 'reader_controller.dart';

/// A [Drawer] listing the book's table of contents.
///
/// Tapping an entry closes the drawer and calls
/// [EpubReaderController.jumpToHref]. The list follows the book's reading
/// direction. Put it in `Scaffold.drawer` (or `endDrawer`).
class EpubTocDrawer extends StatelessWidget {
  /// Creates a TOC drawer.
  const EpubTocDrawer({
    super.key,
    required this.book,
    required this.controller,
    this.header,
    this.onSelected,
  });

  /// The book.
  final EpubBook book;

  /// The controller of the reader to navigate.
  final EpubReaderController controller;

  /// Optional widget above the entries; defaults to the book title.
  final Widget? header;

  /// Called after an entry was chosen.
  final ValueChanged<EpubNavItem>? onSelected;

  List<(EpubNavItem, int)> _flatten(List<EpubNavItem> items, int depth) => [
        for (final item in items) ...[
          (item, depth),
          ..._flatten(item.children, depth + 1)
        ],
      ];

  List<EpubNavItem> get _entries {
    if (book.navigation.toc.isNotEmpty) return book.navigation.toc;
    // No TOC: list the spine documents.
    return [
      for (final (i, s) in book.spine.items.indexed)
        EpubNavItem(
            title: '${i + 1}. ${s.item.href.split('/').last}',
            href: s.item.href),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _flatten(_entries, 0);
    final current = controller.location.spineIndex;
    return Drawer(
      child: SafeArea(
        child: Directionality(
          textDirection: book.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: ListView(
            children: [
              header ??
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(book.metadata.title,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
              for (final (item, depth) in entries)
                ListTile(
                  contentPadding: EdgeInsetsDirectional.only(
                      start: 16.0 + depth * 16, end: 16),
                  title: Text(item.title),
                  enabled: item.href != null,
                  selected: item.href != null &&
                      book.spineIndexOfHref(item.href!) == current,
                  onTap:
                      item.href == null ? null : () => _select(context, item),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, EpubNavItem item) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    if (scaffold != null && scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
    controller.jumpToHref(item.href!);
    onSelected?.call(item);
  }
}
