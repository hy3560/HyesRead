part of 'reader_page.dart';

extension _ReaderViews on _ReaderPageState {
  Widget _textBody() {
    if (pageMode) {
      return TextPageReader(
        key: textPagerKey,
        paragraphs: paragraphs,
        initialCursor: TextPageCursor(paragraph, textOffset),
        title: book.title,
        paper: readerPaper, ink: readerInk,
        contentWidth: contentWidth,
        fontSize: fontSize, lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        justify: justifyText,
        topInset: 0,
        minimalChrome: true,
        surround: narrowReader ? readerPaper : readerSurround,
        fontFamily: readerFont,
        onPositionChanged: _onTextPagePosition,
      );
    }
    return ColoredBox(
      color: narrowReader ? readerPaper : readerSurround,
      child: Center(child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentWidth),
        child: ScrollablePositionedList.builder(
          key: ValueKey(book.id),
          initialScrollIndex: paragraph,
          itemPositionsListener: positionListener,
          itemScrollController: scrollController,
          scrollOffsetController: offsetController,
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 86),
          itemCount: paragraphs.length,
          itemBuilder: (context, i) => _readerParagraph(i),
        ),
      )),
    );
  }

  /// Chapter decoration does not alter paragraphs or saved anchor indices.
  Widget _readerParagraph(int i) {
    final value = paragraphs[i];
    final line = value.trim();
    final chapter = line.length <= 36 &&
        TextPageLayouter.chapterHeading.hasMatch(line);
    final subheading = TextPageLayouter.isSubheading(paragraphs, i);
    final t = HyesTokens.of(context);
    if (chapter) {
      final match = RegExp(
          r'^(第[一二三四五六七八九十百千万零〇两0-9]+[章回卷节集])\s*[：:·—-]?\s*(.*)$')
          .firstMatch(line);
      final sequence = match != null && match[2]!.isNotEmpty ? match[1] : null;
      final title = sequence == null ? line : match![2]!;
      return Padding(padding: EdgeInsets.only(bottom: fontSize * 1.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 64),
          if (sequence != null) ...[
            Text(sequence, style: _proseStyle(size: 12).copyWith(
                color: readerInk.withValues(alpha: .65),
                letterSpacing: 4, height: 1.4)),
            const SizedBox(height: 12),
          ],
          SelectableText(title, textAlign: TextAlign.center,
              style: _proseStyle(size: 26,
                weight: FontWeight.w600).copyWith(height: 1.4)),
          const SizedBox(height: 18),
          Container(width: 24, height: 2, color: t.vermilion),
        ]));
    }
    if (subheading) {
      return Padding(padding: EdgeInsets.only(
          top: fontSize * 1.8, bottom: fontSize * .7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(width: 3, height: fontSize, color: t.vermilion),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(line,
              style: _proseStyle(size: fontSize * 1.12,
                  weight: FontWeight.w600).copyWith(height: 1.4))),
        ]));
    }
    return Padding(padding: EdgeInsets.only(bottom: paragraphSpacing),
      child: SelectableText('\u3000\u3000${value.trimLeft()}',
        textAlign: justifyText ? TextAlign.justify : TextAlign.start,
        style: _proseStyle(),
      ));
  }

  Widget _epubBody() => ColoredBox(
    color: narrowReader ? readerPaper : readerSurround,
    child: Center(child: Container(
      constraints: BoxConstraints(maxWidth: readerSheetWidth),
      decoration: narrowReader ? null : BoxDecoration(
        color: readerPaper,
        border: Border.all(color: readerInk.withValues(alpha: .06)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .045),
          blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFeatures: [FontFeature.enable('palt')]),
        child: EpubReaderView(
        key: _epubViewKey,
        book: epubBook!,
        controller: epubController,
        mode: epubFacingPages ? EpubReaderMode.spread
            : pageMode ? EpubReaderMode.paginated : EpubReaderMode.scroll,
        settings: epubTypography(
          fontSize: fontSize, lineHeight: lineHeight, paper: paper,
          fontKind: fontKind, paragraphSpacing: paragraphSpacing,
          justify: justifyText, isApple: Platform.isIOS || Platform.isMacOS,
          eyeWarmth: eyeWarmth,
        ),
        initialLocation: epubLocation == null
            ? null : EpubLocation.tryDecode(epubLocation!),
        onLocationChanged: _saveEpubLocation,
      ),
      ),
    )),
  );

  Widget _pdfBody() => PdfViewer.file(
    book.path,
    controller: pdfController,
    params: PdfViewerParams(
      calculateInitialPageNumber: (document, _) =>
          pdfPage.clamp(1, document.pages.length).toInt(),
      onViewerReady: (document, _) {
        pdfCount = document.pages.length;
        _refreshReader();
      },
      onPageChanged: (page) {
        if (page == null || page == pdfPage) return;
        pdfPage = page;
        progress = pdfCount > 1
            ? ((pdfPage - 1) / (pdfCount - 1)).clamp(0.0, 1.0).toDouble() : 0.0;
        _scheduleSave();
        _refreshReader();
      },
    ),
  );

  Widget _readerContent() => failure != null
      ? Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(failure!, textAlign: TextAlign.center)))
      : book.isText
          ? loading || paragraphs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _textBody()
          : book.isEpub
              ? loading || epubBook == null
                  ? const Center(child: CircularProgressIndicator())
                  : _epubBody()
              : _pdfBody();

  AppBar _readerAppBar(BuildContext context, bool marked,
      {required bool floating}) {
    final narrow = MediaQuery.sizeOf(context).width < 430 ||
        (MediaQuery.textScalerOf(context).scale(16) > 22 &&
            MediaQuery.sizeOf(context).width < 640);
    return AppBar(
      primary: !floating,
      backgroundColor: readerPaper,
      foregroundColor: readerInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: readerInk.withValues(alpha: .10))),
      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: readerInk, fontFamily: HyesTokens.serifFamily,
          fontSize: 18, fontWeight: FontWeight.w600)),
      leading: IconButton(
        tooltip: _tr('保存并返回书架'), onPressed: _exit,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        _bookmarkAction(marked),
        if (!narrow && book.isText && !loading && failure == null)
          IconButton(
            key: const ValueKey('reader-search-action'),
            tooltip: _english ? 'Find in book (Ctrl+K)' : '搜索书内正文 (Ctrl+K)',
            onPressed: _openReaderTextSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        if (!narrow)
          IconButton(
            tooltip: _tr('查看书签列表'),
            onPressed: failure == null ? _showBookmarks : null,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
        if (!narrow && ((book.isText && !loading) ||
            (book.isPdf && pdfCount > 0)))
          IconButton(
            tooltip: _tr('跳转阅读位置'),
            onPressed: failure == null && !loading ? _showReadingNavigation : null,
            icon: const Icon(Icons.explore_outlined),
          ),
        if (book.isText || book.isEpub)
          IconButton(
            tooltip: _tr('阅读排版'), onPressed: _readingSettings,
            icon: const Icon(Icons.text_fields_rounded),
          ),
        if (!narrow && (book.isText || book.isEpub))
          IconButton(
            key: const ValueKey('reader-mode-toggle'),
            tooltip: _tr(pageMode ? '改为滚动阅读' : '开启双页翻页阅读'),
            onPressed: failure == null && !loading ? _togglePageMode : null,
            icon: Icon(pageMode
              ? Icons.view_day_outlined : Icons.menu_book_outlined),
          ),
        if (book.isEpub && !narrow)
          IconButton(
            tooltip: _tr('章节目录'),
            onPressed: () => readerScaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.toc_rounded),
          ),
        if (narrow)
          PopupMenuButton<String>(
            tooltip: _tr('更多阅读操作'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) {
              switch (action) {
                case 'bookmarks':
                  _showBookmarks();
                case 'search':
                  unawaited(_openReaderTextSearch());
                case 'toc':
                  readerScaffoldKey.currentState?.openEndDrawer();
                case 'navigate':
                  _showReadingNavigation();
                case 'focus':
                  _setFocusReading(true);
                case 'mode':
                  unawaited(_togglePageMode());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'bookmarks', child: Text(_tr('书签列表'))),
              if (book.isText && !loading && failure == null)
                PopupMenuItem(value: 'search', child: Text(
                  _english ? 'Find in book' : '搜索书内正文')),
              if ((book.isText && !loading && failure == null) ||
                  (book.isPdf && pdfCount > 0))
                PopupMenuItem(value: 'navigate',
                  child: Text(_tr('跳转阅读位置'))),
              if (book.isEpub)
                PopupMenuItem(value: 'toc', child: Text(_tr('章节目录'))),
              if (book.isText || book.isEpub)
                PopupMenuItem(value: 'focus', child: Text(_tr('专注阅读'))),
              if (book.isText || book.isEpub)
                PopupMenuItem(value: 'mode',
                    child: Text(_tr(pageMode ? '改为滚动阅读'
                        : '开启翻页阅读'))),
            ],
          )
        else if (book.isText || book.isEpub)
          IconButton(
            tooltip: _tr('进入专注阅读'),
            onPressed: () => _setFocusReading(true),
            icon: const Icon(Icons.fullscreen_rounded),
          ),
      ],
    );
  }

  Widget _bookmarkAction(bool marked) {
    final accent = HyesTokens.of(context).vermilion;
    return SizedBox(width: 44, height: 44, child: IconButton(
      key: const ValueKey('reader-bookmark-action'),
      tooltip: _tr(marked ? '取消当前书签' : '标记当前位置'),
      onPressed: failure == null ? _bookmark : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: AnimatedBuilder(
        animation: _bookmarkAnimation,
        child: Icon(marked
          ? PhosphorIconsFill.bookmark : PhosphorIconsRegular.bookmark,
          size: 22, color: marked ? accent : readerInk),
        builder: (context, icon) {
          final t = _bookmarkAnimation.value;
          final scale = !_bookmarkAnimation.isAnimating ? 1.0
              : _bookmarkWasAdded
                  ? t < .52
                      ? .78 + .42 * Curves.easeOutBack.transform(t / .52)
                      : 1.20 - .20 * Curves.easeOutCubic
                          .transform((t - .52) / .48)
                  : 1 - .13 * math.sin(math.pi * t);
          final angle = (_bookmarkWasAdded ? -.14 : .12) *
              math.sin(math.pi * t) * (1 - t);
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center,
            children: [
              if (_bookmarkWasAdded && t > 0 && t < .78)
                IgnorePointer(child: Opacity(
                  opacity: (1 - t / .78) * .48,
                  child: Transform.scale(
                    scale: .55 + 1.15 * (t / .78),
                    child: Container(
                      key: const ValueKey('reader-bookmark-stamp-ring'),
                      width: 20, height: 20,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.35)),
                    ),
                  ),
                )),
              Transform.rotate(angle: angle,
                child: Transform.scale(scale: scale, child: icon)),
            ],
          );
        },
      ),
    ));
  }

  Widget _readerToolbar(bool marked) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final scaler = MediaQuery.textScalerOf(context);
    // A11y text at 200% must grow the bar; a fixed 65px Row clipped the
    // book/chapter subtitle by 6px on narrow phones.
    final barHeight = math.max(65.0,
        scaler.scale(14) * 1.3 + scaler.scale(11) * 1.35 + 13);
    Widget action(String tooltip, IconData glyph, VoidCallback? callback,
        {Color? color}) => SizedBox(width: 44, height: 44,
      child: IconButton(tooltip: _tr(tooltip), onPressed: callback,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(glyph, size: 22, color: color ?? readerInk)));
    return Material(color: readerPaper.withValues(alpha: .94),
      child: Container(height: barHeight,
        padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
            color: readerInk.withValues(alpha: .10)))),
        child: Row(children: [
          action('保存并返回书架', PhosphorIconsRegular.arrowLeft, _exit),
          const SizedBox(width: 6),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: _proseStyle(size: 14).copyWith(
                    fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 3),
              Text(_chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11,
                    fontFamily: readerFont ?? HyesTokens.serifFamily,
                    color: readerInk.withValues(alpha: .72))),
            ])),
          action(book.isEpub ? '章节目录' : '跳转阅读位置',
              PhosphorIconsRegular.list,
              book.isEpub
                  ? () => readerScaffoldKey.currentState?.openEndDrawer()
                  : _showReadingNavigation),
          _bookmarkAction(marked),
          if (wide && book.isText && !loading && failure == null)
            KeyedSubtree(
              key: const ValueKey('reader-search-action'),
              child: action(_english ? 'Find in book (Ctrl+K)'
                  : '搜索书内正文 (Ctrl+K)',
                PhosphorIconsRegular.magnifyingGlass,
                _openReaderTextSearch),
            ),
          if (book.isText || book.isEpub)
            action('阅读排版', PhosphorIconsRegular.textAa, _readingSettings),
          if (wide && (book.isText || book.isEpub))
            Tooltip(
              message: _tr(pageMode ? '切换为滚动阅读'
                  : '开启自动双页阅读'),
              child: Semantics(
                button: true,
                label: _tr(pageMode ? '当前翻页模式，切换为滚动'
                    : '当前滚动模式，开启双页'),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('reader-spread-mode-chip'),
                    onTap: () => unawaited(_togglePageMode()),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color:
                            (pageMode ? HyesTokens.of(context).vermilion
                                : readerInk).withValues(alpha: .38)),
                        color: readerInk.withValues(alpha: .035),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(pageMode ? Icons.auto_stories_outlined
                            : Icons.view_agenda_outlined,
                            size: 16, color: pageMode
                                ? HyesTokens.of(context).vermilion : readerInk),
                        const SizedBox(width: 7),
                        Text(_tr(!pageMode ? '滚动' :
                            (book.isEpub ? epubFacingPages :
                              MediaQuery.sizeOf(context).width >= 760 &&
                              MediaQuery.sizeOf(context).height >= 440 &&
                              MediaQuery.textScalerOf(context).scale(fontSize) <= 29)
                              ? '双页' : '翻页'),
                          style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: readerInk)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (!wide) SizedBox(width: 44, height: 44,
            child: PopupMenuButton<String>(
              key: const ValueKey('reader-more'),
              tooltip: _tr('更多阅读操作'),
              icon: Icon(PhosphorIconsRegular.dotsThree,
                  color: readerInk, size: 22),
              onSelected: (item) {
                switch (item) {
                  case 'bookmarks': unawaited(_showBookmarks());
                  case 'search': unawaited(_openReaderTextSearch());
                  case 'position': unawaited(_showReadingNavigation());
                  case 'focus': _toggleChrome();
                  case 'mode': unawaited(_togglePageMode());
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'bookmarks',
                    child: Text(_tr('书签列表'))),
                if (book.isText && !loading && failure == null)
                  PopupMenuItem(value: 'search', child: Text(
                    _english ? 'Find in book' : '搜索书内正文')),
                if (book.isText)
                  PopupMenuItem(value: 'position',
                    child: Text(_tr('跳转阅读位置'))),
                PopupMenuItem(value: 'focus', child: Text(
                    _tr(focusReading ? '显示阅读工具栏' : '专注阅读'))),
                PopupMenuItem(value: 'mode', child: Text(
                    _tr(pageMode ? '滚动阅读' : '覆盖翻页'))),
              ],
            ),
          ),
          if (wide) ...[
            action('查看书签列表', PhosphorIconsRegular.bookmarks, _showBookmarks),
            action('进入专注阅读', PhosphorIconsRegular.arrowsOut,
                () => _setFocusReading(true)),
          ],
        ]),
      ),
    );
  }

  Widget _readerBottomPanel() {
    final facing = epubFacingPages;
    final paragraphNavigation = book.isText && _chapterCount == 1 &&
        paragraphs.length > 1;
    final count = paragraphNavigation ? paragraphs.length : _chapterCount;
    final current = paragraphNavigation ? paragraph : _chapterIndex;
    final unit = paragraphNavigation ? '段' : '章';
    final t = HyesTokens.of(context);
    return Material(color: readerPaper.withValues(alpha: .94),
      child: DecoratedBox(decoration: BoxDecoration(
        border: Border(top: BorderSide(color: readerInk.withValues(alpha: .10)))),
        child: Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChapterScrubber(
              key: const ValueKey('reader-chapter-scrubber'),
              index: current, count: count,
              ink: readerInk, accent: t.vermilion, paper: readerPaper,
              chapterLabel: (index) => paragraphNavigation
                  ? _english ? 'Paragraph ${index + 1}'
                      : '第 ${index + 1} 段'
                  : book.isEpub
                  ? _epubDetails(index).$1
                  : book.isText && index < _textChapterStarts.length
                      ? paragraphs[_textChapterStarts[index]].trim()
                      : _english ? 'Chapter ${index + 1}'
                          : '第 ${index + 1} 章',
              onCommit: paragraphNavigation ? _jumpToTextParagraph : _goToChapter,
            ),
            Row(children: [
              IconButton(
                key: ValueKey(book.isEpub
                    ? 'epub-previous-chapter' : 'reader-previous-chapter'),
                tooltip: _tr(facing ? '上一对书页' : '上一章'),
                onPressed: facing
                    ? epubController.canTurnScreen(-1)
                        ? () => _turnReader(-1) : null
                    : current > 0 ? () => paragraphNavigation
                    ? _jumpToTextParagraph(current - 1)
                    : _goToChapter(current - 1) : null,
                icon: Icon(PhosphorIconsRegular.caretLeft,
                    color: readerInk, size: 22),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44)),
              Expanded(child: Text(_english
                  ? facing
                      ? 'Spread ${(epubController.facingPairIndex ?? 0) + 1}'
                        ' / ${epubController.facingPairCount ?? 1}'
                        ' · Chapter ${current + 1}'
                      : '${paragraphNavigation ? 'Paragraph' : 'Chapter'}'
                        ' ${current + 1} / $count · '
                        '${(_chapterFraction * 100).round()}%'
                  : facing
                      ? '第 ${(epubController.facingPairIndex ?? 0) + 1} / '
                        '${epubController.facingPairCount ?? 1} 对 · '
                        '第 ${current + 1} 章'
                      : '第 ${current + 1} / $count $unit · '
                        '${(_chapterFraction * 100).round()}%',
                  key: const ValueKey('reader-chapter-progress'),
                  textAlign: TextAlign.center, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: readerInk, fontSize: 13,
                      fontFamily: readerFont ?? HyesTokens.serifFamily,
                      fontWeight: FontWeight.w600))),
              IconButton(
                key: ValueKey(book.isEpub
                    ? 'epub-next-chapter' : 'reader-next-chapter'),
                tooltip: _tr(facing ? '下一对书页' : '下一章'),
                onPressed: facing
                    ? epubController.canTurnScreen(1)
                        ? () => _turnReader(1) : null
                    : current + 1 < count ? () => paragraphNavigation
                    ? _jumpToTextParagraph(current + 1)
                    : _goToChapter(current + 1) : null,
                icon: Icon(PhosphorIconsRegular.caretRight,
                    color: readerInk, size: 22),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _readerProgressHint() => IgnorePointer(child: Align(
    alignment: Alignment.bottomRight,
    child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 18, 10),
      child: Text(_english
          ? '${book.isText && _chapterCount == 1 ? 'Paragraph' : 'Chapter'}'
            ' ${book.isText && _chapterCount == 1 ? paragraph + 1 : _chapterIndex + 1}'
            ' · ${(_chapterFraction * 100).round()}%'
          : book.isText && _chapterCount == 1
              ? '第 ${paragraph + 1} 段 · ${(_chapterFraction * 100).round()}%'
              : '第 ${_chapterIndex + 1} 章 · '
                '${(_chapterFraction * 100).round()}%',
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: 11, fontFamily: HyesTokens.serifFamily,
          color: readerInk.withValues(alpha: .64))),
    ),
  ));

  /// A brief chapter hand-off, painted above the reading sheet but beneath
  /// the toolbar. It never replaces the EPUB controller or reading anchor.
  Widget _chapterTransitionCue() => AnimatedBuilder(
    animation: _chapterCueAnimation,
    builder: (context, _) {
      final index = _chapterCueIndex;
      final t = _chapterCueAnimation.value;
      if (index == null || t <= 0 || t >= 1 ||
          HyesMotion.reduced(context)) return const SizedBox.shrink();
      final opacity = (math.sin(math.pi * t) * 1.6).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      return IgnorePointer(child: ExcludeSemantics(
        child: Opacity(opacity: opacity,
          child: Center(child: SizedBox(
            key: const ValueKey('reader-chapter-transition'),
            width: math.min(contentWidth + 48, MediaQuery.sizeOf(context).width),
            height: double.infinity,
            child: ColoredBox(color: readerPaper,
              child: Center(child: Transform.translate(
                offset: Offset(0, 9 * (1 - eased)),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_english ? 'Chapter ${index + 1} / $_chapterCount'
                        : '第 ${index + 1} / $_chapterCount 章',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: 11, letterSpacing: 3,
                        color: readerInk.withValues(alpha: .66))),
                    const SizedBox(height: 15),
                    Text(_chapterCueTitle, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _proseStyle(size: 21,
                          weight: FontWeight.w600).copyWith(height: 1.35)),
                    const SizedBox(height: 20),
                    SizedBox(width: 24, height: 2,
                      child: ColoredBox(color: HyesTokens.of(context).vermilion)),
                  ]),
                ),
              )),
            ),
          )),
        ),
      ));
    },
  );

  Widget _immersiveBody(bool marked) {
    final reduced = HyesMotion.reduced(context);
    final duration = reduced ? Duration.zero : const Duration(milliseconds: 220);
    final sheetWidth = readerSheetWidth;
    Widget edgeFade({required bool top}) => IgnorePointer(
      child: Align(alignment: Alignment.center,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: sheetWidth),
          child: Container(height: 28, decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: top
                  ? [readerPaper.withValues(alpha: .92),
                      readerPaper.withValues(alpha: 0)]
                  : [readerPaper.withValues(alpha: 0),
                      readerPaper.withValues(alpha: .92)],
            ),
          )),
        ),
      ),
    );
    return SafeArea(child: MouseRegion(
      onHover: (_) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          _showChrome();
        }
      },
      child: Listener(behavior: HitTestBehavior.translucent,
        onPointerDown: _readerPointerDown,
        onPointerMove: _readerPointerMove,
        onPointerUp: _readerPointerUp,
        onPointerCancel: _readerPointerCancel,
        child: Stack(children: [
          Positioned.fill(child: _readerContent()),
          Positioned.fill(child: ReaderPaperFinish(
            sheetWidth: sheetWidth, ink: readerInk, paper: readerPaper)),
          Positioned.fill(child: _chapterTransitionCue()),
          Positioned(top: 0, left: 0, right: 0,
            child: edgeFade(top: true)),
          Positioned(bottom: focusReading ? 24 : 108, left: 0, right: 0,
            child: edgeFade(top: false)),
          // Content fades to opaque paper before the lower controls. This
          // prevents translucent chrome from showing ghost text underneath.
          if (!focusReading)
            Positioned(left: 0, right: 0, bottom: 0,
              child: IgnorePointer(child: Center(child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheetWidth),
                child: SizedBox(height: 132, child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    stops: const [0, .34, .55],
                    colors: [readerPaper.withValues(alpha: 0),
                      readerPaper, readerPaper],
                  )),
                )),
              ))),
            ),
          Positioned(top: 0, left: 0, right: 0,
            child: Center(child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: sheetWidth),
              child: IgnorePointer(ignoring: focusReading,
                child: ExcludeSemantics(excluding: focusReading,
                  child: AnimatedSlide(
                    offset: Offset(0, focusReading ? -1 : 0),
                    duration: duration, curve: HyesMotion.enter,
                    child: AnimatedOpacity(opacity: focusReading ? 0 : 1,
                      duration: duration,
                      child: AnimatedScale(
                        scale: focusReading ? .985 : 1,
                        alignment: Alignment.topCenter,
                        duration: duration, curve: HyesMotion.enter,
                        child: ColoredBox(color: readerPaper,
                          child: _readerToolbar(marked)),
                      )),
                  ),
                ),
              ),
            )),
          ),
          if (!loading && failure == null && _chapterCount > 0)
            Positioned(bottom: 2, left: 0, right: 0,
              child: Center(child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheetWidth),
                child: IgnorePointer(ignoring: focusReading,
                  child: ExcludeSemantics(excluding: focusReading,
                    child: AnimatedSlide(
                      offset: Offset(0, focusReading ? 1 : 0),
                      duration: duration, curve: HyesMotion.enter,
                      child: AnimatedOpacity(opacity: focusReading ? 0 : 1,
                        duration: duration,
                        child: AnimatedScale(
                          scale: focusReading ? .99 : 1,
                          alignment: Alignment.bottomCenter,
                          duration: duration, curve: HyesMotion.enter,
                          child: ColoredBox(color: readerPaper,
                            child: _readerBottomPanel()),
                        )),
                    ),
                  ),
                ),
              )),
            ),
          if (!loading && failure == null && focusReading && _chapterCount > 0)
            Positioned(bottom: 2, right: 0, child: _readerProgressHint()),
          if (!loading && failure == null && focusReading &&
              _chapterFraction >= .97 && _chapterIndex + 1 < _chapterCount)
            Positioned(left: 0, right: 0, bottom: 34,
              child: Center(child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: sheetWidth - 48),
                child: AnimatedSlide(
                  duration: duration, offset: Offset.zero,
                  child: AnimatedOpacity(opacity: 1,
                    duration: duration,
                    child: Material(color: readerPaper.withValues(alpha: .94),
                      child: InkWell(
                        key: const ValueKey('reader-next-chapter-hint'),
                        onTap: () => _goToChapter(_chapterIndex + 1),
                        child: Padding(padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(child: Text('${_tr('下一章')} · ${book.isEpub
                                ? _epubDetails(_chapterIndex + 1).$1
                                : _textChapterStarts.length > _chapterIndex + 1
                                    ? paragraphs[_textChapterStarts[_chapterIndex + 1]]
                                    : ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: readerInk,
                                fontSize: 13, fontWeight: FontWeight.w600))),
                            Icon(PhosphorIconsRegular.arrowRight,
                              color: readerInk, size: 19),
                          ])),
                      ),
                    ),
                  ),
                ),
              )),
            ),
          Positioned(bottom: 0, left: 0, right: 0,
            child: IgnorePointer(child: Align(alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _overallFraction.clamp(0.0, 1.0),
                child: Container(height: 2,
                  color: HyesTokens.of(context).vermilion),
              ),
            )),
          ),
        ]),
      ),
    ));
  }

  Widget _buildReader(BuildContext context) {
    final saved = widget.repository.byId(book.id) ?? book;
    final marked = book.isText ? saved.textBookmarks.contains(paragraph)
        : book.isPdf ? saved.pdfBookmarks.contains(pdfPage)
        : saved.epubBookmarks.contains(epubLocation);
    final immersive = book.isText || book.isEpub;
    return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          () => _advanceScreen(1),
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          () => _advanceScreen(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown):
          () => _advanceScreen(1),
      const SingleActivator(LogicalKeyboardKey.pageUp):
          () => _advanceScreen(-1),
      const SingleActivator(LogicalKeyboardKey.space):
          () => focusReading ? _showChrome() : _advanceScreen(1),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true):
          () => unawaited(_openReaderTextSearch()),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          () => unawaited(_openReaderTextSearch()),
      const SingleActivator(LogicalKeyboardKey.escape): _toggleChrome,
      const SingleActivator(LogicalKeyboardKey.equal, control: true):
          () => unawaited(_quickAdjustFont(1)),
      const SingleActivator(LogicalKeyboardKey.minus, control: true):
          () => unawaited(_quickAdjustFont(-1)),
      const SingleActivator(LogicalKeyboardKey.keyT):
          () => unawaited(_quickToggleTheme()),
    }, child: Focus(autofocus: true, child: Stack(children: [
    PopScope<void>(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: Scaffold(
        key: readerScaffoldKey,
        backgroundColor: narrowReader ? readerPaper : readerSurround,
        appBar: immersive ? null : _readerAppBar(context, marked, floating: false),
        endDrawer: book.isEpub && epubBook != null
            ? EpubTocDrawer(book: epubBook!, controller: epubController)
            : null,
        body: immersive
            ? _immersiveBody(marked)
            : Column(children: [
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 3),
                Expanded(child: _readerContent()),
                if (failure == null)
                  SafeArea(top: false, child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(tooltip: _tr('上一页'), icon: const Icon(Icons.chevron_left),
                        onPressed: pdfPage <= 1 ? null : () => _turnReader(-1)),
                      TextButton(
                        onPressed: pdfCount > 0 ? _showReadingNavigation : null,
                        child: Text(_english
                            ? 'Page $pdfPage / ${pdfCount > 0 ? pdfCount : '…'}'
                            : '第 $pdfPage / ${pdfCount > 0 ? pdfCount : '…'} 页',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(tooltip: _tr('下一页'), icon: const Icon(Icons.chevron_right),
                        onPressed: pdfCount == 0 || pdfPage >= pdfCount ? null :
                            () => _turnReader(1)),
                    ],
                  )),
              ]),
      ),
    ),
    _openingCover(context),
    ])));
  }

  Widget _openingCover(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return const SizedBox.shrink();
    final reduced = HyesMotion.reduced(context);
    return Positioned.fill(child: IgnorePointer(
      child: Hero(
        tag: 'hyes-cover-${book.id}',
        child: AnimatedBuilder(animation: animation,
          builder: (context, child) {
            // PageRoute finishes the flight at 520ms; the last 220ms turn
            // around a left spine while the real reader is already mounted.
            final turn = reduced ? animation.value :
                ((animation.value - .58) / .42).clamp(0.0, 1.0);
            final matrix = Matrix4.identity();
            if (!reduced) {
              matrix.setEntry(3, 2, .0012);
              matrix.rotateY(-82 * turn * math.pi / 180);
            }
            return Opacity(opacity: (1 - turn).clamp(0.0, 1.0),
              child: Transform(alignment: Alignment.centerLeft,
                transform: matrix, child: child));
          },
          child: FittedBox(fit: BoxFit.fill,
            child: BookCover(book: book, width: 200, height: 300)),
        ),
      ),
    ));
  }
}
