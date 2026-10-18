import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'onnx_accentuator_loader.dart';

const _baseUrl = 'https://huggingface.co/ruaccent/accentuator/resolve/main/nn';

class ModelFile {
  const ModelFile(this.path, this.bytes);

  /// Path below `nn/`.
  final String path;
  final int bytes;
}

/// Downloads the RUAccent ONNX models (MIT licensed, see NOTICE) on demand.
class ModelStore {
  ModelStore({http.Client? client, this._root})
    : _client = client ?? http.Client();

  final http.Client _client;
  Directory? _root;

  Future<Directory> get nnDir async {
    final root = _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/models/nn',
    );
    return root;
  }

  static List<ModelFile> filesFor(OmographModelSize size) => [
    const ModelFile('nn_accent/model.onnx', 803402),
    const ModelFile('nn_accent/config.json', 841),
    const ModelFile('nn_accent/vocab.txt', 140),
    const ModelFile('nn_stress_usage_predictor/model.onnx', 116473561),
    const ModelFile('nn_stress_usage_predictor/config.json', 822),
    const ModelFile('nn_stress_usage_predictor/vocab.txt', 1080667),
    const ModelFile('nn_yo_homograph_resolver/model.onnx', 14332169),
    const ModelFile('nn_yo_homograph_resolver/config.json', 625),
    const ModelFile('nn_yo_homograph_resolver/vocab.txt', 48576),
    ..._omograph(size),
  ];

  static List<ModelFile> _omograph(OmographModelSize size) {
    final d = 'nn_omograph/${size.dirName}';
    return switch (size) {
      OmographModelSize.tiny2 => [
        ModelFile('$d/model.onnx', 10528004),
        ModelFile('$d/vocab.txt', 381781),
        ModelFile('$d/added_tokens.json', 36),
      ],
      OmographModelSize.tiny21 => [
        ModelFile('$d/model.onnx', 41532080),
        ModelFile('$d/vocab.txt', 381781),
        ModelFile('$d/added_tokens.json', 36),
      ],
    };
  }

  static int totalBytes(OmographModelSize size) =>
      filesFor(size).fold(0, (n, f) => n + f.bytes);

  Future<bool> isInstalled(OmographModelSize size) async {
    final dir = await nnDir;
    for (final f in filesFor(size)) {
      final file = File('${dir.path}/${f.path}');
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  /// Downloads missing files; [onProgress] gets 0..1 over the whole set.
  Future<void> install(
    OmographModelSize size, {
    void Function(double)? onProgress,
  }) async {
    final dir = await nnDir;
    final files = filesFor(size);
    final total = totalBytes(size);
    var done = 0;
    for (final f in files) {
      final target = File('${dir.path}/${f.path}');
      if (await target.exists() && await target.length() == f.bytes) {
        done += f.bytes;
        onProgress?.call(done / total);
        continue;
      }
      await target.parent.create(recursive: true);
      final tmp = File('${target.path}.part');
      final response = await _client.send(
        http.Request('GET', Uri.parse('$_baseUrl/${f.path}')),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for ${f.path}');
      }
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call((done + received) / total);
        }
      } finally {
        await sink.close();
      }
      if (received != f.bytes) {
        await tmp.delete();
        throw HttpException(
          'Incomplete download of ${f.path}: $received of ${f.bytes} bytes',
        );
      }
      await tmp.rename(target.path);
      done += f.bytes;
    }
  }
}
