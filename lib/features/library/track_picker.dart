import 'package:flutter/material.dart';

import '../../data/book.dart';

/// Which audiobook language of [book] an action is meant for: the only one
/// without asking, otherwise the user chooses. Null when cancelled.
Future<int?> pickTrack(
  BuildContext context,
  Book book, {
  String title = 'Which audiobook?',
}) async {
  if (book.tracks.isEmpty) return null;
  if (book.tracks.length == 1) return 0;
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (var i = 0; i < book.tracks.length; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, i),
            child: Text(
              '${book.tracks[i].label}'
              '${book.tracks[i].parts.length > 1 ? ' (${book.tracks[i].parts.length} parts)' : ''}',
            ),
          ),
      ],
    ),
  );
}

/// "Ukrainian (2 parts), Portuguese" for the library list.
String audioSummary(Book book) => [
  for (final t in book.tracks)
    t.parts.length > 1 ? '${t.label} (${t.parts.length} parts)' : t.label,
].join(', ');
