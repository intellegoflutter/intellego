import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class ExtractedText {
  const ExtractedText({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

const _noiseTags = [
  'script',
  'style',
  'noscript',
  'nav',
  'header',
  'footer',
  'aside',
  'form',
  'iframe',
  'svg',
  'button',
  'select',
];

/// Pulls the main readable text out of an HTML page: finds the element whose
/// paragraphs hold the most text and returns those paragraphs.
class HtmlTextExtractor {
  const HtmlTextExtractor();

  ExtractedText extract(String htmlSource) {
    final doc = html_parser.parse(htmlSource);
    for (final tag in _noiseTags) {
      for (final e in doc.querySelectorAll(tag)) {
        e.remove();
      }
    }
    final title = _title(doc);
    final container = _bestContainer(doc);
    final blocks =
        container
            ?.querySelectorAll('p, h1, h2, h3, blockquote')
            .where((e) => !_hasBlockAncestorInside(e, container)) ??
        const <Element>[];
    final paragraphs = <String>[];
    for (final b in blocks) {
      final t = _clean(b.text);
      if (t.isNotEmpty) paragraphs.add(t);
    }
    return ExtractedText(title: title, paragraphs: paragraphs);
  }

  String _title(Document doc) {
    final h1 = doc.querySelector('h1');
    final t = h1?.text ?? doc.querySelector('title')?.text ?? '';
    return _clean(t);
  }

  Element? _bestContainer(Document doc) {
    final explicit = doc.querySelector('article') ?? doc.querySelector('main');
    final scores = <Element, int>{};
    for (final p in doc.querySelectorAll('p')) {
      final parent = p.parent;
      if (parent == null) continue;
      scores.update(
        parent,
        (v) => v + _clean(p.text).length,
        ifAbsent: () => _clean(p.text).length,
      );
    }
    if (explicit != null && (scores[explicit] ?? 0) > 0) return explicit;
    if (scores.isEmpty) return explicit ?? doc.body;
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Skip blockquote/heading nodes nested inside another selected block
  /// to avoid duplicated text.
  bool _hasBlockAncestorInside(Element e, Element container) {
    for (var p = e.parent; p != null && p != container; p = p.parent) {
      if (p.localName == 'blockquote') return true;
    }
    return false;
  }

  String _clean(String s) => s
      .replaceAll(' ', ' ')
      .replaceAll('­', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
