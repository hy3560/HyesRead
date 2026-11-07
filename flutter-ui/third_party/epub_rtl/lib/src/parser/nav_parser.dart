import 'package:xml/xml.dart';

import 'epub_models.dart';
import 'epub_path.dart';
import 'xml_utils.dart';

/// Parses an EPUB 3 navigation document located at [navPath].
EpubNavigation parseNavDocument(XmlDocument doc, String navPath) {
  var toc = <EpubNavItem>[];
  var landmarks = <EpubNavItem>[];
  var pageList = <EpubNavItem>[];
  for (final nav in doc.rootElement.descendantsNamed('nav')) {
    final types = (nav.attr('type') ?? '').split(RegExp(r'\s+'));
    final ol = nav.firstChildNamed('ol') ?? _firstDescendant(nav, 'ol');
    final items = ol == null ? <EpubNavItem>[] : _parseOl(ol, navPath);
    if (types.contains('toc') && toc.isEmpty) {
      toc = items;
    } else if (types.contains('landmarks') && landmarks.isEmpty) {
      landmarks = items;
    } else if (types.contains('page-list') && pageList.isEmpty) {
      pageList = items;
    }
  }
  return EpubNavigation(
    toc: toc,
    landmarks: landmarks,
    pageList: pageList,
    source: NavigationSource.navDocument,
  );
}

XmlElement? _firstDescendant(XmlElement e, String name) {
  for (final d in e.descendantElements) {
    if (d.local == name) return d;
  }
  return null;
}

List<EpubNavItem> _parseOl(XmlElement ol, String navPath) => [
      for (final li in ol.childrenNamed('li')) _parseLi(li, navPath),
    ];

EpubNavItem _parseLi(XmlElement li, String navPath) {
  final label = li.firstChildNamed('a') ?? li.firstChildNamed('span');
  final href = label?.local == 'a' ? label!.attr('href') : null;
  final nested = li.firstChildNamed('ol');
  return EpubNavItem(
    title: label?.cleanText ?? '',
    href: href == null ? null : EpubPath.resolve(navPath, href),
    type: label?.attr('type'),
    children: nested == null ? const [] : _parseOl(nested, navPath),
  );
}

/// Parses an EPUB 2 NCX located at [ncxPath]. [guide] becomes the
/// landmarks list.
EpubNavigation parseNcx(
  XmlDocument doc,
  String ncxPath, {
  List<EpubNavItem> guide = const [],
}) {
  final root = doc.rootElement;
  final navMap = root.firstChildNamed('navMap');
  final pageList = root.firstChildNamed('pageList');
  return EpubNavigation(
    toc: [
      for (final p in navMap?.childrenNamed('navPoint') ?? const <XmlElement>[])
        _parseNavPoint(p, ncxPath),
    ],
    pageList: [
      for (final p
          in pageList?.childrenNamed('pageTarget') ?? const <XmlElement>[])
        _parseNavPoint(p, ncxPath),
    ],
    landmarks: guide,
    source: NavigationSource.ncx,
  );
}

EpubNavItem _parseNavPoint(XmlElement point, String ncxPath) {
  final src = point.firstChildNamed('content')?.attr('src');
  return EpubNavItem(
    title: point.firstChildNamed('navLabel')?.cleanText ?? '',
    href: src == null ? null : EpubPath.resolve(ncxPath, src),
    children: [
      for (final c in point.childrenNamed('navPoint'))
        _parseNavPoint(c, ncxPath),
    ],
  );
}
