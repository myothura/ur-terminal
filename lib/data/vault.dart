import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ids.dart';
import '../core/vault_crypto.dart';
import 'models.dart';

enum VaultStatus { loading, empty, locked, unlocked }

/// One record as stored on disk and in every sync backend.
///
/// v2 on-disk shape is only `{"b": sealed-envelope}`; the envelope holds the
/// kind, HLC stamp, deleted flag and data, padded to 256-byte buckets. So a
/// copy of the vault reveals only the number of entries and their random ids.
/// [kind], [stamp] and [deleted] are known only after decryption.
class StoredRecord {
  StoredRecord({
    required this.id,
    required this.box,
    required this.kind,
    required this.stamp,
    this.deleted = false,
  });

  final String id;
  final SealedBox box;
  final RecordKind kind;

  /// Hybrid logical clock stamp of the last change (`millis-counter-node`).
  final String stamp;
  final bool deleted;

  Map<String, dynamic> toJson() => {'b': box.toJson()};
}

/// A decrypted envelope.
class _Envelope {
  _Envelope(this.kind, this.stamp, this.deleted, this.data);
  final RecordKind kind;
  final String stamp;
  final bool deleted;
  final Map<String, dynamic>? data;
}

/// The encrypted local vault. Single source of truth for all user data.
///
/// On-disk format v2 (also the sync payload):
/// ```json
/// {"format":"ur.vault","version":2,
///  "kdf":{...argon2id params...},
///  "dek":{sealed data key},
///  "records":{"<uuid>":{"b":{"n":..,"c":..,"m":..}}}}
/// ```
/// v1 files (kind/stamp/deleted in clear) are read and upgraded on unlock.
class Vault extends ChangeNotifier {
  Vault._(this._nodeOverride);

  static final Vault instance = Vault._(null);

  /// Separate instance for tests (own directory, own HLC node).
  @visibleForTesting
  factory Vault.forTest({String node = 'test'}) => Vault._(node);

  static const formatVersion = 2;

  /// Tombstones older than this are dropped. A device offline for longer
  /// could resurrect a record it still holds; 180 days keeps that unlikely.
  static const tombstoneTtl = Duration(days: 180);

  static const _padBucket = 256;

  final String? _nodeOverride;

  VaultStatus _status = VaultStatus.loading;
  VaultStatus get status => _status;

  late File _file;
  late Hlc _hlc;

  KdfParams? _kdf;
  SealedBox? _wrappedDek;
  List<int>? _dek;

  /// Raw entries read from disk while locked (decoded at unlock).
  Map<String, dynamic> _raw = {};

  final Map<String, StoredRecord> _stored = {};
  final Map<String, VaultRecord> _records = {};

  Timer? _persistTimer;
  Future<void> _writeChain = Future.value();
  int _revision = 0;

  /// Increments on every change; lets widgets cheaply skip rebuild work.
  int get revision => _revision;

  String get filePath => _file.path;

  /// Application support directory holding the vault and device files.
  String get supportDir => _file.parent.path;

