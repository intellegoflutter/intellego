import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../playback/audio_store.dart';
import 'book_bundle.dart';
import 'book_patch.dart';
import 'sync_store.dart';

const defaultSyncPort = 8765;

/// Book ids are numbers made by the app; anything else is not served, which
/// also keeps ids from reaching outside the books folder.
final _validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Whether [id] (a book id or a video id) is safe to use in a file name.
bool isSafeSyncId(String id) => _validId.hasMatch(id);

const _maxBody = 64 * 1024 * 1024;

/// The largest audio file the server accepts.
const _maxAudio = 4 * 1024 * 1024 * 1024;

final _validExtension = RegExp(r'^[a-z0-9]{1,5}$');

/// Whether [ext] is safe to use as a file extension.
bool isSafeAudioExtension(String ext) => _validExtension.hasMatch(ext);

/// After this many wrong codes in a row the server refuses everything for
/// [lockout].
const maxWrongCodes = 5;

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
/// pairing code; after [maxWrongCodes] wrong ones in a row the server answers
/// "too many requests" to everybody for [lockout].
///
///  * `GET /books` lists the book ids,
///  * `GET /books/<id>` returns a whole [BookBundle],
///  * `PUT /books/<id>` stores a whole book this device does not have yet,
///  * `GET /books/<id>/digest` describes the book's state ([BookDigest]),
///  * `GET /books/<id>/prefix?upto=<n>` hashes the first n sentence texts,
///  * `POST /books/<id>/pull` returns the sections, audiobooks and sentences
///    asked for as a [BookPatch],
///  * `POST /books/<id>/push` merges the sent [BookPatch] into the book,
///  * `GET /audio` lists the audio files by video id (extension and size),
///  * `GET /audio/<video id>` sends one audio file,
///  * `PUT /audio/<video id>?ext=m4a` stores one the server does not have.
///
/// The audio endpoints answer 404 unless the server was given an [audio] store.
class SyncServer {
  SyncServer({
    required this.store,
    required String code,
    this.audio,
    this.onChanged,
    this.lockout = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _code = normalizeSyncCode(code),
       _now = clock ?? DateTime.now;

  final SyncStore store;
  final AudioStore? audio;
  final String _code;
  final Duration lockout;
  final DateTime Function() _now;

  /// Called with the id of every book a client changed.
  final void Function(String id)? onChanged;

  HttpServer? _server;
  int _wrongCodes = 0;
  DateTime? _lockedUntil;
  Future<void> _writing = Future.value();

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

  bool get _locked {
    final until = _lockedUntil;
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _lockedUntil = null;
    return false;
  }

  bool _codeMatches(HttpRequest request) {
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

  /// Checks the code, counting wrong ones; false when the request must be
  /// refused (the status is already set).
  bool _authorise(HttpRequest request) {
    if (_locked) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      return false;
    }
    if (_codeMatches(request)) {
      _wrongCodes = 0;
      return true;
    }
    if (++_wrongCodes >= maxWrongCodes) {
      _wrongCodes = 0;
      _lockedUntil = _now().add(lockout);
    }
    request.response.statusCode = HttpStatus.unauthorized;
    return false;
  }

  /// Runs [action] after every earlier change finished, so two requests never
  /// write the same book at once.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _writing.then((_) => action());
    _writing = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorise(request)) return;
      final segments = request.uri.pathSegments;
      if (segments.isNotEmpty && segments.first == 'audio') {
        await _audioFiles(request, segments);
        return;
      }
      if (segments.isEmpty ||
          segments.first != 'books' ||
          segments.length > 3) {
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
      if (segments.length == 2) {
        await _wholeBook(request, id);
      } else {
        await _bookPart(request, id, segments[2]);
      }
    } on FormatException catch (e) {
      response.statusCode = HttpStatus.badRequest;
      response.write(e.message);
    } on TypeError {
      response.statusCode = HttpStatus.badRequest;
    } on StateError catch (e) {
      response.statusCode = HttpStatus.conflict;
      response.write(e.message);
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<void> _audioFiles(HttpRequest request, List<String> segments) async {
    final response = request.response;
    final store = audio;
    if (store == null || segments.length > 2) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (segments.length == 1) {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final files = await store.all();
      _json(response, {
        'files': {
          for (final e in files.entries)
            e.key: {
              'ext': e.value.path.substring(e.value.path.lastIndexOf('.') + 1),
              'size': await e.value.length(),
            },
        },
      });
      return;
    }
    final id = segments[1];
    if (!_validId.hasMatch(id)) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    switch (request.method) {
      case 'GET':
        final file = (await store.all())[id];
        if (file == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        response.headers.contentType = ContentType.binary;
        response.contentLength = await file.length();
        await response.addStream(file.openRead());
      case 'PUT':
        final ext = (request.uri.queryParameters['ext'] ?? '').toLowerCase();
        final length = request.contentLength;
        if (!_validExtension.hasMatch(ext) ||
            length <= 0 ||
            length > _maxAudio) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        await _exclusive(() async {
          if ((await store.all()).containsKey(id)) {
            response.statusCode = HttpStatus.conflict;
            return;
          }
          await store.saveStream(id, ext, request, expectedLength: length);
          response.statusCode = HttpStatus.noContent;
        });
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }

  Future<void> _wholeBook(HttpRequest request, String id) async {
    final response = request.response;
    switch (request.method) {
      case 'GET':
        final bundle = await store.load(id);
        if (bundle == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          _json(response, bundle.toJson());
        }
      case 'PUT':
        final incoming = BookBundle.fromJson(await _readJson(request));
        if (incoming.book.id != id) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        await _exclusive(() async {
          if (await store.load(id) != null) {
            response.statusCode = HttpStatus.conflict;
            return;
          }
          await store.save(incoming);
          onChanged?.call(id);
          response.statusCode = HttpStatus.noContent;
        });
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }

  Future<void> _bookPart(HttpRequest request, String id, String part) async {
    final response = request.response;
    final get = request.method == 'GET';
    final post = request.method == 'POST';
    if (!((get && (part == 'digest' || part == 'prefix')) ||
        (post && (part == 'pull' || part == 'push')))) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (part == 'push') {
      final patch = BookPatch.fromJson(await _readJson(request));
      await _exclusive(() async {
        final mine = await store.load(id);
        if (mine == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        await store.save(applyPatch(mine, patch));
        onChanged?.call(id);
        response.statusCode = HttpStatus.noContent;
      });
      return;
    }
    final bundle = await store.load(id);
    if (bundle == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    switch (part) {
      case 'digest':
        _json(response, digestOf(bundle).toJson());
      case 'prefix':
        final upto = int.tryParse(request.uri.queryParameters['upto'] ?? '');
        if (upto == null || upto < 0) {
          response.statusCode = HttpStatus.badRequest;
          return;
        }
        _json(response, {'hash': textHashUpTo(bundle.book, upto)});
      case 'pull':
        final ask = await _readJson(request);
        _json(
          response,
          buildPatch(
            bundle,
            sections: (ask['sections'] as List? ?? const []).cast<int>(),
            tracks: (ask['tracks'] as List? ?? const []).cast<String>(),
            tailFrom: ask['tailFrom'] as int?,
          ).toJson(),
        );
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    if (request.contentLength > _maxBody) {
      throw const FormatException('The request is too large.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > _maxBody) {
        throw const FormatException('The request is too large.');
      }
    }
    return jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
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
