import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../data/book.dart';
import '../import/loveread_source.dart';
import '../nlp/accent/accentuator.dart';

bool canAddPages(Book book) {
  final url = Uri.tryParse(book.sourceUrl ?? '');
  return url != null && LoveReadSource.bookId(url) != null;
}

/// Imports further pages of a loveread book into the existing book. The
/// audio link, sync points, progress and extra languages are kept; the audio
/// alignment is recomputed for the longer text.
class AddPagesDialog extends ConsumerStatefulWidget {
  const AddPagesDialog({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<AddPagesDialog> createState() => _AddPagesDialogState();
}

class _AddPagesDialogState extends ConsumerState<AddPagesDialog> {
  final _count = TextEditingController();
  bool _busy = false;
  String? _status;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<Accentuator?> _accentuator() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('import.addStressAndYo') ?? true)) return null;
    if (prefs.getBool('import.neuralAccent') ?? false) {
      final store = ref.read(modelStoreProvider);
      if (await store.isInstalled(defaultOmographSize)) {
        return ref.read(onnxAccentuatorProvider.future);
      }
    }
    return ref.read(accentuatorProvider.future);
  }

  Future<void> _run() async {
    final book = ref.read(booksProvider).value?.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Preparing…';
    });
    try {
      final accentuator = await _accentuator();
      var updated = await ref.read(importServiceProvider).appendPages(
            book,
            pageCount: int.tryParse(_count.text.trim()),
            accentuator: accentuator,
            onFetchProgress: (done, total) => setState(() {
              _status = 'Downloading page $done of $total…';
              _progress = done / total;
            }),
            onProcessProgress: (done, total) => setState(() {
              _status = 'Adding stress marks… sentence $done of $total';
              _progress = done / total;
            }),
          );
      setState(() {
        _status = 'Saving…';
        _progress = null;
      });
      await ref.read(booksProvider.notifier).updateBook(updated);
      if (updated.hasAudio) {
        setState(() {
          _status = 'Re-aligning the audiobooks with the longer text…';
          _progress = null;
        });
        updated = await ref.read(audioLinkerProvider).relink(updated);
        await ref.read(booksProvider.notifier).updateBook(updated);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Added ${updated.sentences.length - book.sentences.length} sentences.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(booksProvider).value?.where((b) => b.id == widget.bookId).firstOrNull;
    return AlertDialog(
      title: const Text('Add more pages'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${book?.title ?? ''}\n'
              'Continues after the last imported page. Your audio link, practice '
              'progress and extra languages are kept.'),
          const SizedBox(height: 12),
          TextField(
            controller: _count,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Number of pages (empty = to the end)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            if (_status != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_status!)),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _run, child: const Text('Add')),
      ],
    );
  }
}
