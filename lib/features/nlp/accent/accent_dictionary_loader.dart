import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dictionary_accentuator.dart';
import 'stress_dictionary.dart';

const _assetDir = 'assets/dict';
const _dictVersion = 1;

/// Word lists shared by the dictionary-only and the ONNX accentuators.
class AccentData {
  const AccentData({
    required this.stress,
    required this.yoWords,
    required this.omographs,
    required this.yoHomographs,
  });

  final StressDictionary stress;
  final Map<String, String> yoWords;
  final Map<String, List<String>> omographs;
  final Map<String, String> yoHomographs;
}

/// Copies the bundled stress file to app storage once (assets are not
/// randomly accessible on Android) and loads the other tables.
Future<AccentData> loadAccentData() async {
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/dict',
  );
  await dir.create(recursive: true);
  final dat = File('${dir.path}/stress.dat');
  final stamp = File('${dir.path}/version');
  final current = await stamp.exists() ? await stamp.readAsString() : '';
  if (!await dat.exists() || current != '$_dictVersion') {
    final data = await rootBundle.load('$_assetDir/stress.dat');
    await dat.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await stamp.writeAsString('$_dictVersion');
  }

  Future<Map<String, dynamic>> table(String name) async =>
      jsonDecode(await rootBundle.loadString('$_assetDir/$name.json'))
          as Map<String, dynamic>;

  final omographs = await table('omographs');
  return AccentData(
    stress: FileStressDictionary(
      dat,
      await rootBundle.loadString('$_assetDir/stress.idx'),
    ),
    yoWords: (await table('yo_words')).cast<String, String>(),
    omographs: {
      for (final e in omographs.entries)
        e.key: (e.value as List).cast<String>(),
    },
    yoHomographs: (await table('yo_homographs')).cast<String, String>(),
  );
}

Future<DictionaryAccentuator> loadDictionaryAccentuator() async {
  final d = await loadAccentData();
  return DictionaryAccentuator(
    stress: d.stress,
    yoWords: d.yoWords,
    omographs: d.omographs.keys.toSet(),
    yoHomographs: d.yoHomographs.keys.toSet(),
  );
}
