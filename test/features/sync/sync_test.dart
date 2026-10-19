import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intellego/data/book.dart';
import 'package:intellego/data/book_repository.dart';
import 'package:intellego/data/book_stamps.dart';
import 'package:intellego/features/playback/audio_store.dart';
import 'package:intellego/features/speaking/speaking_log.dart';
import 'package:intellego/features/sync/book_bundle.dart';
import 'package:intellego/features/youtube/caption_models.dart';
import 'package:intellego/features/sync/book_patch.dart';
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

BookSentence _s(String text, {bool practiced = false, int at = 0}) =>
    BookSentence(
      text: text,
      accented: text,
      paragraph: 0,
      practiced: practiced,
      practicedAt: at,
    );

Book _book({
  String id = '1',
  List<BookSentence>? sentences,
  List<Translation> translations = const [],
  List<AudioTrack> tracks = const [],
  int? nextPage,
}) => Book(
  id: id,
  title: 'T',
  createdAt: DateTime.utc(2026),
  sentences: sentences ?? [_s('a'), _s('b'), _s('c')],
  translations: translations,
  tracks: tracks,
  nextPage: nextPage,
);

AudioTrack _track(String language, int at, {String text = 'x'}) =>
    AudioTrack.single(
      language: language,
      label: language,
      videoId: 'v',
      videoTitle: 'V',
      sentences: [TimedText(text: text, startMs: 0, endMs: 10)],
      updatedAt: at,
    );

BookBundle _bundle(Book b, {Map<int, SpeakingAttempt>? speaking, int? pos}) =>
    BookBundle(book: b, speaking: speaking ?? const {}, position: pos ?? 0);

/// Everything a device sends the other, as the client would.
BookPatch _all(BookBundle b) => buildPatch(
  b,
  sections: List.generate(digestOf(b).sections.length, (i) => i),
  tracks: [for (final t in b.book.tracks) t.language],
);

String _json(BookBundle b) => jsonEncode(b.toJson());

AudioStore _audioIn(Directory dir) => AudioStore(root: dir);

