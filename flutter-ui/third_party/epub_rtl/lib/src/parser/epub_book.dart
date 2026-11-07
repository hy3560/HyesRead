import 'dart:typed_data';

import 'epub_exception.dart';
import 'epub_models.dart';
import 'epub_path.dart';
import 'epub_zip.dart';
import 'nav_parser.dart';
import 'opf_parser.dart';
import 'xml_utils.dart';

/// Language subtags written right to left.
const Set<String> rtlLanguages = {
  'ar', 'arc', 'ckb', 'dv', 'fa', 'he', 'iw', 'ps', 'sd', 'syr', 'ug', 'ur',
  'yi', //
};

/// Whether the BCP 47 [languageTag] is normally written right to left.
bool isRtlLanguage(String? languageTag) {
  if (languageTag == null || languageTag.isEmpty) return false;
  return rtlLanguages
      .contains(languageTag.split(RegExp('[-_]')).first.toLowerCase());
}

const _fontObfuscationAlgorithms = {
  'http://www.idpf.org/2008/embedding',
  'http://ns.adobe.com/pdf/enc#RC',
};

/// An opened EPUB 2 or EPUB 3 book.
///
/// Opening reads only the zip directory, the container, the package
/// document and the navigation document. Chapters and resources are
/// inflated from the zip each time they are requested and are not cached.
class EpubBook {
  EpubBook._(this._zip, {required this.lenient}) {
    _open();
  }

  /// Opens a book held in memory.
  ///
  /// Throws [EpubException] for malformed or encrypted books. With
  /// [lenient], common real-world errors (mimetype missing or not first,
  /// missing NCX or nav document, manifest items without a media type,
  /// unknown media types, dangling spine references, wrong letter case in
  /// paths) are recorded in [warnings] instead.
  factory EpubBook.fromBytes(List<int> bytes, {bool lenient = false}) =>
      EpubBook._(EpubZip.fromBytes(bytes), lenient: lenient);

  /// Opens a book from a file on disk. Entries are read from the file on
  /// demand, so large books do not need to fit in memory. Not available on
  /// the web. Call [close] when done.
  factory EpubBook.openFile(String path, {bool lenient = false}) =>
      EpubBook._(EpubZip.fromFile(path), lenient: lenient);

  final EpubZip _zip;

  /// Whether the book was opened in lenient mode.
  final bool lenient;

  /// Problems that lenient mode recovered from.
  final List<String> warnings = [];

  late final String _packagePath;
  late final OpfData _opf;
  late final EpubNavigation _navigation;
  final Set<String> _encrypted = {};
  late final Map<String, EpubManifestItem> _itemsByHref;

  /// Full path of the package (OPF) document.
  String get packagePath => _packagePath;

  /// Package `version` attribute, such as `2.0` or `3.0`.
  String get version => _opf.version;

  /// Package metadata.
  EpubMetadata get metadata => _opf.metadata;

  /// Manifest items by id, in document order.
  Map<String, EpubManifestItem> get manifest => _opf.manifest;

  /// The reading order and its `page-progression-direction`.
  EpubSpine get spine => _opf.spine;

  /// Table of contents, landmarks and page list.
  EpubNavigation get navigation => _navigation;

  /// The cover image item, if declared.
  EpubManifestItem? get coverItem =>
      _opf.coverId == null ? null : manifest[_opf.coverId];

  /// Paths listed in `META-INF/encryption.xml` (lenient mode only; strict
  /// mode refuses such books).
  Set<String> get encryptedResources => Set.unmodifiable(_encrypted);

  /// Whether the book reads right to left: the spine says `rtl`, or it says
  /// nothing and the primary language is an RTL language.
  bool get isRtl => switch (spine.pageProgressionDirection) {
        PageProgressionDirection.rtl => true,
        PageProgressionDirection.ltr => false,
        PageProgressionDirection.defaultDirection =>
          isRtlLanguage(metadata.language),
      };

  void _problem(EpubErrorKind kind, String message) {
    if (!lenient) throw EpubException(kind, message);
    warnings.add(message);
  }

  void _open() {
    _checkMimetype();
    _checkEncryption();

    final container = _readText('META-INF/container.xml');
    if (container == null) {
      throw const EpubException(
          EpubErrorKind.missingContainer, 'META-INF/container.xml is missing');
    }
    final rootfile = parseXml(container, 'META-INF/container.xml')
        .rootElement
        .descendantsNamed('rootfile')
        .where(
          (e) =>
              (e.attr('media-type') ?? 'application/oebps-package+xml') ==
              'application/oebps-package+xml',
        );
    final fullPath = rootfile.isEmpty ? null : rootfile.first.attr('full-path');
    if (fullPath == null || fullPath.isEmpty) {
      throw const EpubException(EpubErrorKind.missingContainer,
          'META-INF/container.xml names no package document');
    }
    final opfName = _find(EpubPath.normalize(fullPath));
    final opfText = opfName == null ? null : _zip.readString(opfName);
    if (opfName == null || opfText == null) {
      throw EpubException(EpubErrorKind.missingPackage,
          'Package document "$fullPath" is missing');
    }
    _packagePath = opfName;
    _opf = parseOpf(parseXml(opfText, opfName), opfName,
        lenient: lenient, warn: warnings.add);
    _itemsByHref = {for (final item in manifest.values) item.href: item};
    _navigation = _readNavigation();
  }

