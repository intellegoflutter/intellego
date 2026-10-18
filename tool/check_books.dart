// Dev check: loads saved books with the current model and compares the audio
// text of every sentence with the legacy fields. dart run tool/check_books.dart <dir>
import 'dart:convert';
import 'dart:io';

import 'package:intellego/data/book.dart';

void main(List<String> a) {
  for (final f in Directory(a[0]).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final book = Book.fromJson(raw);
    var checked = 0, bad = 0;
    final legacy = raw['audio'] as Map<String, dynamic>?;
    if (legacy != null && raw['audioTracks'] == null) {
      final sentences = (legacy['sentences'] as List).cast<Map<String, dynamic>>();
      final rawS = (raw['sentences'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < rawS.length; i++) {
        final from = rawS[i]['ukFrom'] as int?, to = rawS[i]['ukTo'] as int?;
        final expected = from == null || to == null || to <= from
            ? null
            : sentences.sublist(from, to).map((e) => e['text']).join(' ');
        checked++;
        if (book.trackTextFor(i) != expected) bad++;
      }
    }
    final again = Book.fromJson(jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>);
    final same = again.tracks.length == book.tracks.length &&
        List.generate(book.sentences.length, (i) => again.trackTextFor(i) == book.trackTextFor(i))
            .every((x) => x);
    print('${f.path.split('/').last}: ${book.sentences.length} sentences, '
        '${book.tracks.length} tracks, legacy mismatches $bad/$checked, round trip ok=$same, '
        'json ${f.lengthSync() ~/ 1024} KB -> ${jsonEncode(book.toJson()).length ~/ 1024} KB');
  }
}
