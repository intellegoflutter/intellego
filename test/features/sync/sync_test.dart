import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intellego/data/book.dart';
import 'package:intellego/data/book_repository.dart';
import 'package:intellego/features/speaking/speaking_log.dart';
import 'package:intellego/features/sync/book_merge.dart';
import 'package:intellego/features/sync/sync_client.dart';
import 'package:intellego/features/sync/sync_server.dart';
import 'package:intellego/features/sync/sync_store.dart';

class _MemoryStore implements SyncStore {
  final bundles = <String, BookBundle>{};

  @override
  Future<List<String>> ids() async => bundles.keys.toList();

  @override
  Future<BookBundle?> load(String id) async => bundles[id];

  @override
  Future<void> save(BookBundle bundle) async =>
      bundles[bundle.book.id] = bundle;
}

BookSentence _s(String text, {bool practiced = false}) => BookSentence(
  text: text,
  accented: text,
  paragraph: 0,
  practiced: practiced,
);

Book _book({
  String id = '1',
  List<BookSentence>? sentences,
  List<Translation> translations = const [],
  DateTime? at,
  int? nextPage,
}) => Book(
  id: id,
  title: 'T',
  createdAt: DateTime.utc(2026),
  sentences: sentences ?? [_s('a'), _s('b'), _s('c')],
  translations: translations,
  nextPage: nextPage,
  updatedAt: at,
);

