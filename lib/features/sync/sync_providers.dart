import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'sync_server.dart';
import 'sync_store.dart';

final syncStoreProvider = FutureProvider<SyncStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return LocalSyncStore(
    await ref.watch(bookRepositoryProvider.future),
    Directory('${docs.path}/speaking'),
  );
});

/// Preference keys of the sync settings.
const syncCodeKey = 'sync.code';
const syncAddressKey = 'sync.address';

class SyncServerState {
  const SyncServerState({this.port, this.code = '', this.error});

  /// Port the server listens on, null while it is stopped.
  final int? port;
  final String code;
  final String? error;

  bool get running => port != null;
}

/// Starts and stops the sync server of this (desktop) device.
class SyncServerController extends Notifier<SyncServerState> {
  SyncServer? _server;

  @override
  SyncServerState build() {
    ref.onDispose(() => _server?.stop());
    return const SyncServerState();
  }

  Future<String> _code({bool fresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    var code = fresh ? null : prefs.getString(syncCodeKey);
    if (code == null) {
      code = newSyncCode();
      await prefs.setString(syncCodeKey, code);
    }
    return code;
  }

  Future<void> start({bool newCode = false}) async {
    await stop();
    try {
      final code = await _code(fresh: newCode);
      final server = SyncServer(
        store: await ref.read(syncStoreProvider.future),
        audio: ref.read(audioStoreProvider),
        code: code,
        onChanged: (id) {
          ref.invalidate(booksProvider);
          ref.invalidate(speakingLogProvider(id));
        },
      );
      final port = await server.start();
      _server = server;
      state = SyncServerState(port: port, code: code);
    } catch (e) {
      state = SyncServerState(error: 'Could not start: $e');
    }
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    state = const SyncServerState();
  }
}

final syncServerProvider =
    NotifierProvider<SyncServerController, SyncServerState>(
      SyncServerController.new,
    );
