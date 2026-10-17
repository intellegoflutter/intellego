import 'dart:convert';
import 'dart:io';

import '../accent_dictionary_loader.dart';
import 'bert_tokenizer.dart';
import 'char_tokenizer.dart';
import 'models.dart';
import 'nn_session.dart';
import 'onnx_accentuator.dart';

/// Homograph models built on a WordPiece vocabulary. The larger BPE-based
/// RUAccent models (turbo*) are not supported.
enum OmographModelSize {
  tiny2('tiny2', 10),
  tiny21('tiny2.1', 41);

  const OmographModelSize(this.dirName, this.approxMegabytes);

  final String dirName;
  final int approxMegabytes;
}

List<String> _id2label(String configJson) {
  final map = (jsonDecode(configJson) as Map<String, dynamic>)['id2label']
      as Map<String, dynamic>;
  return [for (var i = 0; i < map.length; i++) map['$i'] as String];
}

/// Builds an [OnnxAccentuator] from a RUAccent `nn/` directory
/// (`nn_accent`, `nn_stress_usage_predictor`, `nn_yo_homograph_resolver`,
/// `nn_omograph/<size>`).
Future<OnnxAccentuator> loadOnnxAccentuator(
  Directory nnDir, {
  required AccentData data,
  OmographModelSize omographSize = OmographModelSize.tiny2,
}) async {
  final root = nnDir.path;
  String read(String path) => File('$root/$path').readAsStringSync();

  Future<TokenLabeler> labeler(String dir) async => TokenLabeler(
        await OrtNnSession.open('$root/$dir/model.onnx'),
        BertTokenizer.fromVocabText(read('$dir/vocab.txt')),
        _id2label(read('$dir/config.json')),
      );

  final omographDir = 'nn_omograph/${omographSize.dirName}';
  final addedFile = File('$root/$omographDir/added_tokens.json');
  final added = addedFile.existsSync()
      ? (jsonDecode(addedFile.readAsStringSync()) as Map<String, dynamic>)
          .cast<String, int>()
      : <String, int>{};

  return OnnxAccentuator(
    stress: data.stress,
    yoWords: data.yoWords,
    yoHomographs: data.yoHomographs,
    omographs: data.omographs,
    yoResolver: await labeler('nn_yo_homograph_resolver'),
    stressUsage: await labeler('nn_stress_usage_predictor'),
    omographScorer: OmographScorer(
      await OrtNnSession.open('$root/$omographDir/model.onnx'),
      BertTokenizer.fromVocabText(read('$omographDir/vocab.txt'),
          addedTokens: added),
    ),
    accentPlacer: AccentPlacer(
      await OrtNnSession.open('$root/nn_accent/model.onnx'),
      CharTokenizer(read('nn_accent/vocab.txt')),
      _id2label(read('nn_accent/config.json')),
    ),
  );
}