void main() {
  final t1 = DateTime.utc(2026, 5, 1), t2 = DateTime.utc(2026, 5, 2);

  group('merge', () {
    test('translation lines of both devices are kept, newer wins a clash', () {
      final phone = _book(
        at: t2,
        translations: const [
          Translation(name: 'Italian', lines: ['uno', 'due-phone', '']),
        ],
      );
      final desktop = _book(
        at: t1,
        translations: const [
          Translation(name: 'Italian', lines: ['', 'due-desktop', 'tre']),
          Translation(name: 'English', lines: ['one', '', '']),
        ],
      );
      for (final merged in [
        mergeBooks(phone, desktop),
        mergeBooks(desktop, phone),
      ]) {
        final it = merged.translations.firstWhere((t) => t.name == 'Italian');
        expect(it.lines, ['uno', 'due-phone', 'tre']);
        expect(merged.translations.map((t) => t.name), contains('English'));
        expect(merged.updatedAt, t2);
      }
    });

    test('practised marks are joined and added sentences extend the book', () {
      final a = _book(
        at: t1,
        sentences: [_s('a', practiced: true), _s('b'), _s('c')],
        nextPage: 3,
      );
      final b = _book(
        at: t2,
        sentences: [_s('a'), _s('b', practiced: true), _s('c'), _s('d')],
        translations: const [
          Translation(name: 'Italian', lines: ['', '', '', 'quattro']),
        ],
        nextPage: 4,
      );
      final merged = mergeBooks(a, b);
      expect(merged.sentences.map((s) => s.text), ['a', 'b', 'c', 'd']);
      expect(merged.sentences.map((s) => s.practiced), [
        true,
        true,
        false,
        false,
      ]);
      expect(merged.nextPage, 4);
      expect(merged.translations.single.lines.length, 4);
    });

    test('a shorter translation is padded to the longer book', () {
      final a = _book(
        at: t2,
        translations: const [
          Translation(name: 'Italian', lines: ['x', '', '']),
        ],
      );
      final b = _book(
        at: t1,
        sentences: [_s('a'), _s('b'), _s('c'), _s('d')],
        translations: const [
          Translation(name: 'Italian', lines: ['', '', '', 'd']),
        ],
      );
      expect(mergeBooks(a, b).translations.single.lines, ['x', '', '', 'd']);
    });

    test('different texts are not joined: the newer copy is kept', () {
      final a = _book(at: t1, sentences: [_s('a'), _s('b')]);
      final b = _book(at: t2, sentences: [_s('x'), _s('y')]);
      expect(mergeBooks(a, b).sentences.first.text, 'x');
    });

    test('speaking results keep the larger counts and the best score', () {
      final merged = mergeBundles(
        BookBundle(
          book: _book(),
          speaking: const {0: SpeakingAttempt(attempts: 3, best: 0.5)},
          position: 10,
        ),
        BookBundle(
          book: _book(),
          speaking: const {
            0: SpeakingAttempt(attempts: 1, best: 0.9),
            2: SpeakingAttempt(attempts: 1, best: 0.2),
          },
          position: 4,
        ),
      );
      expect(merged.speaking[0]!.attempts, 3);
      expect(merged.speaking[0]!.best, 0.9);
      expect(merged.speaking[2]!.attempts, 1);
      expect(merged.position, 10);
    });

    test('bundles survive JSON', () {
      final b = BookBundle(
        book: _book(at: t1),
        speaking: const {1: SpeakingAttempt(attempts: 2, best: 0.7)},
        position: 5,
      );
      final back = BookBundle.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(b.toJson()));
    });
  });

  group('client and server', () {
    late _MemoryStore desktop, phone;
    late SyncServer server;
    late Uri address;
    final changed = <String>[];

    setUp(() async {
      desktop = _MemoryStore();
      phone = _MemoryStore();
      changed.clear();
      server = SyncServer(
        store: desktop,
        code: 'ABCD-EFGH',
        onChanged: changed.add,
      );
      final port = await server.start(port: 0);
      address = Uri.parse('http://127.0.0.1:$port');
    });

    tearDown(() => server.stop());

    SyncClient client([String code = 'abcdefgh']) =>
        SyncClient(server: address, code: code, store: phone);

    test('books travel both ways and a second sync changes nothing', () async {
      desktop.bundles['1'] = BookBundle(
        book: _book(id: '1', at: t1),
      );
      phone.bundles['2'] = BookBundle(
        book: _book(id: '2', at: t1),
      );

      final first = await client().sync();
      expect((first.received, first.sent), (1, 1));
      expect(phone.bundles.keys.toSet(), {'1', '2'});
      expect(desktop.bundles.keys.toSet(), {'1', '2'});
      expect(changed, ['2']);

      final second = await client().sync();
      expect((second.received, second.sent, second.unchanged), (0, 0, 2));
    });

    test('Italian translated on the phone reaches the desktop', () async {
      desktop.bundles['1'] = BookBundle(
        book: _book(
          at: t1,
          translations: const [
            Translation(name: 'Italian', lines: ['', '', '']),
          ],
        ),
      );
      phone.bundles['1'] = BookBundle(
        book: _book(
          at: t2,
          translations: const [
            Translation(name: 'Italian', lines: ['uno', 'due', 'tre']),
          ],
        ),
        speaking: const {0: SpeakingAttempt(attempts: 1, best: 1)},
      );
      await client().sync();
      expect(desktop.bundles['1']!.book.translations.single.lines, [
        'uno',
        'due',
        'tre',
      ]);
      expect(desktop.bundles['1']!.speaking[0]!.attempts, 1);
    });

    test('a wrong code is refused', () async {
      desktop.bundles['1'] = BookBundle(book: _book(at: t1));
      await expectLater(
        client('WRONGCODE').sync(),
        throwsA(
          isA<SyncException>().having((e) => '$e', 'message', contains('code')),
        ),
      );
      expect(phone.bundles, isEmpty);
    });

    test(
      'requests without the code, odd ids and bad bodies are refused',
      () async {
        Future<int> status(
          String method,
          String path, {
          String? auth = 'Bearer ABCDEFGH',
          String? body,
        }) async {
          final request = http.Request(method, address.replace(path: path));
          if (auth != null) request.headers['Authorization'] = auth;
          if (body != null) request.body = body;
          return (await request.send()).statusCode;
        }

        expect(await status('GET', '/books', auth: null), 401);
        expect(await status('GET', '/books', auth: 'Bearer NOPE'), 401);
        expect(await status('GET', '/books'), 200);
        expect(await status('GET', '/books/..%2Fsecret'), 400);
        expect(await status('GET', '/books/99'), 404);
        expect(await status('PUT', '/books/99', body: 'not json'), 400);
        expect(await status('DELETE', '/books/99'), 405);
        expect(await status('GET', '/other'), 404);
      },
    );

    test('an unreachable computer gives a readable error', () async {
      await server.stop();
      await expectLater(
        client().sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => '$e',
            'message',
            startsWith('Cannot reach'),
          ),
        ),
      );
    });
  });

  test('addresses are completed with the default port', () {
    expect(parseSyncAddress('192.168.1.20').port, defaultSyncPort);
    expect(parseSyncAddress(' 10.0.0.2:9000 ').port, 9000);
    expect(parseSyncAddress('http://pc.local:1').host, 'pc.local');
    expect(() => parseSyncAddress(' '), throwsA(isA<SyncException>()));
  });

  test('pairing codes ignore case and separators', () {
    expect(normalizeSyncCode('abcd-efgh '), 'ABCDEFGH');
    expect(newSyncCode(), hasLength(8));
  });

  test('local store round-trips through files', () async {
    final dir = await Directory.systemTemp.createTemp('sync_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalSyncStore(
      BookRepository(Directory('${dir.path}/books')),
      Directory('${dir.path}/speaking'),
    );
    final bundle = BookBundle(
      book: _book(at: t1),
      speaking: const {1: SpeakingAttempt(attempts: 2, best: 0.5)},
    );
    await store.save(bundle);
    expect(await store.ids(), ['1']);
    final back = (await store.load('1'))!;
    expect(back.book.updatedAt, t1);
    expect(back.speaking[1]!.attempts, 2);
    expect(await store.load('nope'), isNull);
  });
}
