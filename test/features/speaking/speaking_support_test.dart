import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellego/features/speaking/asr_model_store.dart';
import 'package:intellego/features/speaking/feedback_writer.dart';
import 'package:intellego/features/speaking/pronunciation_comparer.dart';
import 'package:intellego/features/speaking/speaking_log.dart';

void main() {
  group('SpeakingLog', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('speaking'));
    tearDown(() => tmp.delete(recursive: true));

    test('counts attempts, keeps the best score and survives a restart', () async {
      final file = File('${tmp.path}/sub/book.json');
      final log = SpeakingLog(file);
      await log.load();
      expect(log.attempts, isEmpty);
      await log.record(3, 0.5);
      await log.record(3, 0.9);
      await log.record(3, 0.7);
      await log.record(8, 1);
      final again = SpeakingLog(file);
      await again.load();
      expect(again.attempts[3]!.attempts, 3);
      expect(again.attempts[3]!.best, 0.9);
      expect(again.attempts[8]!.best, 1);
    });

    test('a damaged file is ignored', () async {
      final file = File('${tmp.path}/book.json')..writeAsStringSync('{oops');
      final log = SpeakingLog(file);
      await log.load();
      expect(log.attempts, isEmpty);
    });
  });

  group('AsrModelStore', () {
    test('downloads missing files, checks their size and reports progress', () async {
      final tmp = await Directory.systemTemp.createTemp('asr');
      addTearDown(() => tmp.delete(recursive: true));
      final requested = <String>[];
      final client = MockClient.streaming((request, _) async {
        requested.add(request.url.pathSegments.last);
        final name = request.url.pathSegments.last;
        final size = AsrModelStore.files.firstWhere((f) => f.name == name).bytes;
        // Do not really send 236 MB: pretend the sizes are tiny.
        return http.StreamedResponse(Stream.value(List.filled(5, 1)), 200,
            contentLength: size);
      });
      final store = AsrModelStore(client: client, root: Directory('${tmp.path}/asr'), baseUrl: 'https://x/y');
      expect(await store.isInstalled(), isFalse);
      // The mock delivers 5 bytes, so the size check must reject it.
      await expectLater(store.install(), throwsA(isA<HttpException>()));
      expect(requested, ['model.int8.onnx']);
      expect(File('${tmp.path}/asr/model.int8.onnx.part').existsSync(), isFalse);
    });

    test('files of the right size count as installed', () async {
      final tmp = await Directory.systemTemp.createTemp('asr');
      addTearDown(() => tmp.delete(recursive: true));
      final store = AsrModelStore(root: tmp);
      // tokens.txt is small enough to fake; the model is not.
      File('${tmp.path}/tokens.txt').writeAsBytesSync(List.filled(196, 0));
      expect(await store.isInstalled(), isFalse);
      final model = File('${tmp.path}/model.int8.onnx').openSync(mode: FileMode.write);
      model.truncateSync(AsrModelStore.files.first.bytes); // sparse file
      model.closeSync();
      expect(await store.isInstalled(), isTrue);
    });
  });

  group('LocalFeedbackWriter', () {
    const writer = LocalFeedbackWriter();

    test('perfect reading', () async {
      final c = compareWords(accented: 'Она́ чита́ла.', heard: 'она читала');
      final text = await writer.write(accented: 'Она́ чита́ла.', comparison: c);
      expect(text, contains('Every word was recognised'));
      expect(text, contains('stress'));
    });

    test('lists missed and misheard words with their stress', () async {
      const accented = 'Нача́ла она́ расска́зывать о свое́й жи́зни.';
      final c = compareWords(accented: accented, heard: 'начала она расказывать о жизни');
      final text = await writer.write(accented: accented, comparison: c);
      expect(text, contains('67%'));
      expect(text, contains('расска́зывать: almost, heard “расказывать”. Stress on syllable 2.'));
      expect(text, contains('свое́й: not heard. Stress on syllable 2.'));
      expect(text, isNot(contains('жи́зни:')));
    });

    test('one-syllable words get no stress advice', () async {
      final c = compareWords(accented: 'Кто там?', heard: 'там');
      final text = await writer.write(accented: 'Кто там?', comparison: c);
      expect(text, contains('Кто: not heard.'));
      expect(text, isNot(contains('Stress on syllable')));
    });
  });
}
