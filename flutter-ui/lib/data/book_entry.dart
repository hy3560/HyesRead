/// Metadata for a book imported into this application's library.
class BookEntry {
  const BookEntry({
    required this.id, required this.title, required this.fileName,
    required this.format, required this.path, required this.importedAt,
    this.lastOpenedAt, this.progress = 0, this.paragraphIndex = 0,
    this.textOffset = 0,
    this.pdfPage = 1, this.epubCfi, this.epubLocation, this.textBookmarks = const [],
    this.pdfBookmarks = const [], this.epubBookmarks = const [],
    this.archived = false, this.favorite = false,
  });
  final String id, title, fileName, format, path;
  final int importedAt, paragraphIndex, textOffset, pdfPage;
  final int? lastOpenedAt;
  final double progress;
  final String? epubCfi;
  /// epub_rtl serialized location; NOT equivalent to an EPUB CFI.
  final String? epubLocation;
  final List<int> textBookmarks, pdfBookmarks;
  final List<String> epubBookmarks;
  final bool archived, favorite;

  bool get isText => format == 'txt' || format == 'md';
  bool get isEpub => format == 'epub';
  bool get isPdf => format == 'pdf';
  bool get canRead => isText || isEpub || isPdf;
  // Opening a book is a start, even before the first page is turned.
  bool get hasReading => lastOpenedAt != null || progress > 0 || paragraphIndex > 0 ||
      textOffset > 0 ||
      pdfPage > 1 || (epubCfi != null && epubCfi!.isNotEmpty) ||
      (epubLocation != null && epubLocation!.isNotEmpty);
  static const supported = <String>{
    'txt', 'md', 'epub', 'pdf', 'mobi', 'azw3', 'kf8', 'fb2', 'fbz', 'cbz',
  };

  BookEntry copyWith({
    String? title, int? lastOpenedAt, double? progress,
    int? paragraphIndex, int? textOffset, int? pdfPage,
    String? epubCfi, String? epubLocation,
    List<int>? textBookmarks, List<int>? pdfBookmarks,
    List<String>? epubBookmarks, bool? archived, bool? favorite,
  }) => BookEntry(
    id: id, title: title ?? this.title, fileName: fileName,
    format: format, path: path, importedAt: importedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    progress: progress ?? this.progress,
    paragraphIndex: paragraphIndex ?? this.paragraphIndex,
    textOffset: textOffset ?? this.textOffset,
    pdfPage: pdfPage ?? this.pdfPage, epubCfi: epubCfi ?? this.epubCfi,
    epubLocation: epubLocation ?? this.epubLocation,
    textBookmarks: textBookmarks ?? this.textBookmarks,
    pdfBookmarks: pdfBookmarks ?? this.pdfBookmarks,
    epubBookmarks: epubBookmarks ?? this.epubBookmarks,
    archived: archived ?? this.archived,
    favorite: favorite ?? this.favorite,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'title': title, 'fileName': fileName, 'format': format,
    'path': path, 'importedAt': importedAt, 'lastOpenedAt': lastOpenedAt,
    'progress': progress, 'paragraphIndex': paragraphIndex,
    'textOffset': textOffset,
    'pdfPage': pdfPage, 'epubCfi': epubCfi, 'epubLocation': epubLocation,
    'textBookmarks': textBookmarks,
    'pdfBookmarks': pdfBookmarks, 'epubBookmarks': epubBookmarks,
    'archived': archived, 'favorite': favorite,
  };

  factory BookEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'], path = json['path'], format = json['format'];
    if (id is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        path is! String || format is! String || !supported.contains(format)) {
      throw const FormatException('书库记录字段无效');
    }
    final value = (json['progress'] is num)
        ? (json['progress'] as num).toDouble() : 0.0;
    return BookEntry(
      id: id, path: path, format: format,
      title: (json['title'] as String?) ?? (json['fileName'] as String? ?? '未命名'),
      fileName: (json['fileName'] as String?) ?? '未命名',
      importedAt: (json['importedAt'] as num?)?.toInt() ?? 0,
      lastOpenedAt: (json['lastOpenedAt'] as num?)?.toInt(),
      progress: value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0,
      paragraphIndex: ((json['paragraphIndex'] as num?)?.toInt() ?? 0).clamp(0, 100000000).toInt(),
      textOffset: ((json['textOffset'] as num?)?.toInt() ?? 0).clamp(0, 2000000).toInt(),
      pdfPage: ((json['pdfPage'] as num?)?.toInt() ?? 1).clamp(1, 100000000).toInt(),
      epubCfi: json['epubCfi'] as String?,
      epubLocation: json['epubLocation'] as String?,
      textBookmarks: (json['textBookmarks'] as List<dynamic>? ?? [])
          .whereType<num>().map((e) => e.toInt()).where((n) => n >= 0).toList(),
      pdfBookmarks: (json['pdfBookmarks'] as List<dynamic>? ?? [])
          .whereType<num>().map((e) => e.toInt()).where((n) => n > 0).toList(),
      epubBookmarks: (json['epubBookmarks'] as List<dynamic>? ?? [])
          .whereType<String>().toList(),
      archived: json['archived'] == true,
      favorite: json['favorite'] == true,
    );
  }
}
