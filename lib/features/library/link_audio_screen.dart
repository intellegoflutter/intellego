import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/book.dart';

/// Pastes a YouTube link, downloads its subtitles and aligns them with the
/// book's sentences.
class LinkAudioScreen extends ConsumerStatefulWidget {
  const LinkAudioScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<LinkAudioScreen> createState() => _LinkAudioScreenState();
}

class _LinkAudioScreenState extends ConsumerState<LinkAudioScreen> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _link(Book book) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Downloading subtitles…';
    });
    try {
      final captions = await ref.read(captionSourceProvider).fetch(_url.text);
      setState(() => _status =
          'Aligning ${book.sentences.length} sentences with ${captions.cues.length} subtitle lines…');
      final linked = await ref.read(audioLinkerProvider).link(book, captions);
      await ref.read(booksProvider.notifier).updateBook(linked);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == widget.bookId)
        .firstOrNull;
    if (book == null) return Scaffold(appBar: AppBar());
    return Scaffold(
      appBar: AppBar(title: const Text('Link audiobook')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(book.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'YouTube link',
              helperText: 'The subtitles (auto-generated are fine) give the '
                  'Ukrainian text and the timing of every sentence.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _link(book),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _link(book),
            child: const Text('Link'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            if (_status != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!)),
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
}
