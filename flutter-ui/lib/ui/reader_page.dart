import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:epub_rtl/epub_rtl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/book_entry.dart';
import '../data/library_repository.dart';
import '../data/reading_progress.dart';
import '../data/text_blocks.dart';
import '../data/epub_presentation.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../widgets/book_cover.dart';
import '../widgets/paper_controls.dart';
import '../widgets/text_page_reader.dart';
import '../widgets/chapter_scrubber.dart';
import '../widgets/reader_paper_finish.dart';
import 'app_language.dart';
import 'reader_typography.dart';
import 'reader_text_search.dart';
import 'text_page_layout.dart';

part 'reader_controls.dart';
part 'reader_views.dart';

/// Loads a library entry and restores its reading position and preferences.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.repository, required this.bookId});
  final LibraryRepository repository;
  final String bookId;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool get _english =>
      HyesLanguageScope.of(context) == HyesLanguage.english;
  String _tr(String text) =>
      HyesCopy(HyesLanguageScope.of(context)).tr(text);
  late BookEntry book;
  EpubBook? epubBook;
  final EpubReaderController epubController = EpubReaderController();
  final PdfViewerController pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> readerScaffoldKey = GlobalKey<ScaffoldState>();
  final ItemPositionsListener positionListener = ItemPositionsListener.create();
  final ItemScrollController scrollController = ItemScrollController();
  final ScrollOffsetController offsetController = ScrollOffsetController();
  final GlobalKey<TextPageReaderState> textPagerKey =
      GlobalKey<TextPageReaderState>();
  final GlobalKey _epubViewKey = GlobalKey();

  List<String> paragraphs = [];
  TextReadingProgress? _textReadingProgress;
  String? failure;
  bool loading = true;
  bool allowPop = false;
  // Only the reading chrome changes; the underlying scroll viewport stays put.
  bool focusReading = true;
  late final AnimationController _bookmarkAnimation;
  bool _bookmarkWasAdded = true;
  late final AnimationController _chapterCueAnimation;
  int? _chapterCueIndex;
  String _chapterCueTitle = '';
  Timer? chromeTimer;
  int? _readerTapPointer;
  Offset? _readerTapStart;
  bool _readerTapDragged = false;
  String fontKind = 'serif';
  final Map<int, (String, int)> _epubChapterDetails = {};
  List<int>? _epubBlockCounts;
  List<int> _textChapterStarts = [0];
  int paragraph = 0, textOffset = 0, pdfPage = 1, pdfCount = 0;
  bool pageMode = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  // In-session backtracking for an intentional location jump. The normal
  // reading position remains saved in the existing book metadata only.
  int? previousTextParagraph, previousPdfPage;
  String? epubLocation;
  double progress = 0, fontSize = 20, lineHeight = 1.9, contentWidth = 640;
  double paragraphSpacing = 11;
  double eyeWarmth = .5;
  bool justifyText = true, bookLayoutOverride = false;
  String paper = 'sepia';
  Color get readerPaper => paper == 'dark' ? const Color(0xFF1A1815)
      : paper == 'light' ? const Color(0xFFFFFDFA)
      : paper == 'eye' ? Color.lerp(const Color(0xFFE9F1DF),
          const Color(0xFFF2E6D2), eyeWarmth)!
      : paper == 'gray' ? const Color(0xFFE6E4E0)
      : const Color(0xFFF4EEE2);
  Color get readerInk => paper == 'dark'
      ? const Color(0xFFDDD4C5)
      : paper == 'eye' ? const Color(0xFF2A3322)
      : paper == 'gray' ? const Color(0xFF2B2B2B)
      : const Color(0xFF2B2620);
  Color get readerSurround => switch (paper) {
    'dark' => const Color(0xFF0F0E0D),
    'eye' => Color.lerp(const Color(0xFFDFE8D5),
          const Color(0xFFE9DCCD), eyeWarmth)!,
    'gray' => const Color(0xFFDEDBD6),
    'light' => const Color(0xFFF4F1EB),
    _ => const Color(0xFFECE3D0),
  };
  bool get narrowReader => MediaQuery.sizeOf(context).width < 600;
  bool get epubFacingPages => book.isEpub && pageMode &&
      // A 760 logical-pixel desktop window still has room for two
      // comfortable ~330px leaves. Keep this breakpoint in logical pixels
      // so high-DPI Windows displays do not silently fall back to one page.
      MediaQuery.sizeOf(context).width >= 760 &&
      MediaQuery.sizeOf(context).height >= 440 &&
      MediaQuery.textScalerOf(context).scale(fontSize) <= 29;
  double get readerSheetWidth => epubFacingPages
      ? math.min(MediaQuery.sizeOf(context).width - 64,
          (contentWidth + 48) * 2 + 32)
      : contentWidth + 48;
  String? get readerFont => fontKind == 'system' ? null :
      readerFontFamily(fontKind, isApple: Platform.isIOS || Platform.isMacOS);
  TextStyle _proseStyle({double? size, FontWeight weight = FontWeight.w400}) =>
      TextStyle(color: readerInk, fontFamily: readerFont,
        fontFamilyFallback: readerFontFallback,
        fontSize: size ?? fontSize, height: lineHeight,
        letterSpacing: (size ?? fontSize) * .02, fontWeight: weight,
        fontFeatures: const [FontFeature.enable('palt')]);

  int get _chapterCount {
    if (book.isEpub) return epubBook?.spine.items.length ?? 0;
    if (book.isText) return _textChapterStarts.length;
    return pdfCount;
  }

  int get _chapterIndex {
    if (book.isEpub) return (EpubLocation.tryDecode(epubLocation ?? '') ??
        epubController.location).spineIndex.clamp(0, math.max(0, _chapterCount - 1));
    if (book.isText) {
      final pos = _textChapterStarts.lastIndexWhere((i) => i <= paragraph);
      return math.max(0, pos);
    }
    return math.max(0, pdfPage - 1);
  }

  (String, int) _epubDetails(int index) {
    final cached = _epubChapterDetails[index];
    if (cached != null) return cached;
    if (epubBook == null || index < 0 || index >= _chapterCount) {
      return ('章节 ${index + 1}', 1);
    }
    try {
      final chapter = EpubChapter.fromBook(epubBook!, index);
      final heading = chapter.blocks.whereType<EpubTextBlock>()
          .where((block) => block.headingLevel != null &&
              block.plainText.trim().isNotEmpty).firstOrNull;
      final title = heading?.plainText.trim() ?? chapter.title ??
          '章节 ${index + 1}';
      return _epubChapterDetails[index] =
          (title.length > 48 ? title.substring(0, 48) : title,
              math.max(1, chapter.blocks.length));
    } catch (_) {
      return _epubChapterDetails[index] = ('章节 ${index + 1}', 1);
    }
  }

  String get _chapterTitle {
    if (book.isEpub) return _epubDetails(_chapterIndex).$1;
    if (book.isText) {
      final i = _textChapterStarts[_chapterIndex];
      return i < paragraphs.length ? paragraphs[i].trim() : '正文';
    }
    return '第 $pdfPage 页';
  }

  double get _chapterFraction {
    if (book.isEpub && _chapterCount > 0) {
      final loc = EpubLocation.tryDecode(epubLocation ?? '') ??
          epubController.location;
      final count = _epubDetails(_chapterIndex).$2;
      return ((loc.elementIndex + loc.fraction) / count).clamp(0.0, 1.0);
    }
    if (book.isText && paragraphs.isNotEmpty) {
      final first = _textChapterStarts[_chapterIndex];
      final last = _chapterIndex + 1 < _chapterCount
          ? _textChapterStarts[_chapterIndex + 1] : paragraphs.length;
      return ((paragraph - first + textOffset /
          math.max(1, paragraphs[paragraph].length)) /
          math.max(1, last - first)).clamp(0.0, 1.0);
    }
    return 0;
  }

  double get _overallFraction => progress.clamp(0.0, 1.0).toDouble();

  double _textPercentAt(int paragraphIndex, int offset) =>
      _textReadingProgress?.at(paragraphIndex, offset) ?? 0;

  void _goToChapter(int index) {
    if (loading || _chapterCount <= 0) return;
    final target = index.clamp(0, _chapterCount - 1).toInt();
    if (target == _chapterIndex) return;
    if (!HyesMotion.reduced(context) && (book.isEpub || book.isText)) {
      setState(() {
        _chapterCueIndex = target;
        _chapterCueTitle = book.isEpub
            ? _epubDetails(target).$1
            : paragraphs[_textChapterStarts[target]].trim();
      });
      _chapterCueAnimation.forward(from: 0);
    }
    if (book.isEpub) {
      unawaited(epubController.jumpTo(EpubLocation(spineIndex: target)));
    } else if (book.isText) {
      _jumpToTextParagraph(_textChapterStarts[target]);
    } else {
      _jumpToPdfPage(target + 1);
    }
  }
  Timer? saveTimer;
  final Map<String, Timer> _settingWrites = {};
  final Map<String, double> _pendingSettingValues = {};
  bool settingUp = true;
  void _refreshReader() {
    if (mounted) setState(() {});
  }

  void _setFocusReading(bool enabled) {
    if (mounted) setState(() => focusReading = enabled);
  }

  void _showChrome() {
    if (focusReading && mounted) setState(() => focusReading = false);
    chromeTimer?.cancel();
    chromeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !focusReading) setState(() => focusReading = true);
    });
  }

  void _toggleChrome() {
    if (focusReading) {
      _showChrome();
    } else {
      chromeTimer?.cancel();
      if (mounted) setState(() => focusReading = true);
    }
  }

  void _animateBookmark({required bool added}) {
    if (HyesMotion.reduced(context)) return;
    _bookmarkWasAdded = added;
    if (added) {
      HyesMotion.stamped(context);
    } else {
      HyesMotion.selected(context);
    }
    _bookmarkAnimation.forward(from: 0);
  }

  void _readerPointerDown(PointerDownEvent event) {
    if (_readerTapPointer != null) return;
    _readerTapPointer = event.pointer;
    _readerTapStart = event.localPosition;
    _readerTapDragged = false;
  }

  void _readerPointerMove(PointerMoveEvent event) {
    if (event.pointer == _readerTapPointer && _readerTapStart != null &&
        (event.localPosition - _readerTapStart!).distance > 12) {
      _readerTapDragged = true;
    }
  }

  void _readerPointerUp(PointerUpEvent event) {
    if (event.pointer != _readerTapPointer) return;
    final start = _readerTapStart;
    final dragged = _readerTapDragged;
    _readerTapPointer = null;
    _readerTapStart = null;
    if (dragged || start == null) return;
    final size = MediaQuery.sizeOf(context);
    if (start.dx >= size.width / 3 && start.dx <= size.width * 2 / 3 &&
        start.dy > 70 && start.dy < size.height - 115) {
      _toggleChrome();
    }
  }

  void _readerPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _readerTapPointer) return;
    _readerTapPointer = null;
    _readerTapStart = null;
  }

  Future<void> _quickAdjustFont(double change) async {
    final value = (fontSize + change).clamp(14.0, 32.0);
    if (value == fontSize) return;
    setState(() => fontSize = value);
    final prefs = await SharedPreferences.getInstance();
    await _savePreference(prefs.setDouble(_appearanceKey('fontSize'), value));
  }

  Future<void> _quickToggleTheme() async {
    setState(() => paper = paper == 'dark' ? 'sepia' : 'dark');
    final prefs = await SharedPreferences.getInstance();
    await _savePreference(prefs.setString(_appearanceKey('paper'), paper));
  }

  String _appearanceKey(String name) =>
      readerPreferenceKey(name, book.id, bookLayoutOverride);

  void _saveSettingDebounced(SharedPreferences prefs,
      String field, double value) {
    final key = _appearanceKey(field);
    _pendingSettingValues[key] = value;
    _settingWrites[key]?.cancel();
    _settingWrites[key] = Timer(const Duration(milliseconds: 100), () {
      _settingWrites.remove(key);
      _pendingSettingValues.remove(key);
      unawaited(_savePreference(prefs.setDouble(key, value)));
    });
  }

  Future<void> _flushSettings() async {
    for (final timer in _settingWrites.values) { timer.cancel(); }
    _settingWrites.clear();
    final entries = Map<String, double>.from(_pendingSettingValues);
    _pendingSettingValues.clear();
    if (entries.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in entries.entries) {
      if (!await prefs.setDouble(entry.key, entry.value)) {
        throw const FormatException('阅读排版偏好保存失败');
      }
    }
  }

  void _loadAppearance(SharedPreferences prefs) {
    final appearance = loadReaderAppearance(prefs, book.id);
    fontSize = appearance.fontSize;
    lineHeight = appearance.lineHeight;
    contentWidth = appearance.contentWidth;
    paper = appearance.paper;
    paragraphSpacing = appearance.paragraphSpacing;
    eyeWarmth = appearance.eyeWarmth;
    justifyText = appearance.justifyText;
    fontKind = appearance.fontKind;
    if (!prefs.containsKey('fontSize') && !appearance.bookOverride &&
        (Platform.isAndroid || Platform.isIOS)) fontSize = 18;
    bookLayoutOverride = appearance.bookOverride;
    pageMode = prefs.getBool('hyes.reader.pageMode') ??
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  }

  void _jumpToTextParagraph(int index) {
    if (paragraphs.isEmpty) return;
    final target = index.clamp(0, paragraphs.length - 1).toInt();
    if (target == paragraph && textOffset == 0) return;
    if (!pageMode && !scrollController.isAttached) return;
    previousTextParagraph = paragraph;
    paragraph = target;
    textOffset = 0;
    progress = _textPercentAt(target, 0);
    if (pageMode) {
      textPagerKey.currentState?.jumpTo(TextPageCursor(target, 0));
    } else {
      scrollController.jumpTo(index: target);
    }
    _scheduleSave();
    _refreshReader();
  }

  /// Search uses the exact loaded stable paragraphs and UTF-16 offsets.
  /// Cancelling the dialog never changes saved reading progress.
  Future<void> _openReaderTextSearch() async {
    if (!book.isText || loading || failure != null || paragraphs.isEmpty) {
      return;
    }
    chromeTimer?.cancel();
    final result = await showGeneralDialog<ReaderTextHit>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _english ? 'Dismiss book search' : '关闭书内搜索',
      barrierColor: Colors.black.withValues(alpha: .60),
      transitionDuration: HyesMotion.duration(
          context, const Duration(milliseconds: 280)),
      pageBuilder: (context, _, _) => SafeArea(
        child: ReaderTextSearchDialog(
          paragraphs: paragraphs,
          english: _english,
        )),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: HyesMotion.reduced(context)
                  ? Offset.zero : const Offset(0, -.035),
              end: Offset.zero,
            ).animate(curved), child: child));
      },
    );
    if (!mounted || result == null) return;
    if (!pageMode && !scrollController.isAttached) return;
    final target = result.paragraph.clamp(0, paragraphs.length - 1);
    final offset = result.offset.clamp(0, paragraphs[target].length);
    previousTextParagraph = paragraph;
    paragraph = target;
    textOffset = pageMode ? offset : 0;
    progress = _textPercentAt(target, textOffset);
    if (pageMode) {
      textPagerKey.currentState?.jumpTo(TextPageCursor(target, offset));
    } else {
      scrollController.jumpTo(index: target);
    }
    _scheduleSave();
    _refreshReader();
  }

  void _onTextPagePosition(TextPageCursor cursor) {
    if (cursor.paragraph == paragraph && cursor.offset == textOffset) return;
    paragraph = cursor.paragraph;
    textOffset = cursor.offset;
    progress = _textPercentAt(paragraph, textOffset);
    _scheduleSave();
    _refreshReader();
  }

  Future<void> _togglePageMode() async {
    if (!book.isText && !book.isEpub) return;
    if (book.isEpub && epubController.isAttached) _saveEpubLocation();
    final previous = pageMode;
    final previousOffset = textOffset;
    setState(() {
      pageMode = !pageMode;
      if (!pageMode && book.isText) textOffset = 0;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('hyes.reader.pageMode', pageMode)) {
        throw const FormatException('未能保存翻页模式设置');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          pageMode = previous;
          textOffset = previousOffset;
        });
        _showMessage(_tr('阅读模式保存失败：') + error.toString());
      }
    }
  }

  void _turnReader(int direction) {
    if (loading || failure != null) return;
    if (book.isText) {
      if (pageMode) {
        if (direction > 0) {
          textPagerKey.currentState?.nextPage();
        } else {
          textPagerKey.currentState?.previousPage();
        }
      } else if (scrollController.isAttached) {
        final height = MediaQuery.sizeOf(context).height * .72;
        unawaited(offsetController.animateScroll(
          offset: direction * height,
          duration: HyesMotion.duration(context, HyesMotion.base),
          curve: HyesMotion.enter,
        ));
      }
    } else if (book.isPdf) {
      _jumpToPdfPage(pdfPage + direction);
    } else if (book.isEpub && epubController.isAttached) {
      if (epubFacingPages) {
        unawaited(epubController.turnScreen(direction));
      } else if (direction > 0) {
        unawaited(epubController.nextChapter());
      } else {
        unawaited(epubController.previousChapter());
      }
    }
  }

  void _advanceScreen(int direction) {
    if (book.isEpub && epubFacingPages) {
      _turnReader(direction);
      return;
    }
    if (!book.isEpub) {
      _turnReader(direction);
      return;
    }
    final root = _epubViewKey.currentContext;
    ScrollableState? vertical;
    if (root is Element) {
      void inspect(Element node) {
        if (node is StatefulElement && node.state is ScrollableState) {
          final scroll = node.state as ScrollableState;
          if (scroll.position.axis == Axis.vertical &&
              scroll.position.hasContentDimensions &&
              scroll.position.maxScrollExtent > 0) {
            vertical = scroll;
          }
        }
        node.visitChildren(inspect);
      }
      inspect(root);
    }
    final pos = vertical?.position;
    if (pos == null) {
      _turnReader(direction);
      return;
    }
    final target = (pos.pixels + direction * pos.viewportDimension * .82)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 2) {
      _turnReader(direction);
    } else {
      unawaited(pos.animateTo(target,
        duration: HyesMotion.duration(context, HyesMotion.base),
        curve: HyesMotion.enter));
    }
  }

  void _jumpToPdfPage(int page) {
    if (pdfCount < 1) return;
    final target = page.clamp(1, pdfCount).toInt();
    if (target == pdfPage) return;
    previousPdfPage = pdfPage;
    pdfPage = target;
    progress = pdfCount > 1 ? (target - 1) / (pdfCount - 1) : 0;
    pdfController.setCurrentPageNumber(target);
    _scheduleSave();
    _refreshReader();
  }

  @override
  void initState() {
    super.initState();
    _chapterCueAnimation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 440));
    _bookmarkAnimation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky).catchError((Object _) {}));
    }
    WidgetsBinding.instance.addObserver(this);
    book = widget.repository.byId(widget.bookId)!;
    paragraph = book.paragraphIndex;
    textOffset = book.textOffset;
    pdfPage = book.pdfPage;
    epubLocation = book.epubLocation;
    progress = book.progress;
    if (book.isText) positionListener.itemPositions.addListener(_onTextPosition);
    _configure();
  }

  Future<void> _configure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loadAppearance(prefs);
      if (book.isText) {
        final file = File(book.path);
        if (await file.length() > 20 * 1024 * 1024) {
          throw const FormatException('当前文字阅读限制为每本 20 MiB，请继续使用原版读取更大的文件');
        }
        final content = utf8.decode(await file.readAsBytes());
        paragraphs = splitTextIntoStableBlocks(content);
        if (paragraphs.isEmpty) paragraphs = ['（没有可显示的文字）'];
        _textReadingProgress = TextReadingProgress(paragraphs);
        _textChapterStarts = [0];
        for (var i = 1; i < paragraphs.length; i++) {
          if (TextPageLayouter.chapterHeading.hasMatch(paragraphs[i].trim())) {
            _textChapterStarts.add(i);
          }
        }
        paragraph = paragraph.clamp(0, paragraphs.length - 1).toInt();
        textOffset = textOffset.clamp(0, paragraphs[paragraph].length).toInt();
        progress = _textPercentAt(paragraph, textOffset);
      } else if (book.isEpub) {
        final epubFile = File(book.path);
        if (await epubFile.length() > 50 * 1024 * 1024) {
          throw const FormatException('此 Flutter EPUB 预览对单本文件限制为 50 MiB，原版书籍不受影响');
        }
        final originalBytes = await epubFile.readAsBytes();
        // Heavy ZIP inflate/re-encode runs off the UI isolate. On malformed
        // or encrypted archives retain the original read-only input.
        Uint8List renderedBytes;
        try {
          renderedBytes = await Isolate.run(
            () => normalizeEpubForReading(originalBytes));
        } catch (_) {
          // Some widget-test environments cannot spawn an isolate. Do not
          // silently bypass the display-only fix in those environments.
          // The original file on disk is never modified in either branch.
          renderedBytes = normalizeEpubForReading(originalBytes);
        }
        epubBook = EpubBook.fromBytes(renderedBytes, lenient: true);
        unawaited(_loadEpubProgress(book.path));
      }
    } on FormatException catch (error) {
      failure = '无法读取文件：' + error.message +
          '。此版本只直接解析 UTF-8 TXT / MD，原始文件并未修改。';
    } catch (error) {
      failure = '无法打开书籍：' + error.toString();
    } finally {
      settingUp = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadEpubProgress(String filePath) async {
    try {
      final weights = await epubBlockCountsFromFile(filePath);
      if (!mounted || weights.isEmpty) return;
      _epubBlockCounts = weights;
      final location = EpubLocation.tryDecode(epubLocation ?? '') ??
          epubController.location;
      progress = epubProgressFromBlocks(location, weights);
      _scheduleSave();
      _refreshReader();
    } catch (_) {
      // Reading is still usable when progress metadata cannot be obtained.
    }
  }

  void _onTextPosition() {
    if (settingUp || pageMode || paragraphs.isEmpty) return;
    final items = positionListener.itemPositions.value
        .where((pos) => pos.itemTrailingEdge > 0).toList();
    if (items.isEmpty) return;
    final first = items.map((pos) => pos.index).reduce(math.min);
    if (first == paragraph) return;
    paragraph = first;
    textOffset = 0;
    progress = _textPercentAt(first, 0);
    _scheduleSave();
    if (mounted) setState(() {});
  }

  void _scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 850), () {
      unawaited(_persist().catchError((Object error) {
        if (mounted) _showMessage(_tr('位置保存失败：') + error.toString());
      }));
    });
  }

  Future<void> _persist() async {
    final saved = widget.repository.byId(book.id);
    if (saved == null) return;
    await widget.repository.replace(saved.copyWith(
      progress: progress, paragraphIndex: paragraph,
      textOffset: textOffset,
      pdfPage: pdfPage, epubLocation: epubLocation,
    ));
  }

  void _saveEpubLocation([EpubLocation? location]) {
    final current = location ?? epubController.location;
    final encoded = current.encode();
    if (encoded.isNotEmpty && encoded != epubLocation) {
      epubLocation = encoded;
      final weights = _epubBlockCounts;
      if (weights != null && weights.isNotEmpty) {
        progress = epubProgressFromBlocks(current, weights);
      } else if (_chapterCount > 0) {
        final index = current.spineIndex.clamp(0, _chapterCount - 1);
        final blocks = _epubDetails(index).$2;
        progress = ((index +
            (current.elementIndex + current.fraction) /
                math.max(1, blocks)) / _chapterCount)
            .clamp(0.0, 1.0).toDouble();
      }
      _scheduleSave();
      if (pageMode && mounted) _refreshReader();
    }
  }

  Future<void> _exit() async {
    if (allowPop) return;
    saveTimer?.cancel();
    try {
      await _flushSettings();
    } catch (error) {
      _showMessage(_tr('排版偏好保存失败：') + error.toString());
      return;
    }
    if (book.isEpub) _saveEpubLocation();
    try {
      await _persist();
    } catch (error) {
      _showMessage(_tr('无法保存阅读位置：') + error.toString());
      return;
    }
    if (!mounted) return;
    setState(() => allowPop = true);
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (book.isEpub) _saveEpubLocation();
      saveTimer?.cancel();
      unawaited(_persist().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge).catchError((Object _) {}));
    }
    saveTimer?.cancel();
    for (final timer in _settingWrites.values) { timer.cancel(); }
    _chapterCueAnimation.dispose();
    _bookmarkAnimation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    chromeTimer?.cancel();
    if (book.isText) positionListener.itemPositions.removeListener(_onTextPosition);
    epubController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildReader(context);
}