  void _checkMimetype() {
    final names = _zip.names;
    if (!names.contains('mimetype')) {
      _problem(EpubErrorKind.invalidMimetype, 'The mimetype entry is missing');
      return;
    }
    if (names.first != 'mimetype') {
      _problem(EpubErrorKind.invalidMimetype,
          'The mimetype entry is not the first entry of the zip');
    }
    final value = _zip.readString('mimetype')?.trim();
    if (value != 'application/epub+zip') {
      _problem(EpubErrorKind.invalidMimetype,
          'The mimetype entry is "$value", expected "application/epub+zip"');
    }
  }

  void _checkEncryption() {
    final name = _find('META-INF/encryption.xml');
    if (name == null) return;
    final text = _zip.readString(name) ?? '';
    final doc = parseXml(text, name);
    final drm = <String>[];
    final fonts = <String>[];
    for (final data in doc.rootElement.descendantsNamed('EncryptedData')) {
      final algorithm =
          data.firstChildNamed('EncryptionMethod')?.attr('Algorithm') ?? '';
      final uri =
          data.descendantsNamed('CipherReference').firstOrNull?.attr('URI');
      if (uri == null) continue;
      final path = EpubPath.resolve('', uri);
      (_fontObfuscationAlgorithms.contains(algorithm) ? fonts : drm).add(path);
    }
    if (drm.isNotEmpty) {
      throw EpubException(
        EpubErrorKind.encrypted,
        'This book is encrypted (DRM) and cannot be opened. Encrypted resources: ${drm.join(', ')}',
      );
    }
    if (fonts.isNotEmpty) {
      _problem(
        EpubErrorKind.encrypted,
        'META-INF/encryption.xml lists obfuscated fonts, which are not supported: ${fonts.join(', ')}',
      );
      _encrypted.addAll(fonts);
    }
  }

  EpubNavigation _readNavigation() {
    final navItem =
        manifest.values.where((i) => i.properties.contains('nav')).firstOrNull;
    if (navItem != null) {
      final text = readString(navItem.href);
      if (text != null) {
        return parseNavDocument(parseXml(text, navItem.href), navItem.href);
      }
      _problem(EpubErrorKind.missingNavigation,
          'Navigation document ${navItem.href} is missing');
    }
    final ncxItem = manifest[spine.tocId] ??
        manifest.values
            .where((i) => i.mediaType == 'application/x-dtbncx+xml')
            .firstOrNull;
    if (ncxItem != null) {
      final text = readString(ncxItem.href);
      if (text != null) {
        return parseNcx(parseXml(text, ncxItem.href), ncxItem.href,
            guide: _opf.guide);
      }
      _problem(
          EpubErrorKind.missingNavigation, 'NCX ${ncxItem.href} is missing');
    } else if (navItem == null) {
      _problem(EpubErrorKind.missingNavigation,
          'The book has neither a nav document nor an NCX');
    }
    return EpubNavigation(landmarks: _opf.guide);
  }

  String? _find(String path) => _zip.find(path, ignoreCase: lenient);

  String? _readText(String path) {
    final name = _find(path);
    return name == null ? null : _zip.readString(name);
  }

  /// Whether the zip contains [href] (a full path; a `#fragment` is ignored).
  bool contains(String href) => _find(EpubPath.withoutFragment(href)) != null;

  /// Reads the resource at [href] (a full path inside the zip; a
  /// `#fragment` is ignored). Returns null when it does not exist.
  ///
  /// Throws [EpubException] for encrypted resources.
  Uint8List? readBytes(String href) {
    final path = EpubPath.withoutFragment(href);
    if (_encrypted.contains(path)) {
      throw EpubException(
          EpubErrorKind.encrypted, '$path is encrypted and cannot be read');
    }
    final name = _find(path);
    return name == null ? null : _zip.read(name);
  }

  /// Reads the resource at [href] as UTF-8 text, or null when missing.
  String? readString(String href) {
    final path = EpubPath.withoutFragment(href);
    if (_encrypted.contains(path)) {
      throw EpubException(
          EpubErrorKind.encrypted, '$path is encrypted and cannot be read');
    }
    final name = _find(path);
    return name == null ? null : _zip.readString(name);
  }

  /// The XHTML source of the spine item at [spineIndex].
  ///
  /// Throws [EpubException] when the index or the file does not exist.
  String chapterHtml(int spineIndex) {
    if (spineIndex < 0 || spineIndex >= spine.items.length) {
      throw EpubException(EpubErrorKind.missingResource,
          'Spine index $spineIndex is out of range');
    }
    final href = spine.items[spineIndex].item.href;
    final text = readString(href);
    if (text == null) {
      throw EpubException(
          EpubErrorKind.missingResource, 'Chapter file $href is missing');
    }
    return text;
  }

  /// The manifest item whose full path is [href] (fragment ignored).
  EpubManifestItem? itemByHref(String href) {
    final path = EpubPath.withoutFragment(href);
    final exact = _itemsByHref[path];
    if (exact != null || !lenient) return exact;
    final lower = path.toLowerCase();
    return _itemsByHref.values
        .where((i) => i.href.toLowerCase() == lower)
        .firstOrNull;
  }

  /// The spine index of the document [href] points into, or -1.
  int spineIndexOfHref(String href) {
    final item = itemByHref(href);
    if (item == null) return -1;
    return spine.items.indexWhere((s) => s.item.id == item.id);
  }

  /// Releases the file handle of a book opened with [EpubBook.openFile].
  Future<void> close() => _zip.close();
}
