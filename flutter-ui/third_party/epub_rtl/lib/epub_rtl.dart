/// Pure-Flutter EPUB 2/3 parser and reader with right-to-left support.
///
/// Open a book with [EpubBook.fromBytes] or [EpubBook.openFile], then show it
/// with `EpubReaderView`.
library;

export 'src/parser/epub_book.dart' show EpubBook, isRtlLanguage;
export 'src/parser/epub_exception.dart';
export 'src/parser/epub_models.dart';
export 'src/parser/epub_path.dart';
export 'src/content/chapter_parser.dart' show EpubChapter, detectDirection;
export 'src/content/content_model.dart';
export 'src/reader/epub_location.dart';
export 'src/reader/reader_controller.dart';
export 'src/reader/reader_settings.dart';
export 'src/reader/reader_view.dart';
export 'src/reader/toc_drawer.dart';
export 'src/render/block_view.dart';
