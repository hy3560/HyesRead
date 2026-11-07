/// Helpers for paths inside an EPUB container.
///
/// Paths returned by this package are full zip entry names (no leading
/// slash, percent-decoded, `.` and `..` removed), optionally followed by
/// `#fragment`.
abstract final class EpubPath {
  static final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

  /// Whether [href] points outside the book (it has a URI scheme such as
  /// `https:` or `mailto:`).
  static bool isExternal(String href) => _scheme.hasMatch(href.trim());

  /// Resolves [href] relative to the document at [basePath].
  ///
  /// The query string is dropped and the fragment kept.
  static String resolve(String basePath, String href) {
    var ref = href.trim();
    String? fragment;
    final hash = ref.indexOf('#');
    if (hash >= 0) {
      fragment = ref.substring(hash + 1);
      ref = ref.substring(0, hash);
    }
    final query = ref.indexOf('?');
    if (query >= 0) ref = ref.substring(0, query);

    String path;
    if (ref.isEmpty) {
      path = withoutFragment(basePath);
    } else {
      ref = _decode(ref);
      if (ref.startsWith('/')) {
        path = normalize(ref);
      } else {
        path = normalize('${directory(withoutFragment(basePath))}$ref');
      }
    }
    return fragment == null || fragment.isEmpty ? path : '$path#$fragment';
  }

  /// Removes `.` and `..` segments, duplicate and leading slashes.
  static String normalize(String path) {
    final out = <String>[];
    for (final segment in path.replaceAll('\\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(segment);
    }
    return out.join('/');
  }

  /// The directory part of [path], with a trailing slash, or `''`.
  static String directory(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash + 1);
  }

  /// [href] without its `#fragment`.
  static String withoutFragment(String href) {
    final hash = href.indexOf('#');
    return hash < 0 ? href : href.substring(0, hash);
  }

  /// The fragment of [href], or null when there is none.
  static String? fragment(String href) {
    final hash = href.indexOf('#');
    if (hash < 0 || hash == href.length - 1) return null;
    return href.substring(hash + 1);
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } on ArgumentError {
      return s;
    } on FormatException {
      return s;
    }
  }
}
