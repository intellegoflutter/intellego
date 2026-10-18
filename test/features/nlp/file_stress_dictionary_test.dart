import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/nlp/accent/stress_dictionary.dart';

void main() {
  late Directory tmp;
  late FileStressDictionary dict;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stress');
    // blocks of 2 lines
    const lines = [
      ['аист', 0],
      ['банан', 3],
      ['вода', 3],
      ['город', 0],
      ['дом', 0],
      ['ёж', 0],
      ['жизнь', 0],
    ];
    final dat = StringBuffer();
    final idx = StringBuffer();
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = '${lines[i][0]}\t${lines[i][1]}\n';
      if (i % 2 == 0) idx.write('${lines[i][0]}\t$offset\n');
      dat.write(line);
      offset += line.codeUnits.fold<int>(0, (n, c) => n + (c < 0x80 ? 1 : 2));
    }
    final f = File('${tmp.path}/stress.dat')..writeAsStringSync(dat.toString());
    dict = FileStressDictionary(f, idx.toString());
  });

  tearDown(() async {
    await dict.close();
    await tmp.delete(recursive: true);
  });

  test('finds words in every block, including first and last', () async {
    expect(await dict.stressIndex('аист'), 0);
    expect(await dict.stressIndex('банан'), 3);
    expect(await dict.stressIndex('вода'), 3);
    expect(await dict.stressIndex('жизнь'), 0);
  });

  test('missing words return null', () async {
    expect(await dict.stressIndex('аа'), isNull);
    expect(await dict.stressIndex('баран'), isNull);
    expect(await dict.stressIndex('яблоко'), isNull);
  });
}
