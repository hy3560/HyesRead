import 'package:xml/xml.dart';

import 'content_model.dart';

/// The CSS properties this package understands.
const supportedCssProperties = {
  'text-align',
  'font-style',
  'font-weight',
  'margin',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'text-indent',
  'direction',
  'display',
};

/// Parses a declaration block (`a: b; c: d`) into lower-case property names
/// and trimmed values, keeping only [supportedCssProperties]. The `margin`
/// shorthand is expanded.
Map<String, String> parseDeclarations(String text) {
  final out = <String, String>{};
  for (final part in text.split(';')) {
    final colon = part.indexOf(':');
    if (colon < 0) continue;
    final property = part.substring(0, colon).trim().toLowerCase();
    var value = part.substring(colon + 1).trim();
    value = value
        .replaceAll(RegExp(r'!\s*important', caseSensitive: false), '')
        .trim();
    if (!supportedCssProperties.contains(property) || value.isEmpty) continue;
    if (property == 'margin') {
      final v = value.split(RegExp(r'\s+'));
      final top = v[0];
      final right = v.length > 1 ? v[1] : top;
      final bottom = v.length > 2 ? v[2] : top;
      final left = v.length > 3 ? v[3] : right;
      out['margin-top'] = top;
      out['margin-right'] = right;
      out['margin-bottom'] = bottom;
      out['margin-left'] = left;
    } else {
      out[property] = value.toLowerCase();
    }
  }
  return out;
}

/// Parses a CSS length (`1.5em`, `12px`, `9pt`, `0`). Percentages, `auto`
/// and other units give null.
CssLength? parseCssLength(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(-?\d*\.?\d+)(em|rem|px|pt)?$')
      .firstMatch(value.trim().toLowerCase());
  if (m == null) return null;
  final number = double.parse(m.group(1)!);
  final unit = switch (m.group(2)) {
    'em' => CssUnit.em,
    'rem' => CssUnit.rem,
    'pt' => CssUnit.pt,
    'px' => CssUnit.px,
    _ => number == 0 ? CssUnit.px : null,
  };
  return unit == null ? null : CssLength(number, unit);
}

class _Compound {
  _Compound(this.tag, this.id, this.classes);
  final String? tag;
  final String? id;
  final List<String> classes;

  int get specificity =>
      (id == null ? 0 : 100) + classes.length * 10 + (tag == null ? 0 : 1);

  bool matches(XmlElement e) {
    if (tag != null && e.name.local.toLowerCase() != tag) return false;
    if (id != null && e.getAttribute('id') != id) return false;
    if (classes.isNotEmpty) {
      final own = (e.getAttribute('class') ?? '').split(RegExp(r'\s+'));
      if (!classes.every(own.contains)) return false;
    }
    return true;
  }
}

class _Rule {
  _Rule(this.compounds, this.declarations, this.order)
      : specificity = compounds.fold(0, (s, c) => s + c.specificity);
  final List<_Compound> compounds; // descendant chain, last is the subject
  final Map<String, String> declarations;
  final int order;
  final int specificity;

  bool matches(XmlElement e) {
    if (!compounds.last.matches(e)) return false;
    var i = compounds.length - 2;
    var node = e.parent;
    while (i >= 0 && node != null) {
      if (node is XmlElement && compounds[i].matches(node)) i--;
      node = node.parent;
    }
    return i < 0;
  }
}

final _compoundPattern = RegExp(r'^(\*|[a-zA-Z][\w-]*)?((?:[.#][\w-]+)*)$');

_Compound? _parseCompound(String text) {
  final m = _compoundPattern.firstMatch(text);
  if (m == null) return null;
  final tag = m.group(1);
  String? id;
  final classes = <String>[];
  for (final part in RegExp(r'[.#][\w-]+').allMatches(m.group(2) ?? '')) {
    final s = part.group(0)!;
    if (s.startsWith('#')) {
      id = s.substring(1);
    } else {
      classes.add(s.substring(1));
    }
  }
  if (tag == null && id == null && classes.isEmpty) return null;
  return _Compound(tag == '*' ? null : tag?.toLowerCase(), id, classes);
}

/// A tiny stylesheet: tag, class, id and descendant selectors over the
/// supported properties. Other selectors and at-rules are ignored.
class EpubStylesheet {
  final List<_Rule> _rules = [];
  int _order = 0;

  /// Adds the rules of [css].
  void add(String css) {
    final text = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    var i = 0;
    while (i < text.length) {
      final open = text.indexOf('{', i);
      if (open < 0) break;
      final prelude = text.substring(i, open).trim();
      final close = _matchingBrace(text, open);
      final body = text.substring(open + 1, close < 0 ? text.length : close);
      i = close < 0 ? text.length : close + 1;
      if (prelude.contains('@')) {
        // Statement at-rules such as @import end with ';' before a block.
        final semi = prelude.lastIndexOf(';');
        if (semi >= 0 && !prelude.substring(semi + 1).contains('@')) {
          _addRule(prelude.substring(semi + 1).trim(), body);
        }
        continue;
      }
      _addRule(prelude, body);
    }
  }

  void _addRule(String prelude, String body) {
    final declarations = parseDeclarations(body);
    if (declarations.isEmpty) return;
    for (final selector in prelude.split(',')) {
      final parts = selector.trim().split(RegExp(r'\s+'));
      final compounds = <_Compound>[];
      for (final p in parts) {
        final c = _parseCompound(p);
        if (c == null) {
          compounds.clear();
          break;
        }
        compounds.add(c);
      }
      if (compounds.isNotEmpty) {
        _rules.add(_Rule(compounds, declarations, _order++));
      }
    }
  }

  static int _matchingBrace(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// The declarations that apply to [element], cascaded by specificity and
  /// order, with the inline `style` attribute last.
  Map<String, String> declarationsFor(XmlElement element) {
    final matching = _rules.where((r) => r.matches(element)).toList()
      ..sort((a, b) => a.specificity != b.specificity
          ? a.specificity.compareTo(b.specificity)
          : a.order.compareTo(b.order));
    final out = <String, String>{};
    for (final r in matching) {
      out.addAll(r.declarations);
    }
    final inline = element.getAttribute('style');
    if (inline != null) out.addAll(parseDeclarations(inline));
    return out;
  }
}
