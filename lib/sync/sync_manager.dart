import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/vault_crypto.dart';
import '../data/vault.dart';
import 'folder_provider.dart';
import 'github_provider.dart';
import 'sync_provider.dart';

enum SyncState { off, idle, syncing, conflict, error }

/// Keeps the local vault and one cloud copy in step.
///
/// Pull -> per-record last-write-wins merge (HLC stamps) -> push only when
/// the merged vault differs from what the cloud holds. Runs after local
/// edits (debounced), on unlock and every few minutes.
class SyncManager extends ChangeNotifier {
  SyncManager._();

  static final SyncManager I = SyncManager._();

  Vault get vault => Vault.instance;

  SyncProvider? _provider;
  SyncProvider? get provider => _provider;

  SyncState state = SyncState.off;
  String? error;
  DateTime? lastSync;

  /// Cloud copy that belongs to a different vault (set in [SyncState.conflict]).
  Map<String, dynamic>? _conflictRemote;

  Timer? _debounce;
  Timer? _periodic;
  int _syncedRevision = -1;
  bool _running = false;
  bool _again = false;
  bool _listening = false;

  File get _configFile => File('${vault.supportDir}/sync.json');

  // ---------------------------------------------------------------- setup

  /// Called after unlock: restores the configured provider and syncs.
  Future<void> start() async {
    if (!_listening) {
      vault.addListener(_onVaultChanged);
      _listening = true;
    }
    _provider = await _loadConfig();
    state = _provider == null ? SyncState.off : SyncState.idle;
    notifyListeners();
    _periodic?.cancel();
    if (_provider != null) {
      _periodic =
          Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
      unawaited(syncNow());
    }
  }

  /// Called before lock.
  Future<void> stop() async {
    _debounce?.cancel();
    _periodic?.cancel();
    if (_provider != null && vault.revision != _syncedRevision) {
      await syncNow().timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    _provider = null;
    state = SyncState.off;
    notifyListeners();
  }

  Future<void> use(SyncProvider p, {String? token}) async {
    _provider = p;
    _conflictRemote = null;
    error = null;
    await _saveConfig(p, token: token);
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    state = SyncState.idle;
    notifyListeners();
    await syncNow();
  }

  Future<void> disconnect() async {
    _provider = null;
    _periodic?.cancel();
    _conflictRemote = null;
    state = SyncState.off;
    error = null;
    if (await _configFile.exists()) await _configFile.delete();
    notifyListeners();
  }

  void _onVaultChanged() {
    if (_provider == null || vault.status != VaultStatus.unlocked) return;
    if (vault.revision == _syncedRevision) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () {
      if (vault.revision != _syncedRevision) syncNow();
    });
  }

  // ---------------------------------------------------------------- sync

  Future<void> syncNow() async {
    final p = _provider;
    if (p == null || vault.status != VaultStatus.unlocked) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final remote = await p.download();
      if (remote != null) {
        if (!vault.sharesKeyWith(remote)) {
          _conflictRemote = remote;
          state = SyncState.conflict;
          error = 'The cloud copy was created by another vault.';
          return;
        }
        await vault.mergeRemote(remote);
      }
      await vault.flush();
      final local = vault.exportForSync();
      if (remote == null || jsonEncode(local) != jsonEncode(remote)) {
        await p.upload(local);
      }
      _syncedRevision = vault.revision;
      lastSync = DateTime.now();
      error = null;
      state = SyncState.idle;
    } catch (e) {
      error = '$e';
      state = SyncState.error;
      debugPrint('sync: $e');
    } finally {
      _running = false;
      notifyListeners();
      if (_again) {
        _again = false;
        unawaited(syncNow());
      }
    }
  }

  /// Conflict resolution: keep this Mac's vault and overwrite the cloud copy.
  Future<void> replaceCloudWithLocal() async {
    final p = _provider;
    if (p == null) return;
    await vault.flush();
    await p.upload(vault.exportForSync());
    _conflictRemote = null;
    await syncNow();
  }

  /// Conflict resolution: switch this Mac to the cloud vault. Needs that
  /// vault's master password. Throws [WrongPasswordException].
  Future<void> adoptCloud(String password) async {
    final remote = _conflictRemote;
    final p = _provider;
    if (remote == null || p == null) return;
    final token = await _readToken();
    await vault.adoptRemote(remote, password);
    await _saveConfig(p, token: token); // re-seal with the adopted key
    _conflictRemote = null;
    await syncNow();
  }

  // ---------------------------------------------------------------- config

  Future<void> _saveConfig(SyncProvider p, {String? token}) async {
    final c = p.toConfig();
    if (token != null) c['token'] = (await vault.sealLocal(token)).toJson();
    await _configFile.writeAsString(jsonEncode(c));
  }

  Future<String?> _readToken() async {
    try {
      final c = jsonDecode(await _configFile.readAsString()) as Map<String, dynamic>;
      final t = c['token'];
      if (t is! Map<String, dynamic>) return null;
      return await vault.openLocal(SealedBox.fromJson(t));
    } catch (_) {
      return null;
    }
  }

  Future<SyncProvider?> _loadConfig() async {
    try {
      if (!await _configFile.exists()) return null;
      final c = jsonDecode(await _configFile.readAsString()) as Map<String, dynamic>;
      switch (c['type']) {
        case 'folder':
          return FolderSyncProvider.fromConfig(c);
        case 'github':
          final token = await _readToken();
          if (token == null) {
            error = 'GitHub token unavailable. Connect again.';
            return null;
          }
          return GitHubSyncProvider(
            token: token,
            owner: c['owner'] as String,
            repo: c['repo'] as String,
          );
      }
    } catch (e) {
      debugPrint('sync config: $e');
    }
    return null;
  }
}
