import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local copies of audiobook audio, one file per YouTube video id.
class AudioStore {
  AudioStore({this._root});

  Directory? _root;

  Future<Directory> get dir async {
    final d = _root ??=
        Directory('${(await getApplicationSupportDirectory()).path}/audio');
    await d.create(recursive: true);
    return d;
  }

  /// The stored audio of [videoId], or null when it has not been added.
  Future<File?> find(String videoId) async {
    final d = await dir;
    await for (final e in d.list()) {
      if (e is File) {
        final name = e.uri.pathSegments.last;
        if (name.startsWith('$videoId.') && !name.endsWith('.part')) return e;
      }
    }
    return null;
  }

  /// Copies a user-chosen [source] file in as the audio of [videoId].
  Future<File> importFile(String videoId, File source) async {
    await delete(videoId);
    final dot = source.path.lastIndexOf('.');
    final ext = dot < 0 ? 'm4a' : source.path.substring(dot + 1).toLowerCase();
    return source.copy('${(await dir).path}/$videoId.$ext');
  }

  Future<void> delete(String videoId) async {
    final f = await find(videoId);
    if (f != null) await f.delete();
  }

  /// Prefix for downloaders: they append the extension themselves.
  Future<String> targetPrefix(String videoId) async =>
      '${(await dir).path}/$videoId';
}
