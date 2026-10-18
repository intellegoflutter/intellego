import 'dart:convert';

import 'package:http/http.dart' as http;

import 'book_merge.dart';
import 'sync_server.dart';
import 'sync_store.dart';

/// What a sync did.
class SyncReport {
  const SyncReport({this.received = 0, this.sent = 0, this.unchanged = 0});

  /// Books changed on this device, books changed on the other, and books that
  /// were already the same.
  final int received, sent, unchanged;

  @override
  String toString() => received == 0 && sent == 0
      ? 'Already in sync ($unchanged books).'
      : 'Done: $received updated here, $sent updated on the computer, '
            '$unchanged unchanged.';
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
/// [SyncServer] in step: each book is fetched, merged with the local copy, and
/// whichever side then differs from the result is updated.
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

  Uri _uri(String path) => server.replace(path: path);

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
    for (var n = 0; n < ids.length; n++) {
      final id = ids[n];
      onStatus?.call('Book ${n + 1} of ${ids.length}…');
      final local = await store.load(id);
      final remote = remoteIds.contains(id) ? await _fetch(id) : null;
      if (local == null && remote == null) continue;
      final merged = local == null
          ? remote!
          : remote == null
          ? local
          : mergeBundles(local, remote);
      final mergedJson = jsonEncode(merged.toJson());
      final changedHere =
          local == null || jsonEncode(local.toJson()) != mergedJson;
      final changedThere =
          remote == null || jsonEncode(remote.toJson()) != mergedJson;
      if (changedHere) {
        await store.save(merged);
        received++;
      }
      if (changedThere) {
        await _push(merged);
        sent++;
      }
      if (!changedHere && !changedThere) unchanged++;
    }
    return SyncReport(received: received, sent: sent, unchanged: unchanged);
  }

  Future<BookBundle?> _fetch(String id) async {
    final r = await _send(_http.get(_uri('/books/$id'), headers: _headers));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw SyncException('The computer answered ${r.statusCode} for a book.');
    }
    return BookBundle.fromJson(
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _push(BookBundle bundle) async {
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
