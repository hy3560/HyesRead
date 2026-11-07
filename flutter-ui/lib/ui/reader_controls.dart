part of 'reader_page.dart';

extension _ReaderControls on _ReaderPageState {
  Future<void> _savePreference(Future<bool> writing) async {
    try {
      if (!await writing) _showMessage(_tr('无法保存阅读排版偏好'));
    } catch (error) {
      _showMessage(_tr('保存排版偏好失败：') + error.toString());
    }
  }

  Future<void> _bookmark() async {
    final current = widget.repository.byId(book.id);
    if (current == null) return;
    BookEntry updated;
    String message;
    var adding = false;

    if (book.isText) {
      final marks = [...current.textBookmarks];
      if (marks.remove(paragraph)) {
        message = _tr('已取消书签');
      } else {
        adding = true;
        marks.add(paragraph);
        marks.sort();
        message = _tr('已添加书签');
      }
      updated = current.copyWith(textBookmarks: marks);
    } else if (book.isPdf) {
      final marks = [...current.pdfBookmarks];
      if (marks.remove(pdfPage)) {
        message = _tr('已取消书签');
      } else {
        adding = true;
        marks.add(pdfPage);
        marks.sort();
        message = _tr('已添加书签');
      }
      updated = current.copyWith(pdfBookmarks: marks);
    } else {
      _saveEpubLocation();
      if (epubLocation == null || epubLocation!.isEmpty) {
        _showMessage(_tr('阅读位置还未就绪'));
        return;
      }
      final marks = [...current.epubBookmarks];
      if (marks.remove(epubLocation)) {
        message = _tr('已取消书签');
      } else {
        adding = true;
        marks.add(epubLocation!);
        message = _tr('已添加书签');
      }
      updated = current.copyWith(epubLocation: epubLocation, epubBookmarks: marks);
    }

    try {
      final saving = widget.repository.replace(updated);
      _animateBookmark(added: adding);
      _refreshReader();
      await saving;
      _showMessage(message);
    } catch (error) {
      _showMessage(_tr('无法保存书签：') + error.toString());
    }
  }

