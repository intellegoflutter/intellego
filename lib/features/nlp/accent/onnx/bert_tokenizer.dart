import 'dart:convert';

/// Result of encoding text for a BERT-style model.
class BertEncoding {
  BertEncoding(this.ids, this.typeIds, this.tokenStarts, this.isContinuation);

  final List<int> ids;
  final List<int> typeIds;

  /// Source offset (UTF-16) where each token's basic token starts, -1 for
  /// special tokens.
  final List<int> tokenStarts;

  /// True for "##" word pieces that continue the previous token.
  final List<bool> isContinuation;
}

final _punctuation = RegExp(r'\p{P}', unicode: true);
final _control = RegExp(r'\p{C}', unicode: true);
final _space = RegExp(r'\p{Zs}', unicode: true);

/// Cased WordPiece tokenizer equivalent to HuggingFace `BertTokenizer` /
/// `DistilBertTokenizer` with `do_lower_case=false`, `strip_accents=null`.
class BertTokenizer {
  BertTokenizer(this._vocab, {Map<String, int> addedTokens = const {}})
      : _added = addedTokens {
    _unk = _vocab['[UNK]']!;
    _cls = _vocab['[CLS]']!;
    _sep = _vocab['[SEP]']!;
    if (_added.isNotEmpty) {
      final alternatives = (_added.keys.toList()
            ..sort((a, b) => b.length.compareTo(a.length)))
          .map(RegExp.escape)
          .join('|');
      _addedPattern = RegExp(alternatives);
    }
  }

  factory BertTokenizer.fromVocabText(String vocabText,
      {Map<String, int> addedTokens = const {}}) {
    final vocab = <String, int>{};
    var i = 0;
    for (final line in const LineSplitter().convert(vocabText)) {
      vocab[line] = i++;
    }
    return BertTokenizer(vocab, addedTokens: addedTokens);
  }

  static const maxLength = 512;
  static const _maxCharsPerWord = 100;

  final Map<String, int> _vocab;
  final Map<String, int> _added;
  RegExp? _addedPattern;
  late final int _unk, _cls, _sep;

  /// `[CLS] text [SEP]`
  BertEncoding encode(String text) {
    final ids = <int>[_cls];
    final starts = <int>[-1];
    final cont = <bool>[false];
    _tokenizeInto(text, ids, starts, cont, budget: maxLength - 2);
    ids.add(_sep);
    starts.add(-1);
    cont.add(false);
    return BertEncoding(ids, List.filled(ids.length, 0), starts, cont);
  }

  /// `[CLS] a [SEP] b [SEP]`; [a] is truncated first when too long.
  BertEncoding encodePair(String a, String b) {
    final bIds = <int>[], bStarts = <int>[], bCont = <bool>[];
    _tokenizeInto(b, bIds, bStarts, bCont, budget: maxLength ~/ 2);
    final aIds = <int>[], aStarts = <int>[], aCont = <bool>[];
    _tokenizeInto(a, aIds, aStarts, aCont, budget: maxLength - 3 - bIds.length);
    final ids = [_cls, ...aIds, _sep, ...bIds, _sep];
    final starts = [-1, ...aStarts, -1, ...bStarts, -1];
    final cont = [false, ...aCont, false, ...bCont, false];
    final types = [
      for (var i = 0; i < ids.length; i++) i <= aIds.length + 1 ? 0 : 1
    ];
    return BertEncoding(ids, types, starts, cont);
  }

  void _tokenizeInto(String text, List<int> ids, List<int> starts,
      List<bool> cont, {required int budget}) {
    var pos = 0;
    final pattern = _addedPattern;
    if (pattern != null) {
      for (final m in pattern.allMatches(text)) {
        _basic(text.substring(pos, m.start), pos, ids, starts, cont);
        ids.add(_added[m.group(0)!]!);
        starts.add(m.start);
        cont.add(false);
        pos = m.end;
      }
    }
    _basic(text.substring(pos), pos, ids, starts, cont);
    if (ids.length > budget) {
      ids.length = budget;
      starts.length = budget;
      cont.length = budget;
    }
  }

  void _basic(String text, int base, List<int> ids, List<int> starts,
      List<bool> cont) {
    var wordStart = -1;
    final word = StringBuffer();
    void flush() {
      if (word.isEmpty) return;
      _wordPiece(word.toString(), base + wordStart, ids, starts, cont);
      word.clear();
      wordStart = -1;
    }

    var offset = 0;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final here = offset;
      offset += ch.length;
      if (rune == 0 || rune == 0xFFFD) continue;
      final isWs = ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' ||
          _space.hasMatch(ch);
      if (isWs) {
        flush();
        continue;
      }
      if (_control.hasMatch(ch)) continue;
      if (_isPunct(rune, ch) || _isCjk(rune)) {
        flush();
        _wordPiece(ch, base + here, ids, starts, cont);
        continue;
      }
      if (word.isEmpty) wordStart = here;
      word.write(ch);
    }
    flush();
  }

  bool _isPunct(int r, String ch) =>
      (r >= 33 && r <= 47) ||
      (r >= 58 && r <= 64) ||
      (r >= 91 && r <= 96) ||
      (r >= 123 && r <= 126) ||
      _punctuation.hasMatch(ch);

  bool _isCjk(int r) =>
      (r >= 0x4E00 && r <= 0x9FFF) ||
      (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x20000 && r <= 0x2A6DF) ||
      (r >= 0x2A700 && r <= 0x2B73F) ||
      (r >= 0x2B740 && r <= 0x2B81F) ||
      (r >= 0x2B820 && r <= 0x2CEAF) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0x2F800 && r <= 0x2FA1F);

  void _wordPiece(String word, int start, List<int> ids, List<int> starts,
      List<bool> cont) {
    final chars = word.runes.map(String.fromCharCode).toList();
    if (chars.length > _maxCharsPerWord) {
      ids.add(_unk);
      starts.add(start);
      cont.add(false);
      return;
    }
    final pieces = <int>[];
    var from = 0;
    while (from < chars.length) {
      var to = chars.length;
      int? found;
      while (from < to) {
        final sub = (from > 0 ? '##' : '') + chars.sublist(from, to).join();
        final id = _vocab[sub];
        if (id != null) {
          found = id;
          break;
        }
        to--;
      }
      if (found == null) {
        pieces
          ..clear()
          ..add(_unk);
        break;
      }
      pieces.add(found);
      from = to;
    }
    for (var i = 0; i < pieces.length; i++) {
      ids.add(pieces[i]);
      starts.add(start);
      cont.add(i > 0);
    }
  }
}
