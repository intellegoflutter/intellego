import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local copies of audiobook audio, one file per YouTube video id.
class AudioStore {
  AudioStore({this._root});

  Directory? _root;

  Future<Directory> get dir async {
    final d = _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/audio',
    );
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

  /// Every stored audio file by video id.
  Future<Map<String, File>> all() async {
    final found = <String, File>{};
    await for (final e in (await dir).list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final dot = name.indexOf('.');
      if (dot > 0 && !name.endsWith('.part')) found[name.substring(0, dot)] = e;
    }
    return found;
  }

  /// Stores [data] as the audio of [videoId] with extension [ext]. It is
  /// written under a temporary name and only put in place when it is whole:
  /// [expectedLength] bytes, if given.
  Future<File> saveStream(
    String videoId,
    String ext,
    Stream<List<int>> data, {
    int? expectedLength,
  }) async {
    final folder = (await dir).path;
    final part = File('$folder/$videoId.$ext.part');
    try {
      final sink = part.openWrite();
      try {
        await sink.addStream(data);
      } finally {
        await sink.close();
      }
      if (expectedLength != null && await part.length() != expectedLength) {
        throw const FormatException('The audio file did not arrive whole.');
      }
      await delete(videoId);
      return await part.rename('$folder/$videoId.$ext');
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> delete(String videoId) async {
    final f = await find(videoId);
    if (f != null) await f.delete();
  }

  /// Prefix for downloaders: they append the extension themselves.
  Future<String> targetPrefix(String videoId) async =>
      '${(await dir).path}/$videoId';
}
