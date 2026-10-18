import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'book_merge.dart';
import 'sync_store.dart';

const defaultSyncPort = 8765;

/// Book ids are numbers made by the app; anything else is not served, which
/// also keeps ids from reaching outside the books folder.
final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

const _maxBody = 64 * 1024 * 1024;

/// A new pairing code: 8 characters, no look-alikes.
String newSyncCode([Random? random]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 8; i++) alphabet.codeUnitAt(r.nextInt(alphabet.length)),
  ]);
}

/// The code as typed by a person: case, spaces and dashes do not matter.
String normalizeSyncCode(String code) =>
    code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Serves the books of this device to the other one over plain HTTP on the
/// local network (or an `adb reverse` tunnel). Every request must carry the
/// pairing code.
///
///  * `GET /books` lists the book ids,
///  * `GET /books/<id>` returns a [BookBundle],
///  * `PUT /books/<id>` merges the sent bundle into the stored one.
class SyncServer {
  SyncServer({required this.store, required String code, this.onChanged})
    : _code = normalizeSyncCode(code);

  final SyncStore store;
  final String _code;

  /// Called with the id of every book a client changed.
  final void Function(String id)? onChanged;

  HttpServer? _server;

  bool get running => _server != null;

  int? get port => _server?.port;

  /// Starts listening on all addresses; [port] 0 picks a free one.
  Future<int> start({int port = defaultSyncPort}) async {
    final server = _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
    );
    server.listen(_handle);
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  bool _authorised(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return false;
    final given = normalizeSyncCode(header.substring(prefix.length));
    if (given.length != _code.length) return false;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given.codeUnitAt(i) ^ _code.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorised(request)) {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.isEmpty ||
          segments.first != 'books' ||
          segments.length > 2) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (segments.length == 1) {
        if (request.method != 'GET') {
          response.statusCode = HttpStatus.methodNotAllowed;
          return;
        }
        _json(response, {'ids': await store.ids()});
        return;
      }
      final id = segments[1];
      if (!_validId.hasMatch(id)) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      switch (request.method) {
        case 'GET':
          final bundle = await store.load(id);
          if (bundle == null) {
            response.statusCode = HttpStatus.notFound;
          } else {
            _json(response, bundle.toJson());
          }
        case 'PUT':
          final body = await _readBody(request);
          if (body == null) {
            response.statusCode = HttpStatus.requestEntityTooLarge;
            return;
          }
          final incoming = BookBundle.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          );
          if (incoming.book.id != id) {
            response.statusCode = HttpStatus.badRequest;
            return;
          }
          final existing = await store.load(id);
          await store.save(
            existing == null ? incoming : mergeBundles(existing, incoming),
          );
          onChanged?.call(id);
          response.statusCode = HttpStatus.noContent;
        default:
          response.statusCode = HttpStatus.methodNotAllowed;
      }
    } on FormatException catch (e) {
      response.statusCode = HttpStatus.badRequest;
      response.write(e.message);
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('$e');
    } finally {
      await response.close();
    }
  }

  /// The request body as text, null when it is larger than allowed.
  Future<String?> _readBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) return null;
    }
    return utf8.decode(bytes);
  }

  void _json(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}

/// IPv4 addresses of this machine that the other device might reach it on.
Future<List<String>> localAddresses() async {
  final out = <String>[];
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      if (!a.isLoopback) out.add(a.address);
    }
  }
  return out;
}
