/// The category of an [EpubException].
enum EpubErrorKind {
  /// The bytes are not a readable zip archive.
  notZip,

  /// The `mimetype` entry is missing, not first, or not `application/epub+zip`.
  invalidMimetype,

  /// `META-INF/container.xml` is missing or names no package document.
  missingContainer,

  /// The package (OPF) document named by the container does not exist.
  missingPackage,

  /// An XML document in the book could not be parsed.
  malformedXml,

  /// A manifest item lacks a required attribute (id, href or media-type).
  invalidManifest,

  /// A spine `itemref` points at an id that is not in the manifest.
  missingManifestItem,

  /// Neither an EPUB 3 nav document nor an EPUB 2 NCX could be read.
  missingNavigation,

  /// The book, or the requested resource, is encrypted (DRM or font
  /// obfuscation). Encrypted books are not supported.
  encrypted,

  /// A spine index or resource that does not exist was requested.
  missingResource,
}

/// Thrown when an EPUB cannot be opened or read.
///
/// In lenient mode (`EpubBook.fromBytes(bytes, lenient: true)`) the parser
/// recovers from common real-world errors and records them in
/// `EpubBook.warnings` instead of throwing.
class EpubException implements Exception {
  /// Creates an exception of [kind] with a human readable [message].
  const EpubException(this.kind, this.message);

  /// What went wrong.
  final EpubErrorKind kind;

  /// A human readable description, naming the offending path when known.
  final String message;

  @override
  String toString() => 'EpubException(${kind.name}): $message';
}