  Future<void> _showBookmarks() async {
    final current = widget.repository.byId(book.id);
    if (current == null) return;
    final entries = book.isText
        ? current.textBookmarks
            .map((n) => (n, _english
                ? 'Paragraph ${n + 1}' : '第 ${n + 1} 段')).toList()
        : book.isPdf
            ? current.pdfBookmarks
                .map((n) => (n, _english
                    ? 'Page $n' : '第 $n 页')).toList()
            : current.epubBookmarks.asMap().entries
                .map((e) => (e.key, _english
                    ? 'Bookmark ${e.key + 1}' : '书签 ${e.key + 1}')).toList();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(_tr('我的书签'),
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(26),
              child: Text(_tr('还没有书签')),
            )
          else
            Flexible(child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(entries[i].$2),
                onTap: () {
                  Navigator.pop(context);
                  if (book.isText) {
                    scrollController.scrollTo(
                      index: entries[i].$1,
                      duration: const Duration(milliseconds: 260),
                    );
                  } else if (book.isPdf) {
                    pdfController.setCurrentPageNumber(entries[i].$1);
                  } else {
                    final location = EpubLocation.tryDecode(
                      current.epubBookmarks[entries[i].$1],
                    );
                    if (location != null) epubController.jumpTo(location);
                  }
                },
              ),
            )),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Future<void> _showReadingNavigation() async {
    // EPUB locations are engine-specific anchors, not percent-based pages.
    // Do not expose a misleading seek bar for that renderer.
    if ((!book.isText && !book.isPdf) || loading || failure != null) return;
    final total = book.isText ? paragraphs.length : pdfCount;
    if (total < 1) return;
    final origin = book.isText ? paragraph + 1 : pdfPage;
    final previous = book.isText
        ? (previousTextParagraph == null ? null : previousTextParagraph! + 1)
        : previousPdfPage;
    var selected = origin.clamp(1, total).toInt();
    final destination = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.64,
          child: StatefulBuilder(
            builder: (sheetContext, updateSheet) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(children: [
                  Expanded(child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tr('跳转阅读位置'), style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 22),
                        Text(book.isText
                            ? (_english ? 'Paragraph $selected / $total'
                                : '第 $selected / $total 段')
                            : (_english ? 'Page $selected / $total'
                                : '第 $selected / $total 页'),
                            style: const TextStyle(fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Slider(
                          value: (selected - 1).toDouble(),
                          min: 0, max: math.max(1, total - 1).toDouble(),
                          divisions: total > 1 && total <= 200 ? total - 1 : null,
                          label: book.isText
                            ? (_english ? 'Paragraph $selected' : '第 $selected 段')
                            : (_english ? 'Page $selected' : '第 $selected 页'),
                          onChanged: total < 2 ? null : (value) => updateSheet(() {
                            selected = (value.round() + 1).clamp(1, total).toInt();
                          }),
                        ),
                        if (book.isText) ...[
                          const SizedBox(height: 10),
                          Text(_tr('目标段落预览'), style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(paragraphs[selected - 1], maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.6)),
                        ],
                      ],
                    ),
                  )),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(border: Border(top: BorderSide(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant))),
                    child: Wrap(spacing: 8, runSpacing: 8,
                      alignment: WrapAlignment.end, children: [
                        if (previous != null && previous != origin)
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(sheetContext, previous),
                            icon: const Icon(Icons.undo_rounded),
                            label: Text(_tr('返回上次位置')),
                          ),
                        TextButton(onPressed: () => Navigator.pop(sheetContext),
                            child: Text(_tr('取消'))),
                        FilledButton.icon(
                          onPressed: selected == origin ? null
                              : () => Navigator.pop(sheetContext, selected),
                          icon: const Icon(Icons.near_me_outlined),
                          label: Text(_tr('跳转到此处')),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || destination == null || destination == origin) return;
    if (book.isText) {
      _jumpToTextParagraph(destination - 1);
    } else {
      _jumpToPdfPage(destination);
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(_tr('已跳转到新位置')),
      duration: const Duration(seconds: 7),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: _tr('返回原处'), onPressed: () {
        if (!mounted) return;
        if (book.isText) {
          _jumpToTextParagraph(origin - 1);
        } else {
          _jumpToPdfPage(origin);
        }
      }),
    ));
  }

  Future<void> _readingSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var scopeChanging = false;
    Widget appearancePanel(BuildContext panelContext) => StatefulBuilder(
        builder: (context, refreshSheet) => Theme(
          data: Theme.of(context).copyWith(
            brightness: paper == 'dark' ? Brightness.dark : Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: HyesTokens.light.vermilion,
              brightness: paper == 'dark' ? Brightness.dark : Brightness.light),
            extensions: [paper == 'dark' ? HyesTokens.dark : HyesTokens.light],
            textTheme: Theme.of(context).textTheme.apply(
              bodyColor: readerInk, displayColor: readerInk),
          ),
          child: SafeArea(
          child: AbsorbPointer(
            absorbing: scopeChanging,
            child: SingleChildScrollView(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr('阅读排版'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(_tr('字体'), style: TextStyle(color: readerInk,
                      fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 6),
                  PaperChoiceStrip(
                    labels: ['宋体', '楷体', '黑体', '系统'].map(_tr).toList(),
                    selected: const ['serif', 'kai', 'sans', 'system'].indexOf(fontKind),
                    onSelect: (index) {
                      final family = const ['serif', 'kai', 'sans', 'system'][index];
                      refreshSheet(() => fontKind = family);
                      _refreshReader();
                      unawaited(_savePreference(prefs.setString(
                          _appearanceKey('fontKind'), family)));
                    },
                  ),
                  const SizedBox(height: 12),
                  PaperToggle(
                    label: _tr('只调整这本书'),
                    value: bookLayoutOverride,
                    onChanged: (value) async {
                      if (scopeChanging) return;
                      refreshSheet(() => scopeChanging = true);
                      try {
                        final saved = await setReaderBookOverride(prefs, book.id, value);
                        if (!mounted || !context.mounted) return;
                        if (!saved) {
                          _showMessage(_tr('无法保存单书排版设置'));
                          return;
                        }
                        refreshSheet(() => _loadAppearance(prefs));
                        _refreshReader();
                      } finally {
                        if (context.mounted) refreshSheet(() => scopeChanging = false);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(_tr('快速选择'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  PaperChoiceStrip(
                    labels: readerLayoutPresets.map((e) => _tr(e.label)).toList(),
                    selected: readerLayoutPresets.indexWhere(
                      (e) => e.matches(fontSize, lineHeight, contentWidth)),
                    onSelect: (index) {
                      final preset = readerLayoutPresets[index];
                      refreshSheet(() {
                        fontSize = preset.fontSize;
                        lineHeight = preset.lineHeight;
                        contentWidth = preset.contentWidth;
                      });
                      _refreshReader();
                      unawaited(_savePreference(saveReaderLayoutPreset(
                        prefs, preset,
                        prefix: bookLayoutOverride ? readerBookPrefix(book.id) : '',
                      )));
                    },
                  ),
                  const SizedBox(height: 12),
                  _settingSlider(_tr('字号'), fontSize, 14, 32, (v) {
                    refreshSheet(() => fontSize = v);
                    _refreshReader();
                    _saveSettingDebounced(prefs, 'fontSize', v);
                  }),
                  _settingSlider(_tr('行距'), lineHeight, 1.2, 2.4, (v) {
                    refreshSheet(() => lineHeight = v);
                    _refreshReader();
                    _saveSettingDebounced(prefs, 'lineHeight', v);
                  }),
                  _settingSlider(_tr('正文宽度'), contentWidth, 340, 860, (v) {
                    refreshSheet(() => contentWidth = v);
                    _refreshReader();
                    _saveSettingDebounced(prefs, 'contentWidth', v);
                  }),
                  PaperChoiceStrip(
                    labels: ['窄页', '标准', '宽页'].map(_tr).toList(),
                    selected: contentWidth < 570 ? 0 : contentWidth > 710 ? 2 : 1,
                    onSelect: (index) {
                      final width = const [530.0, 640.0, 760.0][index];
                      refreshSheet(() => contentWidth = width);
                      _refreshReader();
                      _saveSettingDebounced(prefs, 'contentWidth', width);
                    },
                  ),
                  if (book.isText || book.isEpub) ...[
                    const SizedBox(height: 12),
                    Text(_tr('段落排版'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    _settingSlider(_tr('段距'), paragraphSpacing, 6, 32, (v) {
                      refreshSheet(() => paragraphSpacing = v);
                      _refreshReader();
                      _saveSettingDebounced(prefs, 'paragraphSpacing', v);
                    }),
                    PaperChoiceStrip(
                      labels: ['自然左对齐', '两端对齐'].map(_tr).toList(),
                      selected: justifyText ? 1 : 0,
                      onSelect: (index) {
                        final value = index == 1;
                        refreshSheet(() => justifyText = value);
                        _refreshReader();
                        unawaited(_savePreference(
                            prefs.setBool(_appearanceKey('justifyText'), value)));
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(_tr('纸张主题'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  PaperThemeSamples(
                    selected: paper,
                    options: const ['sepia', 'eye', 'gray', 'dark'],
                    onSelect: (value) {
                      refreshSheet(() => paper = value);
                      _refreshReader();
                      unawaited(_savePreference(
                        prefs.setString(_appearanceKey('paper'), value)));
                    },
                  ),
                  if (paper == 'eye') _settingSlider(_tr('暖色'), eyeWarmth, 0, 1, (v) {
                    refreshSheet(() => eyeWarmth = v);
                    _refreshReader();
                    _saveSettingDebounced(prefs, 'eyeWarmth', v);
                  }),
                  const SizedBox(height: 10),
                  Text(_tr('翻页方式'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  PaperChoiceStrip(
                    labels: ['滚动', '覆盖翻页'].map(_tr).toList(),
                    selected: pageMode ? 1 : 0,
                    onSelect: (index) {
                      if ((index == 1) == pageMode) return;
                      unawaited(_togglePageMode().then((_) {
                        if (context.mounted) refreshSheet(() {});
                      }));
                    },
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          )),
          ),
        ),
        ),
    );
    if (!mounted) return;
    if (MediaQuery.sizeOf(context).width >= 600) {
      await showGeneralDialog<void>(
        context: context, barrierDismissible: true,
        barrierLabel: _tr('关闭阅读排版'), barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, _, _) => Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 440, height: double.infinity,
            child: Material(color: readerPaper,
              child: appearancePanel(dialogContext))),
        ),
        transitionBuilder: (dialogContext, animation, _, child) {
          final move = CurvedAnimation(parent: animation,
            curve: Curves.easeOutCubic);
          return SlideTransition(position: Tween<Offset>(
              begin: const Offset(1, 0), end: Offset.zero).animate(move),
            child: FadeTransition(opacity: animation, child: child));
        },
      );
    } else {
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: readerPaper,
        barrierColor: Colors.black38,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: appearancePanel,
      );
    }
    await _flushSettings();
  }

  Widget _settingSlider(String label, double value, double low,
      double high, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: _english ? 108 : 72,
        child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
      Expanded(child: PaperSlider(
        label: label, value: value.clamp(low, high).toDouble(),
        min: low, max: high, step: (high - low) / 16,
        onChanged: onChanged,
      )),
      SizedBox(
        width: 54,
        child: Text(value.toStringAsFixed(label == _tr('行距') ? 1 : 0)),
      ),
    ]);
  }
}
