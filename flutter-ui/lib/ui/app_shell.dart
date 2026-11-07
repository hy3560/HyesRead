import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/book_entry.dart';
import '../data/library_repository.dart';
import '../data/reading_progress.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../widgets/book_cover.dart';
import '../widgets/paper_button.dart';
import '../widgets/book_open_route.dart';
import '../widgets/shelf_filter_bar.dart';
import '../widgets/import_arrival.dart';
import '../widgets/empty_shelf_art.dart';
import '../widgets/book_spine_wall.dart';
import '../widgets/appearance_paper.dart';
import 'app_language.dart';
import 'atelier_widgets.dart';
import 'atelier_stage.dart';
import 'atelier_atmosphere.dart';
import 'atelier_command_palette.dart';
import 'glass_widgets.dart';
import 'paper_dock.dart';

const _tabs = ['继续阅读', '我的书架', '阅读记录', '设置'];
const _dockLabels = ['续读', '书架', '记录', '设置'];
const _icons = [
  Icons.auto_stories_outlined, Icons.library_books_outlined,
  Icons.insights_outlined, Icons.tune_rounded,
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key, required this.repository, required this.mode,
    required this.onModeChanged, this.onThemePressed,
    this.language = HyesLanguage.chinese, this.onLanguageChanged,
    this.animationsEnabled = true, this.onAnimationsChanged,
  });
  final LibraryRepository repository;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;
  final void Function(ThemeMode, Offset)? onThemePressed;
  final HyesLanguage language;
  final ValueChanged<HyesLanguage>? onLanguageChanged;
  final bool animationsEnabled;
  final ValueChanged<bool>? onAnimationsChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  HyesLanguage? _languageOverride;
  HyesLanguage get _language => _languageOverride ?? widget.language;
  HyesCopy get _copy => HyesCopy(_language);
  String _tr(String text) => _copy.tr(text);

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _languageOverride = null;
    }
  }

  void _changeLanguage(HyesLanguage value) {
    if (value == _language) return;
    setState(() => _languageOverride = value);
    widget.onLanguageChanged?.call(value);
  }
  final TextEditingController searchController = TextEditingController();
  final ScrollController _contentScroll = ScrollController();
  final ValueNotifier<double> _titleCollapse = ValueNotifier(0);
  // Only the selected tab is mounted. A switcher kept outgoing records
  // behind the incoming cover and exposed both during compositing.
  late final AnimationController _tabEntrance = AnimationController(
    vsync: this,
    duration: HyesMotion.slow,
    value: 1,
  );
  int _tabTravelDirection = 1;
  int tab = 0;
  int visibleCount = 84;
  String query = '';
  String filter = 'all';
  String sort = 'last';
  bool grid = true;
  bool importing = false;
  bool _dragOverLibrary = false;
  BookEntry? _importArrivalBook;
  int _importSequence = 0;
  String? _liftedId;
  String? _pressedId;
  Offset? _lastThemePress;
  final Set<String> _progressLookups = {};

  @override
  void initState() {
    super.initState();
    // Opening the app should make resuming the last book the first action.
    tab = widget.repository.recentlyRead.isEmpty ? 1 : 0;
    _contentScroll.addListener(() {
      if (!_contentScroll.hasClients) return;
      final next = (_contentScroll.offset / 115).clamp(0.0, 1.0);
      if ((_titleCollapse.value - next).abs() > .003) {
        _titleCollapse.value = next;
      }
    });
  }

  @override
  void dispose() {
    _tabEntrance.dispose();
    searchController.dispose();
    _contentScroll.dispose();
    _titleCollapse.dispose();
    super.dispose();
  }

  void _selectTab(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (tab == value) return;
    setState(() {
      _tabTravelDirection = value > tab ? 1 : -1;
      tab = value;
    });
    if (HyesMotion.reduced(context)) {
      _tabEntrance.value = 1;
    } else {
      // A phone never needs the desktop's long perspective reveal.
      _tabEntrance.duration = MediaQuery.sizeOf(context).width < 840
          ? const Duration(milliseconds: 300) : HyesMotion.slow;
      _tabEntrance.forward(from: 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _progressLabel(BookEntry book) {
    if (!book.hasReading) return _tr('未开始');
    _ensureEpubProgress(book);
    return _copy.progress(book.progress);
  }

  void _ensureEpubProgress(BookEntry book) {
    if (book.isEpub &&
        book.progress <= 0 &&
        (book.epubLocation?.isNotEmpty ?? false) &&
        _progressLookups.add(book.id)) {
      final location = book.epubLocation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreEpubPercent(book.id, book.path, location));
      });
    }
  }

  Future<void> _restoreEpubPercent(
      String id, String path, String? encodedLocation) async {
    try {
      final value = await epubProgressFromFile(path, encodedLocation);
      if (!mounted || value == null) return;
      final latest = widget.repository.byId(id);
      if (latest == null || latest.epubLocation != encodedLocation ||
          latest.progress > 0 || value == 0) return;
      await widget.repository.replace(latest.copyWith(progress: value));
      if (mounted) setState(() {});
    } catch (_) {
      // EPUB reading remains possible when progress metadata is unavailable.
    }
  }

  Future<void> _openCommandPalette() async {
    if (!mounted) return;
    final selected = await showGeneralDialog<Object>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _language == HyesLanguage.english
          ? 'Dismiss search' : '关闭搜索',
      barrierColor: Colors.black.withValues(alpha: .66),
      transitionDuration: HyesMotion.duration(
        context, const Duration(milliseconds: 320)),
      pageBuilder: (context, _, _) => SafeArea(
        child: AtelierCommandPalette(
          books: widget.repository.books, language: _language)),
      transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: HyesMotion.reduced(context)
                  ? Offset.zero : const Offset(0, -.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation,
                curve: Curves.easeOutCubic)),
            child: child)),
    );
    if (!mounted) return;
    if (selected is AtelierTextSearchMatch) {
      // The UI result uses the reader's exact stable UTF-16 paragraph anchor.
      // Only a user-confirmed result moves the saved reading location.
      final current = widget.repository.byId(selected.book.id);
      if (current == null || current.archived) return;
      try {
        await widget.repository.replace(current.copyWith(
          paragraphIndex: selected.paragraphIndex,
          textOffset: selected.textOffset,
          progress: selected.progress,
        ));
        if (mounted) await _open(current);
      } catch (error) {
        _notice(_language == HyesLanguage.english
          ? 'Could not open search match: $error'
          : '无法跳转搜索结果：$error');
      }
    } else if (selected is BookEntry) {
      await _open(selected);
    } else if (selected is int && selected >= 0 &&
        selected < _tabs.length) {
      _selectTab(selected);
    }
  }

  Future<void> _importBooks() async {
    if (importing) return;
    setState(() => importing = true);
    var added = 0, duplicate = 0, restored = 0;
    BookEntry? lastImported;
    final failures = <String>[];
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: BookEntry.supported.toList(),
        allowMultiple: true,
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      for (final file in picked.files) {
        File? temporary;
        try {
          File source;
          if (file.path != null) {
            source = File(file.path!);
          } else if (file.bytes != null) {
            final dir = await getTemporaryDirectory();
            temporary = File(p.join(dir.path, 'hyesread-import-' +
                DateTime.now().microsecondsSinceEpoch.toString() +
                p.extension(file.name)));
            await temporary.writeAsBytes(file.bytes!, flush: true);
            source = temporary;
          } else {
            throw const FileSystemException('系统文件提供者没有提供可读取的文件');
          }
          final result = await widget.repository.importFile(
            source, displayName: file.name,
          );
          if (result.imported) {
            added++;
            lastImported = widget.repository.books.last;
          } else if (result.reactivated) {
            restored++;
          } else {
            duplicate++;
          }
        } catch (error) {
          failures.add(file.name + '：' + error.toString());
        } finally {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        }
      }
      if (!mounted) return;
      setState(() {
        tab = 1;
        if (lastImported != null) {
          _importArrivalBook = lastImported;
          _importSequence++;
        }
      });
      if (added != 1 || duplicate != 0 || restored != 0 || failures.isNotEmpty) {
        _notice(_language == HyesLanguage.english
          ? 'Imported $added · Duplicate $duplicate · Restored $restored · Failed ${failures.length}'
          : '上架 $added 本，重复 $duplicate 本，恢复 $restored 本，'
            '未导入 ${failures.length} 本');
      }
      if (failures.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_tr('部分书籍导入失败')),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: SelectableText(failures.join('\n')),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_tr('了解')),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      _notice(_tr('无法打开系统文件选择器：') + error.toString());
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  /// Native file drop uses the existing repository's SHA-256 verification,
  /// duplicate handling, rollback and private-library storage.
  Future<void> _importDroppedFiles(List<DropItemFile> dropped) async {
    if (importing || dropped.isEmpty) {
      if (mounted) setState(() => _dragOverLibrary = false);
      return;
    }
    setState(() {
      importing = true;
      _dragOverLibrary = false;
    });
    var added = 0, duplicate = 0, restored = 0, rejected = 0;
    BookEntry? lastImported;
    final errors = <String>[];
    try {
      Directory temporaryDirectory;
      try {
        temporaryDirectory = await getTemporaryDirectory();
      } on MissingPluginException {
        // Widget tests and unusual portable hosts may not have a
        // path_provider delegate. The OS temporary folder is still safe.
        temporaryDirectory = Directory.systemTemp;
      }
      for (var i = 0; i < dropped.length; i++) {
        final source = dropped[i];
        final name = source.name;
        final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
        if (!BookEntry.supported.contains(extension)) {
          rejected++;
          continue;
        }
        // The untrusted source name is never part of the temporary path.
        final temporary = File(p.join(temporaryDirectory.path,
          'hyesread-drop-${DateTime.now().microsecondsSinceEpoch}-$i.$extension'));
        try {
          // DropItemFile streams Uint8List; IOSink consumes List<int>.
          // Cast the stream view without buffering the entire book in RAM.
          await source.openRead().cast<List<int>>()
              .pipe(temporary.openWrite());
          final result = await widget.repository.importFile(
            temporary, displayName: name);
          if (result.imported) {
            added++;
            lastImported = widget.repository.books.last;
          } else if (result.reactivated) {
            restored++;
          } else {
            duplicate++;
          }
        } catch (error) {
          errors.add('$name：$error');
        } finally {
          // Only our new temp copy may be deleted; not the dropped original.
          if (await temporary.exists()) {
            try {
              await temporary.delete();
            } on FileSystemException {
              // Windows readers/antivirus may release the temporary later.
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        tab = 1;
        if (lastImported != null) {
          _importArrivalBook = lastImported;
          _importSequence++;
        }
      });
      if (added != 1 || duplicate > 0 || restored > 0 ||
          rejected > 0 || errors.isNotEmpty) {
        _notice(_language == HyesLanguage.english
          ? 'Imported $added · Duplicate $duplicate · Restored $restored · '
            'Unsupported $rejected · Failed ${errors.length}'
          : '上架 $added 本，重复 $duplicate 本，恢复 $restored 本，'
            '不支持 $rejected 本，失败 ${errors.length} 本');
      }
      if (errors.isNotEmpty) _notice(errors.take(2).join('；'));
    } catch (error) {
      _notice(_language == HyesLanguage.english
        ? 'Could not import dropped books: $error'
        : '无法导入拖放书籍：$error');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _open(BookEntry book) async {
    if (!book.canRead) {
      _notice(book.format.toUpperCase() + ' · ' + _tr('暂未支持此格式阅读'));
      return;
    }
    if (!File(book.path).existsSync()) {
      _notice(_tr('书籍副本不存在，请重新导入'));
      return;
    }
    // Do not delay the user's first page on a disk write. The repository
    // serializes snapshots and the reader saves its own position on exit.
    unawaited(widget.repository.markOpened(book.id).catchError((Object error) {
      if (mounted) _notice(_tr('无法保存打开时间：') + error.toString());
    }));
    if (!mounted) return;
    await Navigator.of(context).push(BookOpenRoute(
      book: book, repository: widget.repository,
      reduceMotion: HyesMotion.reduced(context)));
    if (mounted) setState(() {});
  }

  Future<void> _archive(BookEntry book) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('从书架隐藏这本书？')),
        content: Text(_language == HyesLanguage.english
          ? '"${book.title}" → Settings / Hidden books'
          : '《${book.title}》→ 设置 · 已隐藏的书籍'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('隐藏书籍'))),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await widget.repository.archive(book.id);
      _notice(_tr('已隐藏，可在设置中恢复'));
    } catch (error) {
      _notice(_tr('无法更新书架：') + error.toString());
    }
  }

  Future<void> _toggleFavorite(BookEntry book) async {
    try {
      await widget.repository.setFavorite(book.id, !book.favorite);
      _notice(_tr(book.favorite ? '已从收藏移除' : '已加入收藏'));
    } catch (error) {
      _notice(_tr('无法更新收藏：') + error.toString());
    }
  }

  Future<void> _liftBook(BookEntry book) async {
    HyesMotion.stamped(context);
    setState(() => _liftedId = book.id);
    final t = HyesTokens.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .4),
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: t.surface.withValues(alpha: .94),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
            child: SafeArea(top: false,
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.title, maxLines: 2, style: t.title),
                  const SizedBox(height: 8),
                  Text('${book.format.toUpperCase()} · '
                      '${_progressLabel(book)}',
                    style: t.caption),
                  const SizedBox(height: 20),
                  ListTile(contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.star_border_rounded),
                    title: Text(_tr(book.favorite ? '取消收藏' : '加入收藏')),
                    onTap: () => Navigator.pop(context, 'favorite')),
                  ListTile(contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(_tr('从书架隐藏')),
                    onTap: () => Navigator.pop(context, 'archive')),
                ]),
              ),
            ),
          ),
        ),
    );
    if (!mounted) return;
    setState(() => _liftedId = null);
    if (chosen == 'favorite') await _toggleFavorite(book);
    if (chosen == 'archive') await _archive(book);
  }

  List<BookEntry> get _filteredBooks {
    final books = widget.repository.books.where((book) {
      final matches = (book.title + ' ' + book.format)
          .toLowerCase().contains(query.trim().toLowerCase());
      return matches && (filter == 'all' ||
          (filter == 'started' && book.hasReading) ||
          (filter == 'favorite' && book.favorite) ||
          (filter == 'new' && !book.hasReading));
    }).toList();
    switch (sort) {
      case 'title': books.sort((a, b) => a.title.compareTo(b.title));
      case 'added': books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      default:
        books.sort((a, b) =>
            (b.lastOpenedAt ?? b.importedAt).compareTo(a.lastOpenedAt ?? a.importedAt));
    }
    return books;
  }

  Widget _desktopRail() {
    const railInk = AtelierColor.nightInk;
    const railAccent = AtelierColor.nightAccent;
    final onRail = railInk.withValues(alpha: .74);
    return Container(
      key: const ValueKey('atelier-sidebar'),
      width: 224,
      color: AtelierColor.rail(context),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(21, 29, 19, 25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AtelierBrandMark(size: 38, darkSurface: true),
          const SizedBox(height: 46),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 16),
            child: Text(_tr('我的阅读'),
              style: TextStyle(color: onRail.withValues(alpha: .78),
                fontSize: 11, letterSpacing: 2.1)),
          ),
          for (var i = 0; i < _tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('atelier-nav-$i'),
                  borderRadius: BorderRadius.circular(9),
                  hoverColor: railInk.withValues(alpha: .08),
                  onTap: () => _selectTab(i),
                  child: AnimatedContainer(
                    duration: HyesMotion.duration(context,
                        const Duration(milliseconds: 270)),
                    curve: Curves.easeOutCubic,
                    height: 46,
                    padding: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: tab == i
                          ? railInk.withValues(alpha: .11)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border(left: BorderSide(
                        color: tab == i ? railAccent : Colors.transparent,
                        width: 2.4)),
                    ),
                    child: Row(children: [
                      const SizedBox(width: 11),
                      Icon(_icons[i], size: 19,
                        color: tab == i ? railAccent : onRail),
                      const SizedBox(width: 13),
                      Expanded(child: Text(_tr(_dockLabels[i]),
                        style: TextStyle(fontSize: 14,
                          fontWeight: tab == i
                              ? FontWeight.w600 : FontWeight.w400,
                          color: tab == i ? railInk : onRail))),
                      Text('${i + 1}'.padLeft(2, '0'),
                        style: TextStyle(fontSize: 10, letterSpacing: 1.1,
                          color: railInk.withValues(alpha:
                              tab == i ? .72 : .35))),
                    ]),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Container(width: 26, height: 1,
            color: railAccent.withValues(alpha: .73)),
          const SizedBox(height: 14),
          Text('${widget.repository.books.length}'.padLeft(2, '0'),
            style: const TextStyle(fontFamily: HyesTokens.serifFamily,
              fontSize: 27, color: railInk)),
          const SizedBox(height: 6),
          Text(_copy.bookCount(widget.repository.books.length),
            style: TextStyle(color: onRail, fontSize: 12)),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isControlPressed ||
             HardwareKeyboard.instance.isMetaPressed)) {
          _openCommandPalette();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            return BackdropGroup(child: Scaffold(
              extendBody: false,
              backgroundColor: AtelierColor.groundFor(context),
              bottomNavigationBar: wide ? null : PaperDock(
                selectedIndex: tab,
                onSelected: _selectTab,
                icons: _icons,
                labels: _dockLabels.map(_tr).toList(),
              ),
              body: AtelierNightAtmosphere(
                focusBook: widget.repository.recentlyRead.isEmpty
                  ? null : widget.repository.recentlyRead.first,
                child: Stack(children: [
                Positioned.fill(child: ColoredBox(
                color: AtelierColor.groundFor(context),
                child: SafeArea(
                child: Row(children: [
                  if (wide)
                    _desktopRail(),
                  Expanded(child: Column(children: [
                    wide ? _header(wide) : _mobileLiquidHeader(),
                    Expanded(child: SingleChildScrollView(
                      controller: _contentScroll,
                      padding: EdgeInsets.fromLTRB(
                        wide ? 52 : 24,
                        wide ? 30 : 14,
                        wide ? 52 : 24, 40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 1080),
                          child: ClipRect(child: AnimatedBuilder(
                            animation: _tabEntrance,
                            child: KeyedSubtree(key: ValueKey(tab),
                              child: switch (tab) {
                                0 => _home(),
                                1 => LayoutBuilder(builder: (context, inner) =>
                                  _library(inner.maxWidth)),
                                2 => _records(),
                                _ => _settings(),
                              }),
                            builder: (context, scene) {
                              final reduced = HyesMotion.reduced(context);
                              final mobileScene = !wide;
                              final t = reduced ? 1.0 : _tabEntrance.value;
                              // A single-stage editorial reveal: one finite
                              // depth/unfold gesture instead of ghosted tabs.
                              final ease = Curves.easeOutCubic.transform(t);
                              final opacity = Curves.easeOutQuad.transform(
                                (t / .52).clamp(0.0, 1.0));
                              final elevation = 1 - ease;
                              return IgnorePointer(
                                ignoring: t < .22,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Transform.translate(
                                    offset: Offset(
                                      _tabTravelDirection * elevation *
                                          (mobileScene ? 9 : 17),
                                      elevation * (mobileScene ? 10 : 20)),
                                    child: Transform(
                                      alignment: Alignment.topCenter,
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, .0007)
                                        ..rotateX(
                                          (mobileScene ? 0 : .015) * elevation)
                                        ..rotateY(
                                          _tabTravelDirection *
                                              (mobileScene ? 0 : .033) * elevation)
                                        ..scaleByDouble(
                                          1 - (mobileScene ? .008 : .022) * elevation,
                                          1 - (mobileScene ? .008 : .022) * elevation,
                                          1, 1),
                                      child: scene,
                                    ),
                                  ),
                                ),
                              );
                            },
                          )),
                        ),
                      ),
                    )),
                  ])),
                ]),
                ),
              )),
                if (_importArrivalBook != null)
                  Positioned.fill(child: ImportArrival(
                    key: ValueKey('import-stamp-$_importSequence'),
                    book: _importArrivalBook!,
                    onFinished: () {
                      if (mounted) setState(() => _importArrivalBook = null);
                    },
                  )),
              ])),
            ));
          },
        );
      },
    ));
  }

  // Continuous collapse (not a sudden two-state app bar); the scroll value is
  // outside the page state so long bookshelves don't rebuild on each pixel.
  Widget _mobileLiquidHeader() {
    return ValueListenableBuilder<double>(valueListenable: _titleCollapse,
      builder: (context, progress, _) {
        final tokens = HyesTokens.of(context);
        final compact = MediaQuery.sizeOf(context).width < 430;
        final showImport = tab == 1 && widget.repository.books.isNotEmpty;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 13 - 5 * progress, 24,
              12 - 5 * progress),
          child: Row(children: [
            AtelierBrandMark(
              size: 27,
              darkSurface: Theme.of(context).brightness == Brightness.dark),
            const SizedBox(width: 10),
            Expanded(child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(_tr(_tabs[tab]), maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.display.copyWith(
                  fontSize: (compact ? 29.0 : 35.0) - progress * 11,
                  letterSpacing: .5 - progress * .5)),
            )),
            if (MediaQuery.sizeOf(context).width >= 380)
              IconButton(
                key: const ValueKey('atelier-command-open-mobile'),
                onPressed: _openCommandPalette,
                tooltip: _language == HyesLanguage.english
                    ? 'Search books and commands'
                    : '搜索书籍与命令',
                icon: const Icon(Icons.search_rounded, size: 22)),
            if (showImport) ...[
              const SizedBox(width: 8),
              SizedBox(height: 48,
                child: TextButton(
                  key: const ValueKey('paper-import'),
                  onPressed: importing ? null : _importBooks,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.vermilion,
                    minimumSize: const Size(48, 48)),
                  child: importing ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Text(_tr('导入'), style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ]),
        );
      });
  }

  Widget _header(bool wide) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 24, 36, 8),
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: SizedBox(height: 44, child: Row(children: [
        Text(_tr('书房'),
          style: TextStyle(fontSize: 13, letterSpacing: 1.0,
            color: AtelierColor.secondary(context))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 14),
          child: Icon(Icons.arrow_forward_ios_rounded,
            size: 10, color: Color(0xFF857F71))),
        Expanded(child: Text(_tr(_tabs[tab]),
          style: TextStyle(fontSize: 14, letterSpacing: .5,
            color: AtelierColor.foreground(context)))),
        IconButton(
          key: const ValueKey('atelier-command-open'),
          onPressed: _openCommandPalette,
          tooltip: _language == HyesLanguage.english
              ? 'Search books and commands (Ctrl+K)'
              : '搜索书籍与命令 (Ctrl+K)',
          icon: Icon(Icons.search_rounded,
            color: AtelierColor.foreground(context), size: 21)),
        const SizedBox(width: 8),
        if (tab == 1)
          FilledButton.icon(
            key: const ValueKey('paper-import'),
            onPressed: importing ? null : _importBooks,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_tr('导入书籍')),
            style: FilledButton.styleFrom(
              backgroundColor: AtelierColor.accent(context),
              foregroundColor: const Color(0xFFFAF6ED),
              minimumSize: const Size(138, 48),
              shape: const RoundedRectangleBorder(),
            ),
          ),
      ])),
    )),
  );

  Widget _home() {
    final recent = widget.repository.recentlyRead;
    final featured = recent.firstOrNull ??
        widget.repository.books.firstOrNull;
    if (featured == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _empty(
          headline: _tr(widget.repository.books.isEmpty
              ? '从一本好书开始' : '今天想读哪一本？'),
          action: () => _selectTab(1),
          actionText: _tr('去书架'),
        ),
      ]);
    }
    final first = featured;
    return _editorialHome(first, recent);
  }

  Widget _editorialHome(BookEntry featured, List<BookEntry> recent) {
    _ensureEpubProgress(featured);
    final favorites = widget.repository.favorites
        .where((book) => book.id != featured.id).take(4).toList();
    final favoriteIds = favorites.map((book) => book.id).toSet();
    final otherRecent = (recent.isEmpty ? widget.repository.books : recent)
        .where((book) => book.id != featured.id &&
            !favoriteIds.contains(book.id)).take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AtelierResumePoster(
        key: const ValueKey('atelier-resume-poster'),
        book: featured,
        onRead: () => _open(featured),
        onBrowse: () => _selectTab(1),
        translate: _tr,
      ),
      const SizedBox(height: 15),
      LayoutBuilder(builder: (context, box) {
        final pathways = [
          _homePathway(Icons.collections_bookmark_outlined,
            _tr('我的书架'), () => _selectTab(1)),
          _homePathway(Icons.add_rounded,
            _tr('添一本新书'), _importBooks),
        ];
        if (box.maxWidth < 550) {
          return Column(children: [
            pathways.first,
            const SizedBox(height: 8),
            pathways.last,
          ]);
        }
        return Row(children: [
          Expanded(child: pathways.first),
          const SizedBox(width: 22),
          Expanded(child: pathways.last),
        ]);
      }),
      if (favorites.isNotEmpty) ...[
        const SizedBox(height: 37),
        _sectionTitle(_tr('我的收藏')),
        const SizedBox(height: 16),
        _editorialShelfRail(favorites),
      ],
      if (otherRecent.isNotEmpty) ...[
        const SizedBox(height: 38),
        _sectionTitle(_tr('最近')),
        const SizedBox(height: 16),
        _editorialShelfRail(otherRecent),
      ],
      const SizedBox(height: 30),
    ]);
  }

  Widget _editorialShelfRail(List<BookEntry> books) =>
      LayoutBuilder(builder: (context, box) {
        const spacing = 20.0;
        final columns = ((box.maxWidth + spacing) / 230)
            .floor().clamp(1, 4);
        final cardWidth = (box.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(spacing: spacing, runSpacing: 16,
          children: books.map((book) => SizedBox(
            width: cardWidth,
            child: AtelierRecentMini(
              book: book,
              onOpen: () => _open(book),
              subtitle: _progressLabel(book),
            ),
          )).toList(),
        );
      });

  Widget _homePathway(IconData icon, String title, VoidCallback onTap) {
    final ink = AtelierColor.foreground(context);
    return AtelierHoverLift(elevation: 2,
      child: Material(color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(
            top: BorderSide(color: AtelierColor.rule(context)))),
          padding: const EdgeInsets.fromLTRB(3, 16, 3, 15),
          child: Row(children: [
            Icon(icon, size: 20, color: AtelierColor.accent(context)),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(fontSize: 17,
              fontFamily: HyesTokens.serifFamily,
              fontWeight: FontWeight.w600, color: ink))),
            Icon(Icons.arrow_upward_rounded, size: 17,
              color: AtelierColor.accent(context)),
          ]),
        ),
      ),
    ));
  }

  Widget _library(double width) {
    final books = _filteredBooks;
    // A cover needs physical room for its title and actions. Three tiny
    // columns at 320px felt like thumbnail wallpaper, not a personal shelf.
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final minimumWidth = textScale > 1.4 ? 200.0
        : width < 720 ? 165.0 : 180.0;
    final gutter = width > 720 ? 26.0 : 16.0;
    final columns = ((width + gutter) / (minimumWidth + gutter))
        .floor().clamp(1, 4).toInt();
    final cellWidth = (width - (columns - 1) * gutter) / columns;
    final coverHeight = (cellWidth - 12).clamp(64.0, 205.0) * 760 / 540;
    final shown = books.take(visibleCount).toList();
    if (grid && shown.length == 1) {
      _ensureEpubProgress(shown.first);
    }
    final options = <(String, String)>[
      ('all', _tr('全部')), ('started', _tr('正在读')),
      ('new', _tr('未开始')),
      if (widget.repository.favorites.isNotEmpty || filter == 'favorite')
        ('favorite', _tr('收藏')),
    ];
    return DropTarget(
      key: const ValueKey('atelier-native-drop-target'),
      enable: !importing,
      onDragEntered: (_) {
        if (mounted && !_dragOverLibrary) {
          setState(() => _dragOverLibrary = true);
        }
      },
      onDragExited: (_) {
        if (mounted && _dragOverLibrary) {
          setState(() => _dragOverLibrary = false);
        }
      },
      onDragDone: (details) => unawaited(_importDroppedFiles(
        details.files.whereType<DropItemFile>().toList(),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pageTitle(_tr('我的书架')),
            const SizedBox(height: 6),
            Text(_copy.bookCount(widget.repository.books.length),
              style: TextStyle(fontSize: 14,
                color: AtelierColor.secondary(context))),
          ])),
      ]),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AtelierColor.sheet(context),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AtelierColor.rule(context)),
          ),
          child: TextField(
            key: const ValueKey('shelf-search-open'),
            controller: searchController,
            onChanged: (value) => setState(() {
              query = value;
              visibleCount = 84;
            }),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                size: 21, color: AtelierColor.secondary(context)),
              suffixIcon: query.isEmpty ? null : IconButton(
                tooltip: _tr('清除筛选'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  query = ''; searchController.clear();
                  FocusManager.instance.primaryFocus?.unfocus();
                }),
              ),
              hintText: _tr('搜索书名或格式'),
              hintStyle: const TextStyle(fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11, vertical: 15),
              isDense: true,
            ),
          ),
        )),
        const SizedBox(width: 10),
        SizedBox(height: 48, child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 48, height: 48, child: PopupMenuButton<String>(
                tooltip: _tr('书籍排序'),
                icon: const Icon(Icons.swap_vert_rounded, size: 22),
                initialValue: sort,
                onSelected: (v) => setState(() => sort = v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'last',
                    child: Text(_tr('最近阅读'))),
                  PopupMenuItem(value: 'added',
                    child: Text(_tr('最近加入'))),
                  PopupMenuItem(value: 'title',
                    child: Text(_tr('按书名'))),
                ],
              )),
              Container(width: 1, height: 21,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14)),
              SizedBox(width: 48, height: 48, child: IconButton(
                tooltip: _tr(grid ? '切换列表' : '切换网格'),
                onPressed: () => setState(() => grid = !grid),
                icon: Icon(grid ? Icons.view_agenda_outlined
                    : Icons.grid_view_rounded, size: 21),
              )),
            ],
          )),
      ]),
      const SizedBox(height: 16),
      ShelfFilterBar(
        labels: options.map((item) => item.$2).toList(),
        selected: math.max(0, options.indexWhere((v) => v.$1 == filter)),
        onSelect: (i) => setState(() {
          filter = options[i].$1; visibleCount = 84;
        }),
      ),
      const SizedBox(height: 20),
      if (books.isEmpty) ...[
        _empty(
        headline: widget.repository.books.isEmpty
            ? _tr('还没有书籍') : _tr('没有匹配的书籍'),
        action: widget.repository.books.isEmpty
            ? _importBooks : () => setState(() {
                query = ''; filter = 'all'; searchController.clear();
              }),
        actionText: _tr(widget.repository.books.isEmpty ? '添加文件' : '清除筛选'),
        compactArtwork: true,
        ),
      ]
      else if (grid && books.length == 1 && textScale <= 1.4)
        AtelierShelfFeature(
          key: const ValueKey('atelier-single-book'),
          book: shown.first,
          translate: _tr,
          onOpen: () => _open(shown.first),
          actions: _bookActions(shown.first),
        )
      else if (grid)
        GridView.builder(
          shrinkWrap: true,
          addAutomaticKeepAlives: false,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: shown.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns, crossAxisSpacing: gutter,
            mainAxisSpacing: 26,
            mainAxisExtent: coverHeight + (textScale > 1.4 ? 120 : 111),
          ),
          itemBuilder: (context, index) => _arrivingBook(shown[index], index),
        )
      else
        ...shown.map((book) => Padding(
          padding: const EdgeInsets.only(bottom: 9), child: _bookRow(book),
        )),
      if (books.length > shown.length)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Center(child: OutlinedButton(
            onPressed: () => setState(() => visibleCount += 84),
            child: Text(_tr('显示更多书籍')),
          )),
        ),
      if (books.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(_copy.bookCount(books.length),
          style: HyesTokens.of(context).caption.copyWith(fontSize: 14)),
      ],
      const SizedBox(height: 38),
      AtelierDropZone(
        key: const ValueKey('atelier-drop-zone'),
        highlighted: _dragOverLibrary,
        enabled: !importing,
        language: _language,
        onTap: _importBooks,
      ),
    ]));
  }

  Widget _arrivingBook(BookEntry book, int index) {
    final reduced = HyesMotion.reduced(context);
    final delay = reduced ? Duration.zero :
        Duration(milliseconds: math.min(index, 5) * 22);
    return Animate(
      key: ValueKey('book-entrance-$filter-${book.id}'),
      effects: [
        FadeEffect(begin: 0, end: 1, delay: delay,
          duration: reduced ? Duration.zero : HyesMotion.base,
          curve: HyesMotion.enter),
        if (!reduced) ...[
          MoveEffect(begin: const Offset(0, 8), end: Offset.zero,
            delay: delay, duration: HyesMotion.base,
            curve: HyesMotion.enter),
        ],
      ],
      child: AtelierHoverLift(elevation: 5, shadow: true,
        child: _bookTile(book)),
    );
  }

  Widget _bookTile(BookEntry book) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 23;
    // On everyday phones the *cover* is the object, not a card containing a
    // small icon. Keep the more spacious JellyCard for accessibility scaling.
    if (largeText) {
      return GestureDetector(onLongPress: () => _liftBook(book),
        child: JellyCard(
        onTap: () => _open(book),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Center(child: _Cover(
              book: book, width: 140, height: 210))),
            const SizedBox(height: 10),
            Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Row(children: [
              Expanded(child: Text(book.format.toUpperCase(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11))),
              _bookActions(book),
            ]),
          ]),
        ),
      ));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final coverWidth = (constraints.maxWidth - 12).clamp(64.0, 205.0);
      final coverHeight = coverWidth * 760 / 540;
      final lifted = _liftedId == book.id;
      final pressed = _pressedId == book.id;
      final reduced = HyesMotion.reduced(context);
      return AnimatedContainer(
        duration: HyesMotion.duration(context, HyesMotion.base),
        curve: HyesMotion.enter,
        transformAlignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(0.0, reduced ? 0.0 : (lifted ? -4.0 : 0.0))
          ..scale(reduced ? 1.0 : lifted ? 1.025 : pressed ? .985 : 1.0),
        child: Material(type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _open(book),
            onLongPress: () => _liftBook(book),
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressedId = value ? book.id : null);
            },
            borderRadius: BorderRadius.circular(4),
            child: Stack(children: [
              Positioned.fill(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: coverHeight + 6,
                      child: Center(child: SizedBox(width: coverWidth,
                        height: coverHeight, child: Stack(children: [
                          _Cover(book: book, width: coverWidth,
                            height: coverHeight),
                          if (book.hasReading && !book.isEpub)
                            Positioned(left: 0, right: 0, bottom: 0,
                              child: LinearProgressIndicator(
                                value: book.progress.clamp(0, 1), minHeight: 2,
                                color: HyesTokens.of(context).vermilion,
                                backgroundColor: Colors.transparent)),
                        ]))),
                    ),
                    const SizedBox(height: 9),
                    Text(book.title, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16,
                        fontFamily: HyesTokens.serifFamily,
                        fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(child: Text(!book.hasReading
                          ? _tr('未开始') : _progressLabel(book),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: HyesTokens.of(context).caption.copyWith(
                          fontSize: 13))),
                      _bookActions(book),
                    ]),
                  ],
                ),
              )),
              Positioned.fill(child: IgnorePointer(child: AnimatedContainer(
                duration: HyesMotion.duration(context, HyesMotion.base),
                color: _liftedId != null && !lifted
                    ? Colors.black.withValues(alpha: .4)
                    : Colors.transparent))),
            ]),
          ),
        ),
      );
    });
  }

  Widget _bookRow(BookEntry book, {bool hero = true}) => JellyCard(
    radius: 22,
    onTap: () => _open(book),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          _Cover(book: book, width: 52, height: 72, hero: hero),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(book.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              if (book.favorite) ...[
                const SizedBox(width: 5),
                Icon(Icons.star_rounded, size: 17,
                    color: Theme.of(context).colorScheme.primary),
              ],
            ]),
            const SizedBox(height: 6),
            Text('${book.format.toUpperCase()}  ·  ${!book.canRead
                ? _tr('暂未支持此格式阅读')
                : _progressLabel(book)}',
                style: TextStyle(fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          _bookActions(book),
        ]),
      ),
  );

  // The ellipsis opens explicit actions; it must never immediately hide a book.
  Widget _bookActions(BookEntry book) => SizedBox(
    width: 48, height: 48,
    child: PopupMenuButton<String>(
      tooltip: _tr('书籍操作'),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (action) {
        if (action == 'favorite') {
          unawaited(_toggleFavorite(book));
        } else if (action == 'archive') {
          unawaited(_archive(book));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: Row(children: [
            Icon(book.favorite ? Icons.star_outline_rounded : Icons.star_rounded,
                size: 20),
            const SizedBox(width: 12),
            Text(_tr(book.favorite ? '取消收藏' : '加入收藏')),
          ]),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 20),
            const SizedBox(width: 12),
            Text(_tr('从书架隐藏')),
          ]),
        ),
      ],
    ),
  );

  Widget _records() {
    final read = widget.repository.recentlyRead;
    final all = widget.repository.books;
    final started = all.where((b) => b.hasReading).length;
    final t = HyesTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pageTitle(_tr('阅读记录')),
      const SizedBox(height: 22),
      _recordCounters(all.length, started,
        all.fold<int>(0, (sum, book) => sum +
          book.textBookmarks.length + book.epubBookmarks.length +
          book.pdfBookmarks.length)),
      const SizedBox(height: 23),
      if (read.isEmpty) ...[
        const SizedBox(height: 40),
        Container(width: 24, height: 2, color: t.vermilion),
        const SizedBox(height: 22),
        Text(_tr('暂无阅读记录'), style: t.title),
      ] else ...[
        if (all.length > 2) ...[
          _sectionTitle(_tr('书脊墙')),
          const SizedBox(height: 8),
          BookSpineWall(books: all, onOpen: _open),
          const SizedBox(height: 26),
        ],
        _sectionTitle(_tr('最近打开')),
        const SizedBox(height: 18),
        for (final book in read) _recordTimelineItem(book),
      ],
    ]);
  }

  Widget _pageTitle(String title) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: HyesTokens.serifFamily,
        fontWeight: FontWeight.w600, fontSize: 39,
        color: AtelierColor.foreground(context))),
  );

  Widget _recordCounters(int books, int reading, int bookmarks) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 555;
        final items = <(int, String)>[
          (books, _tr('书架藏书')),
          (reading, _tr('已经开始')),
          (bookmarks, _tr('书签')),
        ];
        Widget metric((int, String) item) => Container(
          key: ValueKey('atelier-record-stat-${item.$2}'),
          constraints: BoxConstraints(minHeight: compact ? 96 : 116),
          padding: EdgeInsets.fromLTRB(compact ? 12 : 24,
              compact ? 15 : 18, compact ? 8 : 20, compact ? 14 : 19),
          decoration: BoxDecoration(
            color: AtelierColor.sheet(context),
            borderRadius: BorderRadius.circular(13)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${item.$1}'.padLeft(2, '0'),
                style: TextStyle(
                  fontFamily: HyesTokens.serifFamily,
                  fontSize: compact ? 28 : 35,
                  color: AtelierColor.foreground(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
              SizedBox(height: compact ? 5 : 8),
              Text(item.$2, style: TextStyle(
                fontSize: compact ? 12 : 14,
                color: AtelierColor.secondary(context))),
            ]),
        );
        return Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: compact ? 8 : 18),
            Expanded(child: metric(items[i])),
          ],
        ]);
      });

  Widget _recordTimelineItem(BookEntry book) {
    final t = HyesTokens.of(context);
    return IntrinsicHeight(child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 16, child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 6, height: 6,
            decoration: BoxDecoration(color: t.vermilion,
              borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 4),
          Expanded(child: Container(width: 1, color: t.divider)),
        ])),
        const SizedBox(width: 12),
        Padding(padding: const EdgeInsets.only(bottom: 20),
          child: BookCover(book: book, width: 40, height: 60,
            elevation: false)),
        const SizedBox(width: 15),
        Expanded(child: Material(type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _open(book),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(_progressLabel(book), maxLines: 1,
                    overflow: TextOverflow.ellipsis, style: t.caption),
                  const SizedBox(height: 4),
                  Text(trueRelativeOpenedAt(book.lastOpenedAt!, DateTime.now()),
                    style: t.caption.copyWith(color: t.quiet)),
                ],
              ),
            ),
          ),
        )),
      ],
    ));
  }

  Widget _appearancePicker() {
    const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    const labels = ['自动', '浅色', '深色'];
    return Row(children: [
      for (var i = 0; i < modes.length; i++)
        Expanded(child: AppearancePaper(
          label: _tr(labels[i]), mode: modes[i],
          selected: widget.mode == modes[i],
          onTapDown: (details) => _lastThemePress = details.globalPosition,
          onTap: () {
            if (widget.onThemePressed != null && _lastThemePress != null) {
              widget.onThemePressed!(modes[i], _lastThemePress!);
            } else {
              widget.onModeChanged(modes[i]);
            }
          },
        )),
    ]);
  }

  Widget _languagePicker() => Wrap(
    spacing: 12, runSpacing: 12,
    children: [
      for (final value in HyesLanguage.values)
        OutlinedButton.icon(
          key: ValueKey('language-${value.code}'),
          onPressed: () => _changeLanguage(value),
          icon: Icon(_language == value
              ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 19),
          label: Text(value.label),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(135, 55),
            foregroundColor: AtelierColor.foreground(context),
            side: BorderSide(color: _language == value
                ? AtelierColor.cinnabar
                : AtelierColor.secondary(context).withValues(alpha: .28)),
            shape: const RoundedRectangleBorder()),
        ),
    ]);

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(_tr('语言')),
      const SizedBox(height: 15),
      _languagePicker(),
      const SizedBox(height: 29),
      Divider(height: 1, color: HyesTokens.of(context).divider),
      const SizedBox(height: 28),
      _sectionTitle(_tr('外观')),
      const SizedBox(height: 16),
      _appearancePicker(),
      const SizedBox(height: 22),
      Container(
        key: const ValueKey('atelier-animations-setting'),
        constraints: const BoxConstraints(minHeight: 65),
        child: Row(children: [
          Expanded(child: Text(_tr('界面动效'),
            style: TextStyle(fontSize: 17,
              color: AtelierColor.foreground(context)))),
          const SizedBox(width: 18),
          Switch.adaptive(
            key: const ValueKey('atelier-animations-switch'),
            value: widget.animationsEnabled,
            activeThumbColor: AtelierColor.accent(context),
            onChanged: widget.onAnimationsChanged,
          ),
        ]),
      ),
      const SizedBox(height: 22),
      Divider(height: 1, color: HyesTokens.of(context).divider),
      const SizedBox(height: 28),
      _sectionTitle(_tr('已隐藏的书籍')),
      const SizedBox(height: 12),
      ...widget.repository.archived.map((book) => Column(children: [
          SizedBox(height: 70, child: Row(children: [
            BookCover(book: book, width: 28, height: 42, elevation: false),
            const SizedBox(width: 16),
            Expanded(child: Text(book.title, maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: HyesTokens.of(context).body)),
            TextButton(
              child: Text(_tr('恢复')),
              onPressed: () async {
                try {
                  await widget.repository.restore(book.id);
                } catch (error) {
                  _notice(_tr('无法恢复：') + error.toString());
                }
              },
            ),
          ])),
          Divider(height: 1, color: HyesTokens.of(context).divider),
        ])),
    ],
  );

  Widget _sectionTitle(String title, {String? subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(
        fontSize: 24, fontFamily: HyesTokens.serifFamily,
        fontWeight: FontWeight.w600)),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle, style: TextStyle(
          fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant,
        )),
      ],
    ],
  );

  Widget _empty({
    required String headline,
    required VoidCallback action, required String actionText,
    bool compactArtwork = false,
  }) {
    final colors = HyesTokens.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 23;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, compactArtwork ? 28 : 48, 8, 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.repository.books.isEmpty)
              const EmptyShelfArt(height: 220)
            else
              Padding(padding: const EdgeInsets.symmetric(vertical: 20),
                child: SizedBox(width: 60, height: 2,
                  child: ColoredBox(color: colors.vermilion))),
            const SizedBox(height: 26),
            Text(headline, textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: largeText ? 24 : 28,
                height: 1.3,
                fontFamily: HyesTokens.serifFamily,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              )),
            const SizedBox(height: 22),
            PaperButton(
              key: const ValueKey('empty-liquid-action'),
              onPressed: action,
              icon: actionText == _tr('添加文件')
                  ? Icons.add_rounded : Icons.arrow_forward_rounded,
              label: actionText,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.book, required this.width, required this.height,
    this.hero = true});
  final BookEntry book;
  final double width, height;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final art = BookCover(book: book, width: width, height: height);
    return hero ? Hero(tag: 'hyes-cover-${book.id}', child: art) : art;
  }
}
