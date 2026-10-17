import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/nlp/accent/accentuator.dart';
import 'package:intellego/features/nlp/accent/dictionary_accentuator.dart';
import 'package:intellego/features/nlp/accent/stress_dictionary.dart';

/// Runs against the generated assets (tool/build_dictionaries.py); skipped
/// when they are absent.
void main() {
  final dat = File('assets/dict/stress.dat');
  final available = dat.existsSync();

  test('real dictionary accents a sample sentence', () async {
    Set<String> keys(String n) => (jsonDecode(
            File('assets/dict/$n.json').readAsStringSync()) as Map<String, dynamic>)
        .keys
        .toSet();
    final acc = DictionaryAccentuator(
      stress: FileStressDictionary(
          dat, File('assets/dict/stress.idx').readAsStringSync()),
      yoWords: (jsonDecode(File('assets/dict/yo_words.json').readAsStringSync())
              as Map<String, dynamic>)
          .cast<String, String>(),
      omographs: keys('omographs'),
      yoHomographs: keys('yo_homographs'),
    );
    const m = stressMark;
    final out = await acc.accent('Мама купила молоко, а потом пошла домой. Елка стояла в углу.');
    expect(out, contains('Ма$m' 'ма'));
    expect(out, contains('молоко$m'));
    expect(out, contains('Ёлка'));
    expect(out, contains('углу$m'));
  }, skip: available ? false : 'generated dictionary assets missing');
}
