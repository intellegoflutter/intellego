import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intellego/features/speaking/pronunciation_comparer.dart';
import 'package:intellego/features/speaking/recorder.dart';
import 'package:intellego/features/speaking/speech_recognizer.dart';

/// Run: INTELLEGO_ASR_DIR=$PWD/.model_cache/asr flutter test integration_test/speech_recognizer_test.dart -d linux
/// The directory holds model.int8.onnx, tokens.txt and example.wav (a reading of
/// Pushkin's "Ничьих не требуя похвал…" from the sherpa-onnx model archive).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(
    Platform.environment['INTELLEGO_ASR_DIR'] ?? '/nonexistent',
  );

  testWidgets('GigaAmRecognizer transcribes a Russian reading', (tester) async {
    expect(dir.existsSync(), isTrue, reason: 'set INTELLEGO_ASR_DIR');
    final recognizer = GigaAmRecognizer(dir);
    addTearDown(recognizer.dispose);
    final sw = Stopwatch()..start();
    final heard = await recognizer.transcribe(File('${dir.path}/example.wav'));
    final first = sw.elapsedMilliseconds;
    sw.reset();
    await recognizer.transcribe(File('${dir.path}/example.wav'));
    // ignore: avoid_print
    print(
      'HEARD: $heard\nfirst call (incl. model load) $first ms, second ${sw.elapsedMilliseconds} ms',
    );

    const expected =
        'Ничьих не требуя похвал, '
        'Счастлив уж я надеждой сладкой, '
        'Что дева с трепетом любви '
        'Посмотрит, может быть, украдкой '
        'На песни грешные мои. '
        'У лукоморья дуб зелёный';
    final c = compareWords(accented: expected, heard: heard);
    expect(c.score, greaterThan(0.95), reason: '$heard\n${c.problems}');

    // The same text read with a word left out must be reported.
    final cut = compareWords(
      accented: '$expected, златая цепь на дубе том',
      heard: heard,
    );
    expect(cut.problems.map((w) => w.status), everyElement(WordStatus.missed));
  });

  testWidgets('GigaAmRecognizer reports a missing model', (tester) async {
    final recognizer = GigaAmRecognizer(Directory('/nonexistent'));
    addTearDown(recognizer.dispose);
    await expectLater(
      recognizer.transcribe(File('${dir.path}/example.wav')),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('recorder writes a readable WAV from the microphone', (
    tester,
  ) async {
    final recorder = RecordPackageRecorder(
      root: Directory.systemTemp.createTempSync('rec'),
    );
    addTearDown(recorder.dispose);
    if (!await recorder.ensurePermission()) {
      markTestSkipped('no microphone permission');
      return;
    }
    await recorder.start();
    await Future<void>.delayed(const Duration(seconds: 2));
    final file = await recorder.stop();
    expect(file, isNotNull);
    expect(file!.lengthSync(), greaterThan(44 + 16000));
    final recognizer = GigaAmRecognizer(dir);
    addTearDown(recognizer.dispose);
    final heard = await recognizer.transcribe(file); // silence or room noise
    // ignore: avoid_print
    print('MIC: "${file.path}" ${file.lengthSync()} bytes, heard "$heard"');
  });
}
