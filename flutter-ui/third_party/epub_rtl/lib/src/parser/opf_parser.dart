import 'package:xml/xml.dart';

import 'epub_exception.dart';
import 'epub_models.dart';
import 'epub_path.dart';
import 'xml_utils.dart';

/// Result of parsing the package document.
class OpfData {
  /// Creates the result.
  const OpfData({
    required this.version,
    required this.metadata,
    required this.manifest,
    required this.spine,
    required this.coverId,
    required this.guide,
  });

  /// Package `version` attribute.
  final String version;

  /// Metadata.
  final EpubMetadata metadata;

  /// Manifest by id, in document order.
  final Map<String, EpubManifestItem> manifest;

  /// Spine.
  final EpubSpine spine;

  /// Manifest id of the cover image, if declared.
  final String? coverId;

  /// EPUB 2 `<guide>` references.
  final List<EpubNavItem> guide;
}

/// Parses an OPF package document located at [opfPath].
///
/// Recoverable problems are passed to [warn] when [lenient] is true and
/// thrown as [EpubException] otherwise.
OpfData parseOpf(
  XmlDocument doc,
  String opfPath, {
  required bool lenient,
  required void Function(String) warn,
}) {
  void problem(EpubErrorKind kind, String message) {
    if (!lenient) throw EpubException(kind, message);
    warn(message);
  }

  final package = doc.rootElement;
  if (package.local != 'package') {
    throw EpubException(EpubErrorKind.malformedXml,
        '$opfPath: root element is <${package.local}>, expected <package>');
  }
  final version = package.attr('version') ?? '2.0';

  // Metadata ---------------------------------------------------------------
  final metadataEl = package.firstChildNamed('metadata');
  final metaEls = metadataEl == null
      ? const <XmlElement>[]
      : metadataEl.descendantElements.toList();
  // EPUB 3 refinements: id -> property -> value.
  final refines = <String, Map<String, String>>{};
  String? modified;
  String? coverId;
  for (final m in metaEls.where((e) => e.local == 'meta')) {
    final property = m.attr('property');
    final refinesAttr = m.attr('refines');
    if (property != null &&
        refinesAttr != null &&
        refinesAttr.startsWith('#')) {
      refines.putIfAbsent(refinesAttr.substring(1), () => {})[property] =
          m.cleanText;
    } else if (property == 'dcterms:modified') {
      modified = m.cleanText;
    } else if (m.attr('name') == 'cover') {
      coverId = m.attr('content');
    }
  }

  List<String> texts(String name) => [
        for (final e in metaEls.where((e) => e.local == name))
          if (e.cleanText.isNotEmpty) e.cleanText,
      ];

  EpubCreator creator(XmlElement e) {
    final r = refines[e.attr('id')] ?? const {};
    return EpubCreator(
      e.cleanText,
      role: e.attr('role') ?? r['role'],
      fileAs: e.attr('file-as') ?? r['file-as'],
    );
  }

  final uniqueId = package.attr('unique-identifier');
  final identifiers = <EpubIdentifier>[];
  String? uniqueIdentifier;
  for (final e in metaEls.where((e) => e.local == 'identifier')) {
    final id = e.attr('id');
    final value = e.cleanText;
    identifiers.add(EpubIdentifier(
      value,
      id: id,
      scheme: e.attr('scheme') ?? refines[id]?['identifier-type'],
    ));
    if (id != null && id == uniqueId) uniqueIdentifier = value;
  }

  String? first(String name) {
    final list = texts(name);
    return list.isEmpty ? null : list.first;
  }

  final metadata = EpubMetadata(
    titles: texts('title'),
    creators: [
      for (final e in metaEls.where((e) => e.local == 'creator')) creator(e)
    ],
    contributors: [
      for (final e in metaEls.where((e) => e.local == 'contributor')) creator(e)
    ],
    languages: texts('language'),
    identifiers: identifiers,
    uniqueIdentifier: uniqueIdentifier ??
        (identifiers.isEmpty ? null : identifiers.first.value),
    publisher: first('publisher'),
    date: first('date'),
    description: first('description'),
    modified: modified,
    subjects: texts('subject'),
  );

  // Manifest ---------------------------------------------------------------
  final manifest = <String, EpubManifestItem>{};
  final manifestEl = package.firstChildNamed('manifest');
  for (final e in manifestEl?.childrenNamed('item') ?? const <XmlElement>[]) {
    final id = e.attr('id');
    final href = e.attr('href');
    if (id == null || href == null) {
      problem(EpubErrorKind.invalidManifest,
          '$opfPath: manifest item without id or href (${e.toXmlString()})');
      continue;
    }
    final fullHref = EpubPath.withoutFragment(EpubPath.resolve(opfPath, href));
    var mediaType = e.attr('media-type')?.trim().toLowerCase();
    final guessed = guessMediaType(fullHref);
    if (mediaType == null || mediaType.isEmpty) {
      problem(EpubErrorKind.invalidManifest,
          '$opfPath: manifest item "$id" ($href) has no media-type');
      mediaType = guessed ?? 'application/octet-stream';
    } else if (lenient &&
        !_knownMediaTypes.contains(mediaType) &&
        guessed != null &&
        guessed != mediaType) {
      warn(
          '$opfPath: unknown media-type "$mediaType" for "$id" ($href); using $guessed');
      mediaType = guessed;
    }
    final properties = (e.attr('properties') ?? '')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet();
    if (properties.contains('cover-image')) coverId ??= id;
    manifest[id] = EpubManifestItem(
      id: id,
      href: fullHref,
      mediaType: mediaType,
      properties: properties,
      fallback: e.attr('fallback'),
    );
  }
  // EPUB 3 cover-image wins over the EPUB 2 meta when both exist.
  for (final item in manifest.values) {
    if (item.properties.contains('cover-image')) coverId = item.id;
  }

  // Spine ------------------------------------------------------------------
  final spineEl = package.firstChildNamed('spine');
  final items = <EpubSpineItem>[];
  for (final e in spineEl?.childrenNamed('itemref') ?? const <XmlElement>[]) {
    final idref = e.attr('idref') ?? '';
    final item = manifest[idref];
    if (item == null) {
      problem(EpubErrorKind.missingManifestItem,
          '$opfPath: spine itemref "$idref" is not in the manifest');
      continue;
    }
    items.add(EpubSpineItem(
      idref: idref,
      item: item,
      linear: e.attr('linear')?.trim() != 'no',
      properties: (e.attr('properties') ?? '')
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toSet(),
    ));
  }
  final ppd = switch (
      spineEl?.attr('page-progression-direction')?.trim().toLowerCase()) {
    'rtl' => PageProgressionDirection.rtl,
    'ltr' => PageProgressionDirection.ltr,
    _ => PageProgressionDirection.defaultDirection,
  };

  // Guide (EPUB 2) ----------------------------------------------------------
  final guide = <EpubNavItem>[
    for (final r
        in package.firstChildNamed('guide')?.childrenNamed('reference') ??
            const <XmlElement>[])
      if (r.attr('href') != null)
        EpubNavItem(
          title: r.attr('title') ?? r.attr('type') ?? '',
          href: EpubPath.resolve(opfPath, r.attr('href')!),
          type: r.attr('type'),
        ),
  ];

  return OpfData(
    version: version,
    metadata: metadata,
    manifest: manifest,
    spine: EpubSpine(
        items: items,
        pageProgressionDirection: ppd,
        tocId: spineEl?.attr('toc')),
    coverId: manifest.containsKey(coverId) ? coverId : null,
    guide: guide,
  );
}

const _knownMediaTypes = {
  'application/xhtml+xml',
  'text/html',
  'application/x-dtbncx+xml',
  'text/css',
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'image/svg+xml',
  'font/otf',
  'font/ttf',
  'font/woff',
  'font/woff2',
  'application/font-sfnt',
  'application/vnd.ms-opentype',
  'application/font-woff',
  'application/x-font-ttf',
  'application/x-font-otf',
  'application/javascript',
  'text/javascript',
  'application/smil+xml',
  'audio/mpeg',
  'audio/mp4',
  'video/mp4',
  'application/pls+xml',
  'application/oebps-package+xml',
};

/// Guesses a media type from the file extension of [path].
String? guessMediaType(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'xhtml' || 'xht' || 'html' || 'htm' => 'application/xhtml+xml',
    'ncx' => 'application/x-dtbncx+xml',
    'css' => 'text/css',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'svg' => 'image/svg+xml',
    'otf' => 'font/otf',
    'ttf' => 'font/ttf',
    'woff' => 'font/woff',
    'woff2' => 'font/woff2',
    'js' => 'application/javascript',
    'smil' => 'application/smil+xml',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    _ => null,
  };
}
