import 'dart:convert';

import 'package:http/http.dart' as http;

import 'book_bundle.dart';
import 'book_patch.dart';
import 'sync_server.dart';
import 'sync_store.dart';

/// What a sync did.
class SyncReport {
  const SyncReport({
    this.received = 0,
    this.sent = 0,
    this.unchanged = 0,
    this.skipped = const [],
  });

  /// Books changed on this device, books changed on the other, and books that
  /// were already the same.
  final int received, sent, unchanged;

  /// Titles of books that were left alone because the two devices have
  /// different texts under the same book.
  final List<String> skipped;

  @override
  String toString() {
    final skippedNote = skipped.isEmpty
        ? ''
        : ' Left alone because the text differs: ${skipped.join(', ')}.';
    return received == 0 && sent == 0
        ? 'Already in sync ($unchanged books).$skippedNote'
        : 'Done: $received updated here, $sent updated on the computer, '
              '$unchanged unchanged.$skippedNote';
  }
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The address a person typed: `192.168.1.20`, `192.168.1.20:8765` or a full
/// `http://…` URL; the default port is used when none is given.
Uri parseSyncAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) throw const SyncException('Enter the computer\'s address.');
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw SyncException('"$input" is not a valid address.');
  }
  return Uri(
    scheme: 'http',
    host: uri.host,
    port: uri.hasPort ? uri.port : defaultSyncPort,
  );
}

/// Brings the books of this device and of the computer running a
/// [SyncServer] in step. Books only one side has are copied whole; for the
/// others the two states are compared section by section (256 sentences) and
/// only the sections and audiobooks that differ travel, each sentence mark and
/// translation line judged on its own change time.
class SyncClient {
  SyncClient({
    required this.server,
    required this.code,
    required this.store,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _http = client ?? http.Client();

  final Uri server;
  final String code;
  final SyncStore store;
  final http.Client _http;
  final Duration timeout;

  Map<String, String> get _headers => {'Authorization': 'Bearer $code'};

  Uri _uri(String path, [Map<String, String>? query]) =>
      server.replace(path: path, queryParameters: query);

  Future<http.Response> _send(Future<http.Response> request) async {
    final http.Response r;
    try {
      r = await request.timeout(timeout);
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncException('Cannot reach $server: $e');
    }
    if (r.statusCode == 401) {
      throw const SyncException('The code is wrong.');
    }
    if (r.statusCode == 429) {
      throw const SyncException(
        'Too many wrong codes: the computer refuses connections for a minute.',
      );
    }
    return r;
  }

  Future<SyncReport> sync({void Function(String status)? onStatus}) async {
    onStatus?.call('Connecting…');
    final list = await _send(_http.get(_uri('/books'), headers: _headers));
    if (list.statusCode != 200) {
      throw SyncException('The computer answered ${list.statusCode}.');
    }
    final remoteIds = [
      for (final id in (jsonDecode(utf8.decode(list.bodyBytes))['ids'] as List))
        id as String,
    ];
    final ids = {...await store.ids(), ...remoteIds}.toList()..sort();

    var received = 0, sent = 0, unchanged = 0;
    final skipped = <String>[];
    for (var n = 0; n < ids.length; n++) {
      final id = ids[n];
      onStatus?.call('Book ${n + 1} of ${ids.length}…');
      final local = await store.load(id);
      final remoteHas = remoteIds.contains(id);
      if (local == null) {
        final whole = await _fetchWhole(id);
        if (whole != null) {
          await store.save(whole);
          received++;
        }
      } else if (!remoteHas) {
        await _putWhole(local);
        sent++;
      } else {
        switch (await _syncBook(id, local)) {
          case _Outcome.unchanged:
            unchanged++;
          case _Outcome.changed:
            received++;
            sent++;
          case _Outcome.differentText:
            skipped.add(local.book.title);
        }
      }
    }
    return SyncReport(
      received: received,
      sent: sent,
      unchanged: unchanged,
      skipped: skipped,
    );
  }

  /// Brings one book that both sides have in step, moving only the sections
  /// of sentences and the audiobooks that differ.
  Future<_Outcome> _syncBook(String id, BookBundle local) async {
    final ld = digestOf(local);
    final rd = BookDigest.fromJson(
      await _getJson('/books/$id/digest', 'a book'),
    );
    final common = ld.sentences < rd.sentences ? ld.sentences : rd.sentences;
    final bool sameText;
    if (ld.sentences == rd.sentences) {
      sameText = ld.textHash == rd.textHash;
    } else {
      final prefix = await _getJson('/books/$id/prefix', 'a book', {
        'upto': '$common',
      });
      sameText = prefix['hash'] == textHashUpTo(local.book, common);
    }
    if (!sameText) return _Outcome.differentText;

    final sections = differingSections(ld, rd);
    final tracks = differingTracks(ld, rd);
    final settingsDiffer =
        ld.position != rd.position || ld.nextPage != rd.nextPage;
    if (sections.isEmpty &&
        tracks.isEmpty &&
        ld.sentences == rd.sentences &&
        !settingsDiffer) {
      return _Outcome.unchanged;
    }

    final pull = BookPatch.fromJson(
      await _postJson('/books/$id/pull', {
        'sections': sections,
        'tracks': tracks,
        if (rd.sentences > ld.sentences) 'tailFrom': ld.sentences,
      }),
    );
    final push = buildPatch(
      local,
      sections: sections,
      tracks: tracks,
      tailFrom: ld.sentences > rd.sentences ? rd.sentences : null,
    );
    // Merge into the copy as it is now: the book may have been read or edited
    // while the sections travelled.
    final current = await store.load(id) ?? local;
    await store.save(applyPatch(current, pull));
    await _postJson('/books/$id/push', push.toJson(), expectBody: false);
    return _Outcome.changed;
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    String what, [
    Map<String, String>? query,
  ]) async {
    final r = await _send(_http.get(_uri(path, query), headers: _headers));
    if (r.statusCode != 200) {
      throw SyncException('The computer answered ${r.statusCode} for $what.');
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool expectBody = true,
  }) async {
    final r = await _send(
      _http.post(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      ),
    );
    final ok = expectBody
        ? r.statusCode == 200
        : r.statusCode == 204 || r.statusCode == 200;
    if (!ok) {
      throw SyncException(
        'The computer answered ${r.statusCode}'
        '${r.body.isEmpty ? '' : ': ${r.body}'}.',
      );
    }
    return expectBody
        ? jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>
        : const {};
  }

  Future<BookBundle?> _fetchWhole(String id) async {
    final r = await _send(_http.get(_uri('/books/$id'), headers: _headers));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw SyncException('The computer answered ${r.statusCode} for a book.');
    }
    return BookBundle.fromJson(
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
    );
  }

  /// Sends a book the computer does not have yet.
  Future<void> _putWhole(BookBundle bundle) async {
    final r = await _send(
      _http.put(
        _uri('/books/${bundle.book.id}'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode(bundle.toJson())),
      ),
    );
    if (r.statusCode != 204) {
      throw SyncException('The computer answered ${r.statusCode} to a book.');
    }
  }

  void close() => _http.close();
}

enum _Outcome { unchanged, changed, differentText }
