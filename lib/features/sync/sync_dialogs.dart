import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'sync_client.dart';
import 'sync_providers.dart';
import 'sync_server.dart';

/// Desktop: lets the phone connect and shows the address and code to type
/// there.
class SyncServerDialog extends ConsumerWidget {
  const SyncServerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncServerProvider);
    final controller = ref.read(syncServerProvider.notifier);
    return AlertDialog(
      title: const Text('Sync with the phone'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Accept syncs from the phone'),
              value: state.running,
              onChanged: (on) => on ? controller.start() : controller.stop(),
            ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (state.running) ...[
              const SizedBox(height: 8),
              const Text('On the phone, tap the sync button and enter:'),
              const SizedBox(height: 8),
              FutureBuilder<List<String>>(
                future: localAddresses(),
                builder: (context, snapshot) => SelectableText(
                  [
                    for (final a in snapshot.data ?? const <String>[])
                      '$a:${state.port}',
                  ].join('\n'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SelectableText(
                    'Code: ${state.code.substring(0, 4)}-${state.code.substring(4)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'New code',
                    onPressed: () => controller.start(newCode: true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Both devices must be on the same network. Over a USB cable '
                'run "adb reverse tcp:${state.port} tcp:${state.port}" and '
                'use localhost:${state.port} on the phone.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Phone: connects to the desktop and syncs.
class SyncNowDialog extends ConsumerStatefulWidget {
  const SyncNowDialog({super.key});

  @override
  ConsumerState<SyncNowDialog> createState() => _SyncNowDialogState();
}

class _SyncNowDialogState extends ConsumerState<SyncNowDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String _status = '';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _address.text = prefs.getString(syncAddressKey) ?? '';
      _code.text = prefs.getString(syncCodeKey) ?? '';
    } catch (_) {
      // Settings just start empty.
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _failed = false;
      _status = 'Connecting…';
    });
    SyncClient? client;
    try {
      final server = parseSyncAddress(_address.text);
      final code = normalizeSyncCode(_code.text);
      if (code.isEmpty) throw const SyncException('Enter the code.');
      client = SyncClient(
        server: server,
        code: code,
        store: await ref.read(syncStoreProvider.future),
      );
      final report = await client.sync(
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(syncAddressKey, _address.text.trim());
        await prefs.setString(syncCodeKey, code);
      } catch (_) {
        // Not remembering the settings does not undo the sync.
      }
      ref.invalidate(booksProvider);
      ref.invalidate(speakingLogProvider);
      if (mounted) setState(() => _status = '$report');
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = 'Sync failed: $e';
        });
      }
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Sync with the computer'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_status.isNotEmpty) ...[
                Text(
                  _status,
                  style: TextStyle(
                    color: _failed ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'On the computer open the sync dialog and switch it on, then '
                'enter the address and code it shows.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Address (e.g. 192.168.1.20:8765)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('Sync now'),
          onPressed: _busy ? null : _sync,
        ),
      ],
    );
  }
}
