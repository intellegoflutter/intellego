import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intellego/features/nlp/accent/accent_dictionary_loader.dart';
import 'package:intellego/features/nlp/accent/accentuator.dart';
import 'package:intellego/features/nlp/accent/onnx/onnx_accentuator_loader.dart';

/// Run: INTELLEGO_NN_DIR=$PWD/.model_cache/nn flutter test integration_test -d linux
/// Compares the Dart pipeline to Python RUAccent output (fixtures/ruaccent_golden.json).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final nnDir = Platform.environment['INTELLEGO_NN_DIR'] ?? '';
  final golden = jsonDecode(
      File('${Directory.current.path}/test/fixtures/ruaccent_golden.json')
          .readAsStringSync()) as List;

  /// Python marks "+" before a vowel; convert to U+0301 after it and drop
  /// marks that the app intentionally omits (ё, one-syllable words).
  String normalize(String py) {
    const vowels = 'аеёиоуыэюяАЕЁИОУЫЭЮЯ';
    final replaced = py.replaceAllMapped(
        RegExp('\\+([$vowels])'), (m) => '${m[1]}$stressMark');
    return replaced
        .split(RegExp(r'(?<=\s)|(?=\s)'))
        .map((w) => w.split('').where(vowels.contains).length < 2
            ? w.replaceAll(stressMark, '')
            : w)
        .join()
        .replaceAll('ё$stressMark', 'ё')
        .replaceAll('Ё$stressMark', 'Ё');
  }

  testWidgets('matches Python RUAccent on sample sentences', (tester) async {
    expect(nnDir, isNotEmpty, reason: 'set INTELLEGO_NN_DIR');
    final data = await loadAccentData();
    final acc = await loadOnnxAccentuator(Directory(nnDir), data: data);
    var same = 0;
    final diffs = <String>[];
    for (final c in golden) {
      final input = c['in'] as String;
      final got = await acc.accent(input);
      final want = normalize(c['out'] as String);
      if (got == want) {
        same++;
      } else {
        diffs.add('IN   $input\nWANT $want\nGOT  $got');
      }
    }
    // ignore: avoid_print
    print('identical: $same/${golden.length}\n${diffs.join('\n\n')}');
    expect(same / golden.length, greaterThanOrEqualTo(0.9));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
