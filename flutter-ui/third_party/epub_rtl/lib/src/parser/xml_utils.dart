import 'package:xml/xml.dart';

import 'epub_exception.dart';

/// Parses [text] as XML, throwing a [EpubException] naming [path] on
/// failure. HTML named entities (`&nbsp;` and friends) are accepted because
/// real-world content documents often use them without a DTD.
XmlDocument parseXml(String text, String path) {
  try {
    return XmlDocument.parse(
      text,
      entityMapping: const XmlDefaultEntityMapping.html5(),
    );
  } on XmlException catch (e) {
    throw EpubException(
        EpubErrorKind.malformedXml, 'Malformed XML in $path: $e');
  }
}

/// Namespace-agnostic helpers: EPUBs in the wild get prefixes wrong often.
extension XmlElementX on XmlElement {
  /// The local (unprefixed) element name.
  String get local => name.local;

  /// Child elements with local name [localName].
  Iterable<XmlElement> childrenNamed(String localName) =>
      childElements.where((e) => e.name.local == localName);

  /// The first child element with local name [localName].
  XmlElement? firstChildNamed(String localName) {
    for (final e in childElements) {
      if (e.name.local == localName) return e;
    }
    return null;
  }

  /// Descendant elements with local name [localName], in document order.
  Iterable<XmlElement> descendantsNamed(String localName) =>
      descendantElements.where((e) => e.name.local == localName);

  /// The value of the first attribute with local name [localName],
  /// preferring an unprefixed attribute.
  String? attr(String localName) {
    String? prefixed;
    for (final a in attributes) {
      if (a.name.local != localName) continue;
      if (a.name.prefix == null) return a.value;
      prefixed ??= a.value;
    }
    return prefixed;
  }

  /// Text content with whitespace collapsed and trimmed.
  String get cleanText => innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
}
