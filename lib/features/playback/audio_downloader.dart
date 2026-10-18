import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'audio_store.dart';

class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Progress (0..1) from a yt-dlp `--newline` line such as
/// `[download]  45.3% of  172.51MiB at ...`, or null.
double? parseYtDlpProgress(String line) {
  final m = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%').firstMatch(line);
  return m == null ? null : double.parse(m.group(1)!) / 100;
}

/// True when a yt-dlp version string (`2025.10.22`) is at least [minimum].
bool ytDlpIsRecent(String version, {String minimum = '2025.10.01'}) {
  List<int> parts(String v) =>
      RegExp(r'\d+')
          .allMatches(v)
          .map((m) => int.parse(m.group(0)!))
          .take(3)
          .toList();
  final a = parts(version), b = parts(minimum);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return true;
}

/// Desktop downloader that drives yt-dlp (YouTube no longer serves long
/// audio to plain HTTP clients, yt-dlp keeps up with those changes).
/// Needs a recent yt-dlp and, for the n-challenge, node or deno.
class YtDlpDownloader {
  YtDlpDownloader(this._store);

  final AudioStore _store;

  static bool get supported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Future<List<String>?> _locate() async {
    for (final cmd in const [
      ['yt-dlp'],
      ['uvx', 'yt-dlp'],
    ]) {
      try {
        final r = await Process.run(cmd.first, [...cmd.skip(1), '--version']);
        if (r.exitCode == 0 && ytDlpIsRecent('${r.stdout}'.trim())) return cmd;
      } on ProcessException {
        continue;
      }
    }
    return null;
  }

  Future<bool> _has(String exe) async {
    try {
      return (await Process.run(exe, const ['--version'])).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Downloads the audio of [videoId] into the store.
  Future<File> download(
    String videoId, {
    void Function(double)? onProgress,
  }) async {
    final cmd = await _locate();
    if (cmd == null) {
      throw DownloadException(
        'A recent yt-dlp is required (version 2025.10 or newer). '
        'Install or update it with: pipx install -U yt-dlp  (or: uv tool install yt-dlp). '
        'Alternatively pick an audio file you downloaded yourself.',
      );
    }
    final runtime = await _has('node') ? ['--js-runtimes', 'node'] : <String>[];
    final prefix = await _store.targetPrefix(videoId);
    final process = await Process.start(cmd.first, [
      ...cmd.skip(1),
      '-f',
      '139/140/bestaudio[ext=m4a]/bestaudio',
      '--no-playlist',
      '--newline',
      ...runtime,
      '-o',
      '$prefix.%(ext)s',
      'https://www.youtube.com/watch?v=$videoId',
    ]);
    final errors = <String>[];
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
          final p = parseYtDlpProgress(l);
          if (p != null) onProgress?.call(p);
        });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(errors.add);
    final code = await process.exitCode;
    final file = await _store.find(videoId);
    if (code != 0 || file == null) {
      final tail = errors.where((e) => e.contains('ERROR')).take(2).join('\n');
      throw DownloadException(
        'Download failed${tail.isEmpty ? ' (yt-dlp exit code $code)' : ': $tail'}',
      );
    }
    return file;
  }
}