  // ---------------------------------------------------------------- lifecycle

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await initAt(dir);
  }

  Future<void> initAt(Directory dir) async {
    await dir.create(recursive: true);
    _file = File('${dir.path}/vault.json');
    _hlc = Hlc(_nodeOverride ?? await _deviceNode(dir));

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
    final version = j['version'] as int? ?? 1;
    if (version > formatVersion) {
      throw FormatException(
          'Vault format $version is newer than this app. Please update.');
    }
    _kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
    _wrappedDek = SealedBox.fromJson(j['dek'] as Map<String, dynamic>);
    _raw = Map<String, dynamic>.from(j['records'] as Map? ?? const {});
    _stored.clear();
    _records.clear();
  }

  /// [kdf] is only overridden by tests (fast Argon2 parameters).
  Future<void> create(String password, {KdfParams? kdf}) async {
    final params = kdf ?? KdfParams.fresh();
    final kek = await VaultCrypto.deriveKek(password, params);
    final dek = VaultCrypto.newDataKey();
    _kdf = params;
    _wrappedDek = await VaultCrypto.wrapKey(kek, dek);
    _dek = dek;
    _raw = {};
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
    final upgraded = await _decodeRaw(_raw);
    _raw = {};
    final collected = _collectTombstones();
    _status = VaultStatus.unlocked;
    if (upgraded || collected) await _persistNow();
    _changed();
  }

  /// Decodes raw entries into [_stored] / [_records]. Returns true when any
  /// entry was in the old v1 layout (and has been re-sealed as v2).
  Future<bool> _decodeRaw(Map<String, dynamic> raw) async {
    _stored.clear();
    _records.clear();
    var upgraded = false;
    final results = await Future.wait(raw.entries.map((e) async {
      try {
        final entry = e.value as Map<String, dynamic>;
        final isV1 = entry.containsKey('k');
        final env = await _openEntry(e.key, entry);
        final rec = isV1 ? await _reseal(e.key, env) : _toStored(e.key, entry, env);
        if (isV1) upgraded = true;
        return (rec, env);
      } catch (err) {
        debugPrint('Vault: skipping unreadable record ${e.key}: $err');
        return null;
      }
    }));
    for (final r in results) {
      if (r == null) continue;
      final (rec, env) = r;
      _hlc.observe(rec.stamp);
      _stored[rec.id] = rec;
      if (!rec.deleted && env.data != null) {
        _records[rec.id] = VaultRecord.fromJson(rec.kind, env.data!);
      }
    }
    return upgraded;
  }

  Future<void> lock() async {
    await flush();
    _raw = {for (final r in _stored.values) r.id: r.toJson()};
    _dek = null;
    _stored.clear();
    _records.clear();
    _status = VaultStatus.locked;
    _changed();
  }

  Future<void> changePassword(String current, String next,
      {KdfParams? kdf}) async {
    final kek = await VaultCrypto.deriveKek(current, _kdf!);
    final dek = await VaultCrypto.unwrapKey(kek, _wrappedDek!);
    final params = kdf ?? KdfParams.fresh();
    final newKek = await VaultCrypto.deriveKek(next, params);
    _kdf = params;
    _wrappedDek = await VaultCrypto.wrapKey(newKek, dek);
    await _persistNow();
  }

  // ---------------------------------------------------------------- envelope

  static List<int> _aadV2(String id) => utf8.encode('ur.rec.v2|$id');

  Future<SealedBox> _seal(
    String id,
    RecordKind kind,
    String stamp, {
    bool deleted = false,
    Map<String, dynamic>? data,
  }) {
    final body = <String, dynamic>{
      'k': kind.name,
      'u': stamp,
      if (deleted) 'd': true,
      'v': ?data,
    };
    // Pad to a multiple of 256 bytes so the ciphertext length does not reveal
    // the record type or size. Spaces add exactly one byte each.
    body['p'] = '';
    final len = utf8.encode(jsonEncode(body)).length;
    final target = ((len + _padBucket - 1) ~/ _padBucket) * _padBucket;
    body['p'] = ''.padRight(target - len, ' ');
    return VaultCrypto.sealJson(_dek!, body, aad: _aadV2(id));
  }

  /// Opens a v2 or v1 entry.
  Future<_Envelope> _openEntry(String id, Map<String, dynamic> entry) async {
    if (entry.containsKey('k')) {
      // v1: metadata in clear, data sealed with AAD "id|kind".
      final kind = recordKindFromName(entry['k'] as String);
      final stamp = entry['u'] as String;
      final deleted = entry['d'] as bool? ?? false;
      Map<String, dynamic>? data;
      final b = entry['b'];
      if (!deleted && b is Map<String, dynamic>) {
        data = await VaultCrypto.openJson(_dek!, SealedBox.fromJson(b),
            aad: utf8.encode('$id|${kind.name}'));
      }
      return _Envelope(kind, stamp, deleted, data);
    }
    final j = await VaultCrypto.openJson(
        _dek!, SealedBox.fromJson(entry['b'] as Map<String, dynamic>),
        aad: _aadV2(id));
    return _Envelope(
      recordKindFromName(j['k'] as String),
      j['u'] as String,
      j['d'] as bool? ?? false,
      (j['v'] as Map?)?.cast<String, dynamic>(),
    );
  }

  StoredRecord _toStored(
          String id, Map<String, dynamic> entry, _Envelope env) =>
      StoredRecord(
        id: id,
        box: SealedBox.fromJson(entry['b'] as Map<String, dynamic>),
        kind: env.kind,
        stamp: env.stamp,
        deleted: env.deleted,
      );

  Future<StoredRecord> _reseal(String id, _Envelope env) async => StoredRecord(
        id: id,
        box: await _seal(id, env.kind, env.stamp,
            deleted: env.deleted, data: env.data),
        kind: env.kind,
        stamp: env.stamp,
        deleted: env.deleted,
      );

  bool _collectTombstones() {
    final cutoff = DateTime.now().subtract(tombstoneTtl).millisecondsSinceEpoch;
    final old = _stored.values
        .where((r) => r.deleted && _stampMillis(r.stamp) < cutoff)
        .map((r) => r.id)
        .toList();
    for (final id in old) {
      _stored.remove(id);
    }
    return old.isNotEmpty;
  }

  static int _stampMillis(String stamp) =>
      int.tryParse(stamp.split('-').first) ?? 0;

  // ---------------------------------------------------------------- writes

  Future<void> put(VaultRecord record) async {
    _requireUnlocked();
    final stamp = _hlc.now();
    final box = await _seal(record.id, record.kind, stamp,
        data: record.toJson());
    _stored[record.id] = StoredRecord(
      id: record.id,
      box: box,
      kind: record.kind,
      stamp: stamp,
    );
    _records[record.id] = record;
    _changed();
    _schedulePersist();
  }

  Future<void> delete(String id) async {
    _requireUnlocked();
    final existing = _stored[id];
    if (existing == null) return;
    final stamp = _hlc.now();
    _stored[id] = StoredRecord(
      id: id,
      box: await _seal(id, existing.kind, stamp, deleted: true),
      kind: existing.kind,
      stamp: stamp,
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

  /// Per-record last-write-wins merge (by HLC stamp) of a vault downloaded
  /// from a backend. Accepts v1 and v2 payloads. Returns true when anything
  /// local changed.
  Future<bool> mergeRemote(Map<String, dynamic> remote) async {
    _requireUnlocked();
    final records = remote['records'] as Map<String, dynamic>? ?? const {};
    var changed = false;
    for (final e in records.entries) {
      final entry = e.value as Map<String, dynamic>;
      _Envelope env;
      try {
        env = await _openEntry(e.key, entry);
      } catch (err) {
        debugPrint('Vault: skipping unreadable remote record ${e.key}: $err');
        continue;
      }
      final local = _stored[e.key];
      if (local != null && local.stamp.compareTo(env.stamp) >= 0) continue;

      _hlc.observe(env.stamp);
      _stored[e.key] = entry.containsKey('k')
          ? await _reseal(e.key, env)
          : _toStored(e.key, entry, env);
      if (env.deleted || env.data == null) {
        _records.remove(e.key);
      } else {
        _records[e.key] = VaultRecord.fromJson(env.kind, env.data!);
      }
      changed = true;
    }
    if (changed) {
      _changed();
      _schedulePersist();
    }
    return changed;
  }

  /// Number of non-deleted records.
  int get liveRecordCount => _records.length;

  /// True when [remote] was encrypted with the same data key as this vault
  /// (i.e. it is a copy of this vault, possibly edited on another device).
  bool sharesKeyWith(Map<String, dynamic> remote) {
    final dek = remote['dek'];
    return dek is Map && jsonEncode(dek) == jsonEncode(_wrappedDek!.toJson());
  }

  /// Replaces this vault with [remote] (a vault created on another device),
  /// unlocking it with that vault's master password.
  /// Throws [WrongPasswordException] on a bad password.
  Future<void> adoptRemote(Map<String, dynamic> remote, String password) async {
    final kdf = KdfParams.fromJson(remote['kdf'] as Map<String, dynamic>);
    final wrapped = SealedBox.fromJson(remote['dek'] as Map<String, dynamic>);
    final kek = await VaultCrypto.deriveKek(password, kdf);
    final dek = await VaultCrypto.unwrapKey(kek, wrapped);
    _loadHeader(remote);
    _dek = dek;
    await _decodeRaw(_raw);
    _raw = {};
    _collectTombstones();
    _status = VaultStatus.unlocked;
    await _persistNow();
    _changed();
  }

  /// Seal / open small device-local secrets (e.g. sync tokens) with the
  /// vault data key.
  Future<SealedBox> sealLocal(String text) {
    _requireUnlocked();
    return VaultCrypto.seal(_dek!, utf8.encode(text),
        aad: utf8.encode('ur.local.v1'));
  }

  Future<String> openLocal(SealedBox box) async {
    _requireUnlocked();
    final bytes = await VaultCrypto.open(_dek!, box,
        aad: utf8.encode('ur.local.v1'));
    return utf8.decode(bytes);
  }

  // ---------------------------------------------------------------- persistence

  Map<String, dynamic> _toJson() => {
        'format': 'ur.vault',
        'version': formatVersion,
        'kdf': _kdf!.toJson(),
        'dek': _wrappedDek!.toJson(),
        'records': _status == VaultStatus.unlocked
            ? {for (final r in _stored.values) r.id: r.toJson()}
            : _raw,
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
    await _writeChain;
  }

  /// Writes are serialized so two saves never race on the temp file.
  Future<void> _persistNow() {
    final text = jsonEncode(_toJson());
    return _writeChain = _writeChain.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(_file.path);
    });
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
