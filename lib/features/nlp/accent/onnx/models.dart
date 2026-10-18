import 'dart:math' as math;

import 'bert_tokenizer.dart';
import 'char_tokenizer.dart';
import 'nn_session.dart';

List<double> softmax(List<double> x) {
  final m = x.reduce(math.max);
  final e = [for (final v in x) math.exp(v - m)];
  final sum = e.fold<double>(0, (a, b) => a + b);
  return [for (final v in e) v / sum];
}

/// BERT token classifier that yields one label per basic (whitespace /
/// punctuation separated) token, e.g. RUAccent's stress-usage and
/// ё-homograph models. Word pieces are merged by averaging probabilities.
class TokenLabeler {
  TokenLabeler(this._session, this._tokenizer, this._id2label);

  final NnSession _session;
  final BertTokenizer _tokenizer;
  final List<String> _id2label;

  /// Label keyed by the source offset where the token starts.
  Future<Map<int, String>> labelByStart(String text) async {
    final enc = _tokenizer.encode(text);
    final logits = await _session.run(enc.ids, tokenTypeIds: enc.typeIds);
    final labels = <int, String>{};
    var i = 0;
    while (i < enc.ids.length) {
      if (enc.tokenStarts[i] < 0) {
        i++;
        continue;
      }
      final start = enc.tokenStarts[i];
      final sum = List<double>.filled(logits.classes, 0);
      var count = 0;
      do {
        final p = softmax(logits.row(i));
        for (var c = 0; c < p.length; c++) {
          sum[c] += p[c];
        }
        count++;
        i++;
      } while (i < enc.ids.length && enc.isContinuation[i]);
      var best = 0;
      for (var c = 1; c < sum.length; c++) {
        if (sum[c] > sum[best]) best = c;
      }
      labels[start] = _id2label[best];
      assert(count > 0);
    }
    return labels;
  }
}

/// Chooses the right stressed variant of a homograph given its sentence.
class OmographScorer {
  OmographScorer(this._session, this._tokenizer);

  final NnSession _session;
  final BertTokenizer _tokenizer;

  static final _spaceBeforePunct = RegExp(r'\s+(?=[,.?!:;…])');

  /// [markedSentence] holds the target word wrapped in `<w>…</w>`.
  /// Mirrors RUAccent: with an even number of variants the raw "match" logit
  /// is compared, otherwise the softmax probability.
  Future<int> pick(String markedSentence, List<String> variants) async {
    final text = markedSentence.replaceAll(_spaceBeforePunct, '');
    final rawLogit = variants.length.isEven;
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < variants.length; i++) {
      final enc = _tokenizer.encodePair(text, variants[i]);
      final logits = await _session.run(enc.ids, tokenTypeIds: enc.typeIds);
      final row = logits.row(0);
      final score = rawLogit ? row[1] : softmax(row)[1];
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }
}

/// Character-level stress placement for words missing from the dictionary.
class AccentPlacer {
  AccentPlacer(this._session, this._tokenizer, this._id2label);

  final NnSession _session;
  final CharTokenizer _tokenizer;
  final List<String> _id2label;

  static const _threshold = 0.55;
  static const _maxWordLength = 56;

  /// Returns [word] with "+" before every stressed vowel the model predicts.
  Future<String> putAccent(String word) async {
    if (word.length > _maxWordLength) return word;
    final lower = word.toLowerCase();
    final ids = _tokenizer.encode(lower);
    final logits = await _session.run(ids);
    final chars = word.split('');
    final out = StringBuffer();
    final marks = <int>{};
    for (var i = 1; i <= chars.length; i++) {
      final p = softmax(logits.row(i));
      var best = 0;
      for (var c = 1; c < p.length; c++) {
        if (p[c] > p[best]) best = c;
      }
      final label = _id2label[best];
      if (label != 'NO' &&
          label != 'STRESS_SECONDARY' &&
          p[best] >= _threshold) {
        marks.add(i - 1);
      }
    }
    for (var i = 0; i < chars.length; i++) {
      if (marks.contains(i)) out.write('+');
      out.write(chars[i]);
    }
    return out.toString();
  }
}
