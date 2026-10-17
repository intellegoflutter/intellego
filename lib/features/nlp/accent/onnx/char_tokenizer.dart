import 'dart:convert';

/// Character-level tokenizer used by the RUAccent stress placement model:
/// `[bos] c1 c2 … [eos]`.
class CharTokenizer {
  CharTokenizer(String vocabText) {
    var i = 0;
    for (final line in const LineSplitter().convert(vocabText)) {
      _vocab[line] = i++;
    }
    _unk = _vocab['[unk]']!;
    _bos = _vocab['[bos]']!;
    _eos = _vocab['[eos]']!;
  }

  final _vocab = <String, int>{};
  late final int _unk, _bos, _eos;

  List<int> encode(String word) => [
        _bos,
        for (final r in word.runes) _vocab[String.fromCharCode(r)] ?? _unk,
        _eos,
      ];
}
