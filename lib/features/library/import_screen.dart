import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../import/import_target.dart';
import '../nlp/accent/accentuator.dart';
import '../nlp/accent/onnx/model_store.dart';

const _prefAccent = 'import.addStressAndYo';
const _prefNeural = 'import.neuralAccent';
const _prefSite = 'import.siteUrl';
const _prefLastInput = 'import.lastInput';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _url = TextEditingController();
  final _pages = TextEditingController();
  Uri _site = Uri.parse(defaultSite);
  bool _accent = true;
  bool _neural = false;
  double? _progress;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _accent = prefs.getBool(_prefAccent) ?? true;
          _neural = prefs.getBool(_prefNeural) ?? false;
          _site = Uri.tryParse(prefs.getString(_prefSite) ?? '') ?? _site;
          if (_url.text.isEmpty) {
            _url.text = prefs.getString(_prefLastInput) ?? inputPrefix(_site);
          }
        });
      }
    } catch (_) {
      // Preference storage unavailable: keep the default.
    }
  }

  void _onProcess(int done, int total) => setState(() {
        _status = _accent
            ? 'Adding stress marks… sentence $done of $total'
            : 'Splitting into sentences… $done of $total';
        _progress = done / total;
      });

  @override
  void dispose() {
    _url.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final target = parseImportInput(_url.text, site: _site);
    if (target == null || (target is LoveReadTarget && _url.text.trim() == inputPrefix(_site))) {
      setState(() => _error = 'Enter a book URL or id');
      return;
    }
    final pageCount = int.tryParse(_pages.text.trim());
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Downloading page…';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAccent, _accent);
      await prefs.setBool(_prefNeural, _neural);
      await prefs.setString(_prefLastInput, _url.text.trim());
      if (target is LoveReadTarget) {
        _site = target.site;
        await prefs.setString(_prefSite, _site.toString());
      }
      Accentuator? accentuator;
      if (_accent) {
        if (_neural) {
          final store = ref.read(modelStoreProvider);
          if (!await store.isInstalled(defaultOmographSize)) {
            setState(() => _status = 'Downloading language models…');
            await store.install(defaultOmographSize,
                onProgress: (p) => setState(() => _progress = p));
            setState(() => _progress = null);
          }
          setState(() => _status = 'Loading language models…');
          accentuator = await ref.read(onnxAccentuatorProvider.future);
        } else {
          setState(() => _status = 'Loading stress dictionary (first time takes a moment)…');
          accentuator = await ref.read(accentuatorProvider.future);
        }
      }
      setState(() {
        _status = 'Processing text…';
        _progress = null;
      });
      final service = ref.read(importServiceProvider);
      final book = switch (target) {
        LoveReadTarget t => await service.importLoveRead(
            t.site,
            t.bookId,
            firstPage: t.firstPage,
            pageCount: pageCount,
            accentuator: accentuator,
            onFetchProgress: (done, total) => setState(() {
              _status = 'Downloading page $done of $total…';
              _progress = done / total;
            }),
            onProcessProgress: _onProcess,
          ),
        WebPageTarget t => await service.importUrl(t.url,
            accentuator: accentuator, onProcessProgress: _onProcess),
      };
      setState(() {
        _status = 'Saving…';
        _progress = null;
      });
      await ref.read(booksProvider.notifier).add(book);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
            content: Text('Imported “${book.title}”: ${book.sentences.length} sentences.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Import text')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Book URL or id',
                helperText: 'Paste a loveread link; the site is remembered. '
                    'Other web pages work too.',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _import(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pages,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of pages (empty = to the end)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add stress marks and ё'),
              subtitle: const Text('Helps beginners read correctly'),
              value: _accent,
              onChanged: _busy ? null : (v) => setState(() => _accent = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resolve ambiguous words by context'),
              subtitle: Text(
                  'Neural models, e.g. за́мок vs замо́к. One-time download of '
                  '~${(ModelStore.totalBytes(defaultOmographSize) / 1e6).round()} MB'),
              value: _neural && _accent,
              onChanged: _busy || !_accent ? null : (v) => setState(() => _neural = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _import,
              child: const Text('Import'),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              if (_status != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      );
}
