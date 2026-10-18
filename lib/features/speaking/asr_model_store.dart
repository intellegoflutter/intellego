import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const defaultAsrBaseUrl =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-ctc-giga-am-v2-russian-2025-04-19/resolve/main';

class AsrModelFile {
  const AsrModelFile(this.name, this.bytes);

  final String name;
  final int bytes;
}

/// Downloads the Russian GigaAM speech recognition model (NeMo CTC, int8,
/// from the sherpa-onnx releases, see NOTICE) on first use.
class AsrModelStore {
  AsrModelStore({
    http.Client? client,
    this._root,
    this.baseUrl = defaultAsrBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  Directory? _root;

  static const files = [
    AsrModelFile('model.int8.onnx', 236457977),
    AsrModelFile('tokens.txt', 196),
  ];

  static int get totalBytes => files.fold(0, (n, f) => n + f.bytes);

  Future<Directory> get dir async => _root ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/models/asr',
  );

  Future<bool> isInstalled() async {
    final d = await dir;
    for (final f in files) {
      final file = File('${d.path}/${f.name}');
      if (!await file.exists() || await file.length() != f.bytes) return false;
    }
    return true;
  }

  /// Downloads missing files; [onProgress] gets 0..1 over the whole set.
  Future<void> install({void Function(double)? onProgress}) async {
    final d = await dir;
    await d.create(recursive: true);
    var done = 0;
    for (final f in files) {
      final target = File('${d.path}/${f.name}');
      if (await target.exists() && await target.length() == f.bytes) {
        done += f.bytes;
        onProgress?.call(done / totalBytes);
        continue;
      }
      final tmp = File('${target.path}.part');
      final response = await _client.send(
        http.Request('GET', Uri.parse('$baseUrl/${f.name}')),
      );
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for ${f.name}');
      }
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call((done + received) / totalBytes);
        }
      } finally {
        await sink.close();
      }
      if (received != f.bytes) {
        await tmp.delete();
        throw HttpException(
          'Incomplete download of ${f.name}: $received of ${f.bytes} bytes',
        );
      }
      await tmp.rename(target.path);
      done += f.bytes;
    }
  }
}