void main() {
  group('stamping saved changes', () {
    test('only what differs from the saved copy gets the new time', () {
      final old = _book(
        sentences: [_s('a', practiced: true, at: 5), _s('b'), _s('c')],
        translations: const [
          Translation(
            name: 'Italian',
            lines: ['uno', 'due', ''],
            stamps: [7, 8, 0],
          ),
        ],
        tracks: [_track('uk', 3)],
      );
      final edited = old
          .withSentences([
            old.sentences[0],
            old.sentences[1].copyWith(practiced: true),
            old.sentences[2],
          ])
          .withTranslations([
            old.translations[0].withLine(1, 'DUE').withLine(2, 'tre'),
          ])
          .withTracks([old.tracks[0].copyWith(visible: false)]);
      final out = stampChanges(old, edited, 100);
      expect(out.sentences.map((s) => s.practicedAt), [5, 100, 0]);
      expect(out.translations.single.stamps, [7, 100, 100]);
      // a display setting is not a change of the audiobook
      expect(out.tracks.single.updatedAt, 3);
      final changed = stampChanges(
        old,
        old.withTracks([_track('uk', 3, text: 'other')]),
        100,
      );
      expect(changed.tracks.single.updatedAt, 100);
    });

    test('a new translation is stamped line by line, empty lines stay 0', () {
      final old = _book();
      final next = old.withTranslations(const [
        Translation(name: 'English', lines: ['one', '', 'three']),
      ]);
      expect(stampChanges(old, next, 9).translations.single.stamps, [9, 0, 9]);
    });

    test(
      'the repository stamps on save but keeps stamps it is told to',
      () async {
        final dir = await Directory.systemTemp.createTemp('stamps');
        addTearDown(() => dir.delete(recursive: true));
        final repo = BookRepository(dir);
        await repo.save(_book());
        final first = (await repo.load('1'))!;
        final saved = await repo.save(
          first.withSentences([
            first.sentences[0].copyWith(practiced: true),
            ...first.sentences.skip(1),
          ]),
        );
        expect(saved.sentences[0].practicedAt, greaterThan(0));
        expect(saved.sentences[1].practicedAt, 0);
        final kept = await repo.save(
          first.withSentences([
            first.sentences[0].copyWith(practiced: true, practicedAt: 42),
            ...first.sentences.skip(1),
          ]),
          keepStamp: true,
        );
        expect(kept.sentences[0].practicedAt, 42);
      },
    );
  });

  group('merging patches', () {
    test('each translation line goes to its newer edit, on both devices', () {
      Book with_(List<String> lines, List<int> stamps) => _book(
        translations: [
          Translation(name: 'Italian', lines: lines, stamps: stamps),
        ],
      );
      final phone = _bundle(with_(['uno', 'DUE', ''], [10, 30, 0]));
      final desktop = _bundle(with_(['UNO', 'due', 'tre'], [20, 15, 5]));
      final onPhone = applyPatch(phone, _all(desktop));
      final onDesktop = applyPatch(desktop, _all(phone));
      expect(onPhone.book.translations.single.lines, ['UNO', 'DUE', 'tre']);
      expect(onPhone.book.translations.single.stamps, [20, 30, 5]);
      expect(_json(onPhone), _json(onDesktop));
    });

    test('chapters from both devices are joined, the same on both', () {
      Book with_(List<Chapter> chapters) => _book().withChapters(chapters);
      final phone = _bundle(
        with_(const [
          Chapter(title: 'One', sentenceIndex: 0),
          Chapter(title: 'Two', sentenceIndex: 2),
        ]),
      );
      final desktop = _bundle(
        with_(const [
          Chapter(title: 'Uno', sentenceIndex: 0),
          Chapter(title: 'Three', sentenceIndex: 1),
        ]),
      );
      final onPhone = applyPatch(phone, _all(desktop));
      final onDesktop = applyPatch(desktop, _all(phone));
      expect(
        [
          for (final c in onPhone.book.chapters)
            '${c.sentenceIndex}:${c.title}',
        ],
        ['0:Uno', '1:Three', '2:Two'],
      );
      expect(_json(onPhone), _json(onDesktop));
      expect(digestOf(phone).chapters, isNot(digestOf(desktop).chapters));
    });

    test(
      'applying a patch keeps the chapters of a copy it knows nothing of',
      () {
        final mine = _bundle(
          _book().withChapters(const [Chapter(title: 'One', sentenceIndex: 0)]),
        );
        final merged = applyPatch(mine, _all(_bundle(_book())));
        expect(merged.book.chapters, hasLength(1));
      },
    );

    test('equal times give the same winner on both sides', () {
      Book with_(String line) => _book(
        translations: [
          Translation(
            name: 'It',
            lines: [line, '', ''],
            stamps: const [5, 0, 0],
          ),
        ],
      );
      final a = _bundle(with_('alfa')), b = _bundle(with_('beta'));
      expect(_json(applyPatch(a, _all(b))), _json(applyPatch(b, _all(a))));
    });

    test('a newer mark wins, so a sentence can be un-practised', () {
      final phone = _bundle(
        _book(sentences: [_s('a'), _s('b', practiced: true, at: 10), _s('c')]),
      );
      final desktop = _bundle(
        _book(
          sentences: [
            _s('a', practiced: true, at: 4),
            _s('b', practiced: false, at: 20),
            _s('c'),
          ],
        ),
      );
      final merged = applyPatch(phone, _all(desktop)).book.sentences;
      expect(merged.map((s) => s.practiced), [true, false, false]);
      expect(
        _json(applyPatch(phone, _all(desktop))),
        _json(applyPatch(desktop, _all(phone))),
      );
    });

    test('unstamped marks from both sides are joined', () {
      final a = _bundle(
        _book(sentences: [_s('a', practiced: true), _s('b'), _s('c')]),
      );
      final b = _bundle(
        _book(sentences: [_s('a'), _s('b', practiced: true), _s('c')]),
      );
      final merged = applyPatch(a, _all(b)).book.sentences;
      expect(merged.map((s) => s.practiced), [true, true, false]);
    });

    test('sentences added at the end and a new language arrive', () {
      final short = _bundle(_book());
      final longer = _bundle(
        _book(
          sentences: [_s('a'), _s('b'), _s('c'), _s('d'), _s('e')],
          translations: const [
            Translation(
              name: 'English',
              lines: ['1', '2', '3', '4', '5'],
              stamps: [1, 1, 1, 1, 1],
            ),
          ],
          nextPage: 7,
        ),
      );
      final digestShort = digestOf(short), digestLong = digestOf(longer);
      final sections = differingSections(digestShort, digestLong);
      final pull = buildPatch(longer, sections: sections, tailFrom: 3);
      final onShort = applyPatch(short, pull);
      expect(onShort.book.sentences.map((s) => s.text), [
        'a', 'b', 'c', 'd', 'e', //
      ]);
      expect(onShort.book.translations.single.lines, ['1', '2', '3', '4', '5']);
      expect(onShort.book.nextPage, 7);
      final push = buildPatch(short, sections: sections);
      expect(_json(applyPatch(longer, push)), _json(onShort));
    });

    test('a patch that continues after missing sentences is refused', () {
      final longer = _bundle(
        _book(sentences: [for (final t in 'abcde'.split('')) _s(t)]),
      );
      expect(
        () => applyPatch(_bundle(_book()), buildPatch(longer, tailFrom: 4)),
        throwsStateError,
      );
    });

    test('the newer audiobook wins, new ones are added, visibility stays', () {
      final mine = _bundle(
        _book(tracks: [_track('uk', 10, text: 'old').copyWith(visible: false)]),
      );
      final theirs = _bundle(
        _book(
          tracks: [
            _track('uk', 20, text: 'new'),
            _track('pt', 1),
          ],
        ),
      );
      final merged = applyPatch(mine, _all(theirs)).book.tracks;
      expect(merged.map((t) => t.language), ['uk', 'pt']);
      expect(merged[0].sentences.single.text, 'new');
      expect(merged[0].visible, false);
      final older = applyPatch(theirs, _all(mine)).book.tracks;
      expect(older[0].sentences.single.text, 'new');
    });

    test('speaking results keep the larger counts, position the later one', () {
      final a = _bundle(
        _book(),
        speaking: const {
          0: SpeakingAttempt(attempts: 3, best: 0.4),
          1: SpeakingAttempt(attempts: 1, best: 0.9),
        },
        pos: 5,
      );
      final b = _bundle(
        _book(),
        speaking: const {0: SpeakingAttempt(attempts: 2, best: 0.8)},
        pos: 9,
      );
      final merged = applyPatch(a, _all(b));
      expect(merged.speaking[0]!.attempts, 3);
      expect(merged.speaking[0]!.best, 0.8);
      expect(merged.speaking[1]!.attempts, 1);
      expect(merged.position, 9);
    });

    test('patches and digests survive JSON', () {
      final b = _bundle(
        _book(
          translations: const [
            Translation(name: 'It', lines: ['x', 'y', 'z'], stamps: [1, 2, 3]),
          ],
          tracks: [_track('uk', 4)],
        ),
        speaking: const {2: SpeakingAttempt(attempts: 1, best: 0.5)},
        pos: 2,
      );
      final patch = _all(b);
      final back = BookPatch.fromJson(
        jsonDecode(jsonEncode(patch.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(patch.toJson()));
      final d = digestOf(b);
      expect(
        jsonEncode(
          BookDigest.fromJson(jsonDecode(jsonEncode(d.toJson()))).toJson(),
        ),
        jsonEncode(d.toJson()),
      );
      expect(_json(BookBundle.fromJson(jsonDecode(_json(b)))), _json(b));
    });
  });

  group('digests', () {
    final big = _book(
      sentences: [for (var i = 0; i < 1000; i++) _s('sentence $i')],
      translations: [
        Translation(
          name: 'It',
          lines: [for (var i = 0; i < 1000; i++) 'riga $i'],
          stamps: List.filled(1000, 1),
        ),
      ],
    );

    test('only the section with a changed line differs', () {
      final edited = big.withTranslations([
        big.translations[0].copyWith(
          lines: [...big.translations[0].lines]..[600] = 'cambiata',
          stamps: [...big.translations[0].stamps]..[600] = 2,
        ),
      ]);
      final a = digestOf(_bundle(big)), b = digestOf(_bundle(edited));
      expect(a.sections, hasLength(4));
      expect(differingSections(a, b), [2]);
      expect(a.textHash, b.textHash);
    });

    test('texts, tracks and positions are told apart', () {
      final other = big.withSentences([
        big.sentences[0].copyWith(),
        for (var i = 1; i < 1000; i++)
          i == 5 ? _s('changed') : big.sentences[i],
      ]);
      expect(
        digestOf(_bundle(big)).textHash,
        isNot(digestOf(_bundle(other)).textHash),
      );
      expect(
        differingTracks(
          digestOf(_bundle(big.withTracks([_track('uk', 1)]))),
          digestOf(_bundle(big)),
        ),
        ['uk'],
      );
    });
  });

  group('audio files', () {
    late _MemoryStore desktop, phone;
    late Directory desktopDir, phoneDir, tmp;
    late AudioStore desktopAudio, phoneAudio;
    late SyncServer server;
    late Uri address;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sync_audio');
      desktopDir = await Directory('${tmp.path}/desktop').create();
      phoneDir = await Directory('${tmp.path}/phone').create();
      desktopAudio = _audioIn(desktopDir);
      phoneAudio = _audioIn(phoneDir);
      desktop = _MemoryStore();
      phone = _MemoryStore();
      // Both have a book that refers to the audio of the video "v".
      final book = _book(tracks: [_track('ru', 1)]);
      desktop.bundles['1'] = _bundle(book);
      phone.bundles['1'] = _bundle(book);
      server = SyncServer(
        store: desktop,
        code: 'ABCDEFGH',
        audio: desktopAudio,
      );
      address = Uri.parse('http://127.0.0.1:${await server.start(port: 0)}');
    });

    tearDown(() async {
      await server.stop();
      await tmp.delete(recursive: true);
    });

    SyncClient client({AudioStore? audio}) => SyncClient(
      server: address,
      code: 'ABCDEFGH',
      store: phone,
      audio: audio ?? phoneAudio,
    );

    Future<File> put(AudioStore store, String id, List<int> bytes) async {
      final dir = await store.dir;
      return File('${dir.path}/$id.m4a').writeAsBytes(bytes);
    }

    test('a file only the computer has is copied to the phone, once', () async {
      final bytes = List.generate(300000, (i) => i % 251);
      await put(desktopAudio, 'v', bytes);
      final first = await client().sync();
      expect((first.audioReceived, first.audioSent), (1, 0));
      expect(first.audioFailed, isEmpty);
      expect(await (await phoneAudio.find('v'))!.readAsBytes(), bytes);
      final second = await client().sync();
      expect((second.audioReceived, second.audioSent), (0, 0));
    });

    test('a file only the phone has is copied to the computer', () async {
      final bytes = List.generate(200000, (i) => (i * 7) % 256);
      await put(phoneAudio, 'v', bytes);
      final report = await client().sync();
      expect((report.audioReceived, report.audioSent), (0, 1));
      expect(await (await desktopAudio.find('v'))!.readAsBytes(), bytes);
    });

    test('audio no book refers to stays where it is', () async {
      await put(desktopAudio, 'other', [1, 2, 3]);
      final report = await client().sync();
      expect(report.audioReceived, 0);
      expect(await phoneAudio.find('other'), isNull);
    });

    test('nothing is copied when the audio is switched off', () async {
      await put(desktopAudio, 'v', [1, 2, 3]);
      final report = await client().sync(withAudio: false);
      expect(report.audioReceived, 0);
      expect(await phoneAudio.find('v'), isNull);
    });

    test('a computer without audio support does not fail the sync', () async {
      await server.stop();
      server = SyncServer(store: desktop, code: 'ABCDEFGH');
      address = Uri.parse('http://127.0.0.1:${await server.start(port: 0)}');
      final report = await client().sync();
      expect(report.audioFailed, hasLength(1));
      expect('$report', contains('Audio not copied'));
    });

    test('the server refuses odd names and file types', () async {
      Future<int> put_(String path) async {
        final r = await http.put(
          address.replace(
            path: path.split('?').first,
            query: path.contains('?') ? path.split('?').last : null,
          ),
          headers: {'Authorization': 'Bearer ABCDEFGH'},
          body: [1, 2, 3],
        );
        return r.statusCode;
      }

      expect(await put_('/audio/v?ext=../x'), 400);
      expect(await put_('/audio/v?ext=toolongext'), 400);
      expect(await put_('/audio/v'), 400);
      expect(await put_('/audio/v?ext=m4a'), 204);
      expect(await put_('/audio/v?ext=m4a'), 409);
      expect(await desktopAudio.find('v'), isNotNull);
    });
  });

  group('client and server', () {
    late _MemoryStore desktop, phone;
    late SyncServer server;
    late Uri address;
    final changed = <String>[];
    var now = DateTime.utc(2026, 1, 1);

    setUp(() async {
      desktop = _MemoryStore();
      phone = _MemoryStore();
      changed.clear();
      now = DateTime.utc(2026, 1, 1);
      server = SyncServer(
        store: desktop,
        code: 'ABCD-EFGH',
        onChanged: changed.add,
        clock: () => now,
      );
      final port = await server.start(port: 0);
      address = Uri.parse('http://127.0.0.1:$port');
    });

    tearDown(() => server.stop());

    SyncClient client([String code = 'abcdefgh', http.Client? http]) =>
        SyncClient(server: address, code: code, store: phone, client: http);

    test('books travel both ways and a second sync changes nothing', () async {
      desktop.bundles['1'] = _bundle(_book(id: '1'));
      phone.bundles['2'] = _bundle(_book(id: '2'));

      final first = await client().sync();
      expect((first.received, first.sent), (1, 1));
      expect(phone.bundles.keys.toSet(), {'1', '2'});
      expect(desktop.bundles.keys.toSet(), {'1', '2'});
      expect(changed, ['2']);

      final second = await client().sync();
      expect((second.received, second.sent, second.unchanged), (0, 0, 2));
    });

    test('Italian translated on the phone reaches the desktop', () async {
      desktop.bundles['1'] = _bundle(
        _book(
          translations: const [
            Translation(name: 'Italian', lines: ['', '', '']),
          ],
        ),
      );
      phone.bundles['1'] = _bundle(
        _book(
          translations: const [
            Translation(
              name: 'Italian',
              lines: ['uno', 'due', 'tre'],
              stamps: [5, 5, 5],
            ),
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
      expect(_json(phone.bundles['1']!), _json(desktop.bundles['1']!));
    });

    test('edits to different lines on both sides are both kept', () async {
      Book base(List<String> lines, List<int> stamps) => _book(
        sentences: [for (var i = 0; i < 600; i++) _s('s$i')],
        translations: [Translation(name: 'It', lines: lines, stamps: stamps)],
      );
      final lines = [for (var i = 0; i < 600; i++) 'l$i'];
      final stamps = List.filled(600, 1);
      desktop.bundles['1'] = _bundle(
        base([...lines]..[10] = 'desktop edit', [...stamps]..[10] = 50),
      );
      phone.bundles['1'] = _bundle(
        base([...lines]..[500] = 'phone edit', [...stamps]..[500] = 60),
      );
      await client().sync();
      for (final store in [phone, desktop]) {
        final merged = store.bundles['1']!.book.translations.single.lines;
        expect(merged[10], 'desktop edit');
        expect(merged[500], 'phone edit');
      }
      expect(_json(phone.bundles['1']!), _json(desktop.bundles['1']!));
    });

    test('only the changed section travels', () async {
      final sentences = [for (var i = 0; i < 5000; i++) _s('sentence $i')];
      final lines = [for (var i = 0; i < 5000; i++) 'riga numero $i'];
      Book make(List<String> l, List<int> s) => _book(
        sentences: sentences,
        translations: [Translation(name: 'It', lines: l, stamps: s)],
      );
      final stamps = List.filled(5000, 1);
      desktop.bundles['1'] = _bundle(make(lines, stamps));
      phone.bundles['1'] = _bundle(
        make([...lines]..[4000] = 'nuova', [...stamps]..[4000] = 9),
      );
      final counter = _CountingClient();
      final report = await client('abcdefgh', counter).sync();
      expect(report.sent, 1);
      expect(
        desktop.bundles['1']!.book.translations.single.lines[4000],
        'nuova',
      );
      // a whole book is about 200 KB here; one section a few KB
      expect(counter.bytes, lessThan(40 * 1024));
    });

    test('pages added on one side extend the other', () async {
      final shared = [for (var i = 0; i < 300; i++) _s('s$i')];
      desktop.bundles['1'] = _bundle(_book(sentences: shared));
      phone.bundles['1'] = _bundle(
        _book(
          sentences: [...shared, for (var i = 300; i < 350; i++) _s('s$i')],
          nextPage: 3,
        ),
      );
      await client().sync();
      expect(desktop.bundles['1']!.book.sentences, hasLength(350));
      expect(desktop.bundles['1']!.book.nextPage, 3);
      expect(_json(phone.bundles['1']!), _json(desktop.bundles['1']!));
      final again = await client().sync();
      expect(again.unchanged, 1);
    });

    test('books with different texts are left alone and reported', () async {
      desktop.bundles['1'] = _bundle(_book());
      phone.bundles['1'] = _bundle(
        _book(sentences: [_s('a'), _s('other'), _s('c')]),
      );
      final report = await client().sync();
      expect(report.skipped, ['T']);
      expect(desktop.bundles['1']!.book.sentences[1].text, 'b');
    });

    test('a wrong code is refused', () async {
      desktop.bundles['1'] = _bundle(_book());
      await expectLater(
        client('WRONGCODE').sync(),
        throwsA(
          isA<SyncException>().having((e) => '$e', 'message', contains('code')),
        ),
      );
      expect(phone.bundles, isEmpty);
    });

    test('five wrong codes lock the server for a minute', () async {
      for (var i = 0; i < maxWrongCodes; i++) {
        await expectLater(
          client('WRONGCODE').sync(),
          throwsA(isA<SyncException>()),
        );
      }
      // even the right code is refused while locked
      await expectLater(
        client().sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => '$e',
            'message',
            contains('Too many'),
          ),
        ),
      );
      now = now.add(const Duration(minutes: 2));
      expect((await client().sync()).unchanged, 0);
    });

    test('a right code in between restarts the count', () async {
      for (var round = 0; round < 3; round++) {
        for (var i = 0; i < maxWrongCodes - 1; i++) {
          await expectLater(
            client('WRONGCODE').sync(),
            throwsA(isA<SyncException>()),
          );
        }
        await client().sync();
      }
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

        expect(await status('GET', '/books'), 200);
        expect(await status('GET', '/books/..%2Fsecret'), 400);
        expect(await status('GET', '/books/99'), 404);
        expect(await status('GET', '/books/99/digest'), 404);
        expect(await status('PUT', '/books/99', body: 'not json'), 400);
        expect(await status('POST', '/books/99/push', body: '{}'), 400);
        expect(await status('DELETE', '/books/99'), 405);
        expect(await status('GET', '/other'), 404);
        expect(await status('GET', '/books', auth: null), 401);
      },
    );

    test('a whole book is only stored when the computer lacks it', () async {
      desktop.bundles['1'] = _bundle(_book());
      final request = http.Request('PUT', address.replace(path: '/books/1'))
        ..headers['Authorization'] = 'Bearer ABCDEFGH'
        ..body = _json(_bundle(_book()));
      expect((await request.send()).statusCode, 409);
    });

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
    final bundle = _bundle(
      _book(sentences: [_s('a', practiced: true, at: 42), _s('b'), _s('c')]),
      speaking: const {1: SpeakingAttempt(attempts: 2, best: 0.5)},
    );
    await store.save(bundle);
    expect(await store.ids(), ['1']);
    final back = (await store.load('1'))!;
    expect(back.book.sentences[0].practicedAt, 42);
    expect(back.speaking[1]!.attempts, 2);
    expect(await store.load('nope'), isNull);
  });
}

/// Counts the bytes of every request and response body.
class _CountingClient extends http.BaseClient {
  final _inner = http.Client();
  int bytes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) bytes += request.bodyBytes.length;
    final response = await _inner.send(request);
    final body = await response.stream.toBytes();
    bytes += body.length;
    return http.StreamedResponse(
      Stream.value(body),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
