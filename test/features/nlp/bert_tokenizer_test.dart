import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/nlp/accent/onnx/bert_tokenizer.dart';
import 'package:intellego/features/nlp/accent/onnx/word_splitter.dart';

const _nn = '.model_cache/nn';

void main() {
  final available = Directory(_nn).existsSync();
  final golden = jsonDecode(
          File('test/fixtures/bert_tokenizer_golden.json').readAsStringSync())
      as Map<String, dynamic>;

  group('BertTokenizer vs HuggingFace', () {
    late BertTokenizer omograph, usage;
    setUp(() {
      Map<String, int> added(String dir) {
        final f = File('$dir/added_tokens.json');
        return f.existsSync()
            ? (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
                .cast<String, int>()
            : {};
      }

      const o = '$_nn/nn_omograph/tiny2';
      omograph = BertTokenizer.fromVocabText(
          File('$o/vocab.txt').readAsStringSync(),
          addedTokens: added(o));
      usage = BertTokenizer.fromVocabText(
          File('$_nn/nn_stress_usage_predictor/vocab.txt').readAsStringSync());
    });

    test('single sequences incl. offsets', () {
      for (final c in golden['single'] as List) {
        final text = c['text'] as String;
        expect(omograph.encode(text).ids, (c['ids'] as List).cast<int>(),
            reason: text);
        final u = usage.encode(text);
        expect(u.ids, (c['uids'] as List).cast<int>(), reason: text);
        final offsets = c['uoffsets'] as List;
        for (var i = 0; i < u.ids.length; i++) {
          if (u.tokenStarts[i] < 0 || u.isContinuation[i]) continue;
          expect(u.tokenStarts[i], (offsets[i] as List)[0],
              reason: '$text token $i');
        }
      }
    });

    test('sentence pairs', () {
      for (final c in golden['pairs'] as List) {
        final e = omograph.encodePair(c['a'] as String, c['b'] as String);
        expect(e.ids, (c['ids'] as List).cast<int>());
        expect(e.typeIds, (c['types'] as List?)?.cast<int>() ?? e.typeIds);
      }
    });
  }, skip: available ? false : 'run tool/fetch_models.sh first');

  test('splitWords keeps stress markers and punctuation runs', () {
    final s = splitWords('Он, к+оса?! (да) кто-то');
    expect(s.words, ['Он', ',', 'к+оса', '?!', '(', 'да', ')', 'кто', '-', 'то']);
    expect(s.join(s.words), 'Он, к+оса?! (да) кто-то');
    expect(s.starts[2], 4);
  });
}
