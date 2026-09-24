import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ids.dart';
import '../core/vault_crypto.dart';
import 'models.dart';

enum VaultStatus { loading, empty, locked, unlocked }

/// One encrypted record as stored on disk and in every sync backend.
class StoredRecord {
  const StoredRecord({
    required this.id,
    required this.kind,
    required this.stamp,
    this.deleted = false,
    this.box,
  });

  factory StoredRecord.fromJson(String id, Map<String, dynamic> j) =>
      StoredRecord(
        id: id,
        kind: recordKindFromName(j['k'] as String),
        stamp: j['u'] as String,
        deleted: j['d'] as bool? ?? false,
        box: j['b'] == null
            ? null
            : SealedBox.fromJson(j['b'] as Map<String, dynamic>),
      );

  final String id;
  final RecordKind kind;

  /// Hybrid logical clock stamp of the last change.
  final String stamp;
  final bool deleted;
  final SealedBox? box;

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'u': stamp,
        if (deleted) 'd': true,
        if (box != null) 'b': box!.toJson(),
      };
}

/// The encrypted local vault. Single source of truth for all user data.
///
/// On-disk format (also the sync payload):
/// ```json
/// {"format":"ur.vault","version":1,
///  "kdf":{...argon2id params...},
///  "dek":{sealed data key},
///  "records":{"<id>":{"k":"host","u":"<hlc>","b":{sealed json}}}}
/// ```
class Vault extends ChangeNotifier {
  Vault._();

  static final Vault instance = Vault._();

  static const formatVersion = 1;

  VaultStatus _status = VaultStatus.loading;
  VaultStatus get status => _status;

  late File _file;
  late Hlc _hlc;

  KdfParams? _kdf;
  SealedBox? _wrappedDek;
  List<int>? _dek;

  final Map<String, StoredRecord> _stored = {};
  final Map<String, VaultRecord> _records = {};

  Timer? _persistTimer;
  int _revision = 0;

  /// Increments on every change; lets widgets cheaply skip rebuild work.
  int get revision => _revision;

  String get filePath => _file.path;

  // ---------------------------------------------------------------- lifecycle

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _file = File('${dir.path}/vault.json');
    _hlc = Hlc(await _deviceNode(dir));

