/// A sentence together with the paragraph it came from.
class SplitSentence {
  const SplitSentence(this.text, this.paragraphIndex);

  final String text;
  final int paragraphIndex;

  @override
  String toString() => 'SplitSentence($paragraphIndex, $text)';
}

/// Never ends a sentence (titles, places, bibliographic markers).
const _nonTerminalAbbreviations = {
  'г', 'гг', 'ул', 'пр', 'пер', 'просп', 'пл', 'им', 'проф', 'акад', 'доц',
  'д-р', 'св', 'см', 'ср', 'рис', 'стр', 'гл', 'табл', 'напр', 'т', 'тов',
  'гр', 'обл', 'р', 'руб', 'коп', 'тыс', 'млн', 'млрд', 'ок', 'в', 'вв',
  'п', 'пп', 'др-', 'ген', 'полк', 'лейт', 'кап', 'мл', 'ст',
};

/// May end a sentence when the next word is capitalised ("и т. д. Он ...").
const _terminalAbbreviations = {'т.д', 'т.п', 'т.е', 'т.к', 'и др', 'др', 'пр', 'etc'};

const _closers = '»"”’\')]';
const _openers = '«"“‘(—–-[';
const _terminators = '.!?…';

/// Splits Russian prose into sentences. Paragraph breaks (newlines) always
/// end a sentence.
class SentenceSplitter {
  const SentenceSplitter();

  List<SplitSentence> split(String text) {
    final result = <SplitSentence>[];
    final paragraphs = text.split(RegExp(r'\r?\n+'));
    var index = 0;
    for (final raw in paragraphs) {
      final paragraph = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (paragraph.isEmpty) continue;
      for (final s in _splitParagraph(paragraph)) {
        result.add(SplitSentence(s, index));
      }
      index++;
    }
    return result;
  }

  List<String> _splitParagraph(String p) {
    final sentences = <String>[];
    var start = 0;
    var i = 0;
    while (i < p.length) {
      if (!_terminators.contains(p[i])) {
        i++;
        continue;
      }
      final termStart = i;
      while (i < p.length && _terminators.contains(p[i])) {
        i++;
      }
      final terminator = p.substring(termStart, i);
      while (i < p.length && _closers.contains(p[i])) {
        i++;
      }
      if (i >= p.length) break;
      if (p[i] != ' ') continue;
      var next = i;
      while (next < p.length && p[next] == ' ') {
        next++;
      }
      if (next >= p.length) break;
      if (_isBoundary(p, termStart, terminator, p[next])) {
        sentences.add(p.substring(start, i).trim());
        start = next;
      }
      i = next;
    }
    final tail = p.substring(start).trim();
    if (tail.isNotEmpty) sentences.add(tail);
    return sentences;
  }

  bool _isBoundary(String p, int termStart, String terminator, String nextCh) {
    final startsNew = _isUpper(nextCh) || _openers.contains(nextCh);
    if (terminator == '…') {
      return startsNew;
    }
    if (terminator != '.') {
      // "!" / "?" / "?!" end a sentence unless a lowercase word follows
      // directly (e.g. "Что?! — спросил он" is handled by the dash opener).
      return startsNew || _isDigit(nextCh);
    }
    if (!startsNew && !_isDigit(nextCh)) return false;
    final token = _lastToken(p, termStart);
    if (token.isEmpty) return true;
    final lower = token.toLowerCase();
    // Initials: "А. С. Пушкин"
    if (token.length == 1 && _isUpper(token)) return false;
    if (_terminalAbbreviations.contains(lower)) return _isUpper(nextCh);
    if (_nonTerminalAbbreviations.contains(lower)) return false;
    return true;
  }

  /// Last word-like token (letters, dots, hyphens) before [end].
  String _lastToken(String p, int end) {
    var i = end;
    while (i > 0 && _isTokenChar(p.codeUnitAt(i - 1))) {
      i--;
    }
    return p.substring(i, end);
  }

  static final _letter = RegExp(r'\p{L}', unicode: true);

  bool _isTokenChar(int unit) {
    if (unit == 0x2E || unit == 0x2D) return true; // '.' '-'
    if (unit < 0x80) return (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A;
    return _letter.hasMatch(String.fromCharCode(unit));
  }

  bool _isUpper(String ch) => ch != ch.toLowerCase() && ch == ch.toUpperCase();

  bool _isDigit(String ch) => RegExp(r'\d').hasMatch(ch);
}
