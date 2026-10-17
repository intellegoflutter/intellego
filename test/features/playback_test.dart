import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellego/features/playback/audio_downloader.dart';
import 'package:intellego/features/playback/audio_store.dart';

void main() {
  test('yt-dlp progress lines', () {
    expect(parseYtDlpProgress('[download]  45.3% of  172.51MiB at 5.1MiB/s ETA 00:20'), closeTo(0.453, 1e-9));
    expect(parseYtDlpProgress('[download] 100% of 172.51MiB in 00:34'), 1.0);
    expect(parseYtDlpProgress('[youtube] Extracting URL'), isNull);
  });

  test('yt-dlp version check', () {
    expect(ytDlpIsRecent('2025.10.22'), isTrue);
    expect(ytDlpIsRecent('2026.01.03'), isTrue);
    expect(ytDlpIsRecent('2024.04.09'), isFalse);
    expect(ytDlpIsRecent('2025.9.30'), isFalse);
  });

  test('audio store imports, finds and replaces files', () async {
    final tmp = await Directory.systemTemp.createTemp('audio');
    addTearDown(() => tmp.delete(recursive: true));
    final store = AudioStore(root: Directory('${tmp.path}/store'));
    expect(await store.find('abc'), isNull);

    final src = File('${tmp.path}/book.MP3')..writeAsStringSync('x');
    final stored = await store.importFile('abc', src);
    expect(stored.path, endsWith('/abc.mp3'));
    expect((await store.find('abc'))!.path, stored.path);
    expect(await store.find('ab'), isNull);

    File('${stored.parent.path}/abc.m4a.part').writeAsStringSync('partial');
    final again = File('${tmp.path}/b.m4a')..writeAsStringSync('y');
    final replaced = await store.importFile('abc', again);
    expect(replaced.path, endsWith('/abc.m4a'));
    expect(File(stored.path).existsSync(), isFalse);
  });
}
