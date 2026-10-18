// Dumps real cues + Russian paragraphs to JSON for calibrating the aligner.
// dart run tool/capture_data.dart <videoUrl> <bookId> <pages> <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:intellego/features/import/loveread_source.dart';
import 'package:intellego/features/import/web_text_fetcher.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> a) async {
  final out = Directory(a[3])..createSync(recursive: true);
  final yt = YoutubeExplode();
  final video = await yt.videos.get(a[0]);
  final manifest = await yt.videos.closedCaptions.getManifest(video.id);
  final cc = await yt.videos.closedCaptions.get(manifest.tracks.first);
  File('${out.path}/cues.json').writeAsStringSync(
    jsonEncode([
      for (final c in cc.captions)
        {
          's': c.offset.inMilliseconds,
          'd': c.duration.inMilliseconds,
          't': c.text,
        },
    ]),
  );
  yt.close();
  final src = LoveReadSource(WebTextFetcher());
  final book = await src.fetchBook(
    Uri.parse('https://loveread.ec'),
    int.parse(a[1]),
    pageCount: int.parse(a[2]),
  );
  File('${out.path}/ru.json').writeAsStringSync(jsonEncode(book.paragraphs));
  print('cues=${cc.captions.length} ruParagraphs=${book.paragraphs.length}');
}