    if (await _file.exists()) {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      _loadHeader(j);
      _status = VaultStatus.locked;
    } else {
      _status = VaultStatus.empty;
    }
    notifyListeners();
  }

  Future<String> _deviceNode(Directory dir) async {
    final f = File('${dir.path}/device.json');
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final node = j['node'] as String?;
      if (node != null && node.isNotEmpty) return node;
    }
    final node = newId().substring(0, 8);
    await f.writeAsString(jsonEncode({'node': node}));
    return node;
  }

  void _loadHeader(Map<String, dynamic> j) {
    if (j['format'] != 'ur.vault') {
      throw const FormatException('Not an Ur.Terminal vault');
    }
    _kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
    _wrappedDek = SealedBox.fromJson(j['dek'] as Map<String, dynamic>);
    _stored
      ..clear()
      ..addAll({
        for (final e in (j['records'] as Map<String, dynamic>).entries)
          e.key: StoredRecord.fromJson(e.key, e.value as Map<String, dynamic>),
      });
    for (final r in _stored.values) {
      _hlc.observe(r.stamp);
    }
  }

  Future<void> create(String password) async {
    final kdf = KdfParams.fresh();
    final kek = await VaultCrypto.deriveKek(password, kdf);
    final dek = VaultCrypto.newDataKey();
    _kdf = kdf;
    _wrappedDek = await VaultCrypto.wrapKey(kek, dek);
    _dek = dek;
    _stored.clear();
    _records.clear();
    _status = VaultStatus.unlocked;
    await _persistNow();
    _changed();
  }

  /// Throws [WrongPasswordException] on a bad password.
  Future<void> unlock(String password) async {
    final kek = await VaultCrypto.deriveKek(password, _kdf!);
    final dek = await VaultCrypto.unwrapKey(kek, _wrappedDek!);
    _dek = dek;
    await _decryptAll();
    _status = VaultStatus.unlocked;
    _changed();
  }

  Future<void> _decryptAll() async {
    _records.clear();
    final live = _stored.values.where((r) => !r.deleted && r.box != null);
    final results = await Future.wait(live.map(_decrypt));
    for (final r in results) {
      if (r != null) _records[r.id] = r;
    }
  }

  Future<VaultRecord?> _decrypt(StoredRecord s) async {
    try {
      final json = await VaultCrypto.openJson(_dek!, s.box!, aad: _aad(s));
      return VaultRecord.fromJson(s.kind, json);
    } catch (e) {
      debugPrint('Vault: skipping unreadable record ${s.id}: $e');
      return null;
    }
  }

  Future<void> lock() async {
    await flush();
    _dek = null;
    _records.clear();
    _status = VaultStatus.locked;
    _changed();
  }

  Future<void> changePassword(String current, String next) async {
    final kek = await VaultCrypto.deriveKek(current, _kdf!);
    final dek = await VaultCrypto.unwrapKey(kek, _wrappedDek!);
    final kdf = KdfParams.fresh();
    final newKek = await VaultCrypto.deriveKek(next, kdf);
    _kdf = kdf;
    _wrappedDek = await VaultCrypto.wrapKey(newKek, dek);
    await _persistNow();
  }

  List<int> _aad(StoredRecord s) => utf8.encode('${s.id}|${s.kind.name}');

  // ---------------------------------------------------------------- writes

  Future<void> put(VaultRecord record) async {
    _requireUnlocked();
    final stamp = _hlc.now();
    final draft = StoredRecord(id: record.id, kind: record.kind, stamp: stamp);
    final box = await VaultCrypto.sealJson(
      _dek!,
      record.toJson(),
      aad: _aad(draft),
    );
    _stored[record.id] = StoredRecord(
      id: record.id,
      kind: record.kind,
      stamp: stamp,
      box: box,
    );
    _records[record.id] = record;
    _changed();
    _schedulePersist();
  }

  Future<void> delete(String id) async {
    _requireUnlocked();
    final existing = _stored[id];
    if (existing == null) return;
    _stored[id] = StoredRecord(
      id: id,
      kind: existing.kind,
      stamp: _hlc.now(),
      deleted: true,
    );
    _records.remove(id);
    _changed();
    _schedulePersist();
  }

  void _requireUnlocked() {
    if (_status != VaultStatus.unlocked || _dek == null) {
      throw StateError('Vault is locked');
    }
  }

  // ---------------------------------------------------------------- sync

  /// Serialized vault for upload to a sync backend. Already encrypted.
  Map<String, dynamic> exportForSync() => _toJson();

  /// Per-record last-write-wins merge of a vault downloaded from a backend.
  /// Returns true when anything local changed.
  Future<bool> mergeRemote(Map<String, dynamic> remote) async {
    _requireUnlocked();
    final records = remote['records'] as Map<String, dynamic>? ?? const {};
    var changed = false;
    for (final e in records.entries) {
      final incoming =
          StoredRecord.fromJson(e.key, e.value as Map<String, dynamic>);
      final local = _stored[e.key];
      if (local != null && local.stamp.compareTo(incoming.stamp) >= 0) {
        continue;
      }
      _hlc.observe(incoming.stamp);
      _stored[e.key] = incoming;
      if (incoming.deleted || incoming.box == null) {
        _records.remove(e.key);
      } else {
        final r = await _decrypt(incoming);
        if (r != null) _records[r.id] = r;
      }
      changed = true;
    }
    if (changed) {
      _changed();
      _schedulePersist();
    }
    return changed;
  }

  // ---------------------------------------------------------------- persistence

  Map<String, dynamic> _toJson() => {
        'format': 'ur.vault',
        'version': formatVersion,
        'kdf': _kdf!.toJson(),
        'dek': _wrappedDek!.toJson(),
        'records': {for (final r in _stored.values) r.id: r.toJson()},
      };

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 300), _persistNow);
  }

  Future<void> flush() async {
    if (_persistTimer?.isActive ?? false) {
      _persistTimer!.cancel();
      await _persistNow();
    }
  }

  Future<void> _persistNow() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_toJson()), flush: true);
    await tmp.rename(_file.path);
  }

  // ---------------------------------------------------------------- reads

  void _changed() {
    _revision++;
    _cache.clear();
    notifyListeners();
  }

  final Map<Type, List<VaultRecord>> _cache = {};

  List<T> _all<T extends VaultRecord>(String Function(T) sortKey) {
    final cached = _cache[T];
    if (cached != null) return cached.cast<T>();
    final list = _records.values.whereType<T>().toList()
      ..sort((a, b) =>
          sortKey(a).toLowerCase().compareTo(sortKey(b).toLowerCase()));
    _cache[T] = list;
    return list;
  }

  List<Host> get hosts => _all<Host>((h) => h.displayName);
  List<HostGroup> get groups => _all<HostGroup>((g) => g.name);
  List<Identity> get identities => _all<Identity>((i) => i.label);
  List<SshKey> get keys => _all<SshKey>((k) => k.label);
  List<Snippet> get snippets => _all<Snippet>((s) => s.label);
  List<ForwardRule> get forwards => _all<ForwardRule>((f) => f.label);
  List<KnownHost> get knownHosts => _all<KnownHost>((k) => k.endpoint);

  T? byId<T extends VaultRecord>(String? id) {
    if (id == null) return null;
    final r = _records[id];
    return r is T ? r : null;
  }

  KnownHost? knownHostFor(String endpoint) {
    for (final k in knownHosts) {
      if (k.endpoint == endpoint) return k;
    }
    return null;
  }
}
