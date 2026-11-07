/// A `dc:creator` or `dc:contributor` entry.
class EpubCreator {
  /// Creates a creator.
  const EpubCreator(this.name, {this.role, this.fileAs});

  /// Display name.
  final String name;

  /// MARC relator code such as `aut` or `ill`, when given.
  final String? role;

  /// Sort form of the name, such as `Writer, Jane`.
  final String? fileAs;

  @override
  String toString() => 'EpubCreator($name, role: $role)';
}

/// A `dc:identifier` entry.
class EpubIdentifier {
  /// Creates an identifier.
  const EpubIdentifier(this.value, {this.id, this.scheme});

  /// The identifier text, such as an ISBN or `urn:uuid:...`.
  final String value;

  /// The XML `id` attribute.
  final String? id;

  /// The EPUB 2 `opf:scheme` attribute, or an EPUB 3 `identifier-type`
  /// refinement.
  final String? scheme;
}

/// Package metadata from the OPF `<metadata>` element.
class EpubMetadata {
  /// Creates metadata.
  const EpubMetadata({
    this.titles = const [],
    this.creators = const [],
    this.contributors = const [],
    this.languages = const [],
    this.identifiers = const [],
    this.uniqueIdentifier,
    this.publisher,
    this.date,
    this.description,
    this.modified,
    this.subjects = const [],
  });

  /// All `dc:title` values, main title first.
  final List<String> titles;

  /// `dc:creator` entries in document order.
  final List<EpubCreator> creators;

  /// `dc:contributor` entries in document order.
  final List<EpubCreator> contributors;

  /// `dc:language` values (BCP 47 tags).
  final List<String> languages;

  /// `dc:identifier` entries.
  final List<EpubIdentifier> identifiers;

  /// The identifier referenced by the package `unique-identifier` attribute.
  final String? uniqueIdentifier;

  /// `dc:publisher`.
  final String? publisher;

  /// `dc:date`, as written in the book.
  final String? date;

  /// `dc:description`.
  final String? description;

  /// EPUB 3 `dcterms:modified`.
  final String? modified;

  /// `dc:subject` values.
  final List<String> subjects;

  /// The main title, or an empty string.
  String get title => titles.isEmpty ? '' : titles.first;

  /// The primary language, or null.
  String? get language => languages.isEmpty ? null : languages.first;
}

/// An item of the OPF manifest.
class EpubManifestItem {
  /// Creates a manifest item.
  const EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties = const {},
    this.fallback,
  });

  /// Manifest id.
  final String id;

  /// Full, decoded path of the resource inside the zip.
  final String href;

  /// Media type, such as `application/xhtml+xml` or `image/png`.
  final String mediaType;

  /// EPUB 3 `properties`, such as `nav`, `cover-image` or `svg`.
  final Set<String> properties;

  /// Id of the fallback item, if any.
  final String? fallback;

  /// Whether this item is an (X)HTML content document.
  bool get isXhtml =>
      mediaType == 'application/xhtml+xml' || mediaType == 'text/html';

  /// Whether this item is an image.
  bool get isImage => mediaType.startsWith('image/');

  @override
  String toString() => 'EpubManifestItem($id, $href, $mediaType)';
}

/// The reading direction declared by the spine.
enum PageProgressionDirection {
  /// Left to right.
  ltr,

  /// Right to left, used by Arabic, Hebrew, Persian and Urdu books (and
  /// Japanese manga).
  rtl,

  /// Not declared; readers should pick a direction from the content.
  defaultDirection,
}

/// An `itemref` of the spine.
class EpubSpineItem {
  /// Creates a spine item.
  const EpubSpineItem({
    required this.idref,
    required this.item,
    this.linear = true,
    this.properties = const {},
  });

  /// The manifest id this entry refers to.
  final String idref;

  /// The manifest item.
  final EpubManifestItem item;

  /// False for `linear="no"` (auxiliary content such as footnotes).
  final bool linear;

  /// EPUB 3 itemref `properties`, such as `page-spread-right`.
  final Set<String> properties;
}

/// The OPF spine: the default reading order.
class EpubSpine {
  /// Creates a spine.
  const EpubSpine({
    this.items = const [],
    this.pageProgressionDirection = PageProgressionDirection.defaultDirection,
    this.tocId,
  });

  /// The reading order.
  final List<EpubSpineItem> items;

  /// The `page-progression-direction` attribute.
  final PageProgressionDirection pageProgressionDirection;

  /// The EPUB 2 `toc` attribute (manifest id of the NCX).
  final String? tocId;
}

/// Where the navigation was read from.
enum NavigationSource {
  /// The EPUB 3 navigation document.
  navDocument,

  /// The EPUB 2 NCX.
  ncx,

  /// No navigation could be read (lenient mode only).
  none,
}

/// An entry of a table of contents, landmarks list or page list.
class EpubNavItem {
  /// Creates an entry.
  const EpubNavItem({
    required this.title,
    this.href,
    this.type,
    this.children = const [],
  });

  /// Label text.
  final String title;

  /// Full path of the target inside the book, with an optional `#fragment`.
  /// Null for headings without a link.
  final String? href;

  /// `epub:type` for landmarks (for example `bodymatter`), or the guide
  /// reference type for EPUB 2.
  final String? type;

  /// Nested entries.
  final List<EpubNavItem> children;

  @override
  String toString() => 'EpubNavItem($title -> $href)';
}

/// Navigation structures of a book.
class EpubNavigation {
  /// Creates a navigation.
  const EpubNavigation({
    this.toc = const [],
    this.landmarks = const [],
    this.pageList = const [],
    this.source = NavigationSource.none,
  });

  /// Table of contents.
  final List<EpubNavItem> toc;

  /// Landmarks (EPUB 3) or guide references (EPUB 2).
  final List<EpubNavItem> landmarks;

  /// Print page list.
  final List<EpubNavItem> pageList;

  /// Which document the navigation came from.
  final NavigationSource source;
}
