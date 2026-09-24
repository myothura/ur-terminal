import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../core/ids.dart';
import '../core/keygen.dart';
import 'models.dart';
import 'ssh_config_import.dart';
import 'vault.dart';

/// Imports Termius' own (decrypted) IndexedDB dump, as written by
/// `termius-local-export --write-raw-decrypted` (decrypted-indexeddb.json).
///
/// Layout (Termius desktop 9.x, App Store and DMG): one IndexedDB database
/// per entity, e.g. `hosts`, `ssh_configs`, `ssh_identities`, `keys`, `tags`,
/// `tag_hosts`, `snippets`, `pf_rules`, `known_hosts`. Rows reference each
/// other by `local_id` (bare value or `{local_id: ..}` object).
class TermiusDbImporter {
  TermiusDbImporter(this.vault);

  final Vault vault;

  static bool looksLikeDump(Object? json) =>
      json is Map && json['databases'] is List;

  late final Map<String, List<Map<String, dynamic>>> _stores;

  Future<ImportReport> importDump(Map<String, dynamic> dump) async {
    final report = ImportReport();
    _stores = _readStores(dump);

    final configs = _index('ssh_configs');
    final identities = _index('ssh_identities');
    final keys = _index('keys');
    final groups = _index('groups');
    final tags = _index('tags');

    // ssh_config -> identity link table (used when ssh_config.identity is empty).
    final configIdentity = <String, String>{};
    for (final row in _rows('ssh_config_identities')) {
      final c = _ref(row['ssh_config']);
      final i = _ref(row['identity']);
      if (c != null && i != null) configIdentity[c] = i;
    }

    // host -> tag labels
    final hostTags = <String, List<String>>{};
    for (final row in _rows('tag_hosts')) {
      final h = _ref(row['host']);
      final t = tags[_ref(row['tag'])];
      final label = _str(t?['label']);
      if (h != null && label != null) {
        hostTags.putIfAbsent(h, () => []).add(label);
      }
    }

    // ---- keys
    final keyIds = <String, String>{}; // termius key id -> vault key id
    final existingPems = {for (final k in vault.keys) k.privatePem.trim(): k.id};
    Future<String?> keyFor(String? termiusKeyId) async {
      if (termiusKeyId == null) return null;
      final cached = keyIds[termiusKeyId];
      if (cached != null) return cached;
      final k = keys[termiusKeyId];
      final pem = _str(k?['private_key'])?.trim();
      if (k == null || pem == null) return null;
      final existing = existingPems[pem];
      if (existing != null) return keyIds[termiusKeyId] = existing;
      final label = _str(k['label']) ?? 'termius-key';
      final passphrase = _str(k['passphrase']);
      String? pub = _str(k['public_key'])?.trim();
      String? type;
      try {
        final info = KeyTools.inspect(pem, passphrase: passphrase, comment: label);
        pub = info.publicLine;
        type = info.type;
      } catch (_) {}
      final key = SshKey(
        id: newId(),
        label: label,
        privatePem: '$pem\n',
        passphrase: passphrase,
        publicLine: pub,
        type: type,
      );
      await vault.put(key);
      report.keys++;
      existingPems[pem] = key.id;
      return keyIds[termiusKeyId] = key.id;
    }

    // ---- groups
    final groupIds = {for (final g in vault.groups) g.name: g.id};
    Future<String?> groupFor(Object? ref) async {
      final g = groups[_ref(ref)];
      final name = _str(g?['label']);
      if (name == null) return null;
      final existing = groupIds[name];
      if (existing != null) return existing;
      final id = newId();
      await vault.put(HostGroup(id: id, name: name));
      return groupIds[name] = id;
    }

    // ---- hosts
    final existingHosts = {
      for (final h in vault.hosts) '${h.address}:${h.port}:${h.username ?? ''}',
    };
    final hostIds = <String, String>{}; // termius host id -> vault host id
    for (final row in _rows('hosts')) {
      final address = _str(row['address']);
      if (address == null) continue;
      final termiusId = _ref(row['local_id']);
      final config = configs[_ref(row['ssh_config'])];
      final port = _int(config?['port']) ?? 22;
      final identityId = _ref(config?['identity']) ??
          configIdentity[_ref(row['ssh_config']) ?? ''];
      final identity = identities[identityId];
      final username = _str(identity?['username']);
      final sig = '$address:$port:${username ?? ''}';

      final existing = vault.hosts
          .where((h) => '${h.address}:${h.port}:${h.username ?? ''}' == sig)
          .firstOrNull;
      if (existing != null || existingHosts.contains(sig)) {
        if (termiusId != null && existing != null) {
          hostIds[termiusId] = existing.id;
        }
        report.warnings.add('Skipped ${_str(row['label']) ?? address} (exists)');
        continue;
      }

      final host = Host(
        id: newId(),
        label: _str(row['label']) ?? address,
        address: address,
        port: port,
        username: username,
        password: _str(identity?['password']),
        keyId: await keyFor(_ref(identity?['ssh_key'])),
        groupId: await groupFor(row['group']),
        tags: hostTags[termiusId ?? ''] ?? const ['termius'],
      );
      await vault.put(host);
      existingHosts.add(sig);
      if (termiusId != null) hostIds[termiusId] = host.id;
      report.hosts++;
    }

    // ---- snippets
    final existingSnippets = vault.snippets.map((s) => s.command.trim()).toSet();
    for (final row in _rows('snippets')) {
      final script = _str(row['script']);
      if (script == null || existingSnippets.contains(script.trim())) continue;
      await vault.put(Snippet(
        id: newId(),
        label: _str(row['label']) ?? script.split('\n').first,
        command: script,
      ));
      existingSnippets.add(script.trim());
      report.snippets++;
    }

    // ---- port forwarding
    for (final row in _rows('pf_rules')) {
      final hostId = hostIds[_ref(row['host']) ?? ''];
      final localPort = _int(row['local_port']);
      if (hostId == null || localPort == null) continue;
      final type = switch (_str(row['pf_type'])?.toLowerCase()) {
        'remote' || 'r' => ForwardType.remote,
        'dynamic' || 'd' => ForwardType.dynamic,
        _ => ForwardType.local,
      };
      await vault.put(ForwardRule(
        id: newId(),
        label: _str(row['label']) ?? '',
        type: type,
        hostId: hostId,
        bindHost: _str(row['bound_address']) ?? '127.0.0.1',
        bindPort: localPort,
        destHost: _str(row['hostname']) ?? '127.0.0.1',
        destPort: _int(row['remote_port']) ?? 0,
      ));
      report.forwards++;
    }

    // ---- known hosts
    for (final row in _rows('known_hosts')) {
      final names = _str(row['hostnames']);
      final keyLine = _str(row['key']);
      if (names == null || keyLine == null) continue;
      final fp = await _fingerprint(keyLine);
      if (fp == null) continue;
      for (final name in names.split(',')) {
        final endpoint = _endpoint(name.trim());
        if (endpoint == null || vault.knownHostFor(endpoint) != null) continue;
        await vault.put(KnownHost(
          id: newId(),
          endpoint: endpoint,
          keyType: fp.$1,
          fingerprint: fp.$2,
          addedAt: DateTime.now(),
        ));
        report.knownHosts++;
      }
    }
    return report;
  }

  // ------------------------------------------------------------ helpers

  static Map<String, List<Map<String, dynamic>>> _readStores(
      Map<String, dynamic> dump) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final db in dump['databases'] as List) {
      if (db is! Map) continue;
      final stores = db['stores'];
      if (stores is! Map) continue;
      for (final e in stores.entries) {
        final rows = <Map<String, dynamic>>[];
        for (final r in (e.value as List? ?? const [])) {
          if (r is! Map) continue;
          final v = r['value'];
          if (v is! Map) continue;
          final row = v.cast<String, dynamic>();
          if (_isDeleted(row)) continue;
          row.putIfAbsent('local_id', () => r['key']);
          rows.add(row);
        }
        out[e.key as String] = rows;
      }
    }
    return out;
  }

  static bool _isDeleted(Map<String, dynamic> row) {
    final s = row['status'];
    return s is String && s.toLowerCase().contains('delet');
  }

  List<Map<String, dynamic>> _rows(String store) => _stores[store] ?? const [];

  Map<String?, Map<String, dynamic>> _index(String store) => {
        for (final r in _rows(store)) _ref(r['local_id']): r,
      };

  static String? _ref(Object? v) {
    if (v == null) return null;
    if (v is Map) return _ref(v['local_id'] ?? v['id']);
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static String? _str(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) => switch (v) {
        final int i => i,
        final String s => int.tryParse(s.trim()),
        final double d => d.toInt(),
        _ => null,
      };

  /// `[1.2.3.4]:2222` -> `1.2.3.4:2222`, `1.2.3.4` -> `1.2.3.4:22`.
  static String? _endpoint(String name) {
    if (name.isEmpty || name.startsWith('|')) return null; // hashed entry
    final m = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(name);
    if (m != null) return '${m.group(1)}:${m.group(2)}';
    return '$name:22';
  }

  /// OpenSSH SHA256 fingerprint for a `type base64` public key line.
  static Future<(String, String)?> _fingerprint(String keyLine) async {
    final parts = keyLine.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    final blobText = parts.length >= 2 ? parts[1] : parts[0];
    final type = parts.length >= 2 ? parts[0] : 'unknown';
    try {
      final blob = base64.decode(blobText);
      final hash = await Sha256().hash(blob);
      final b64 = base64.encode(hash.bytes).replaceAll('=', '');
      return (type, 'SHA256:$b64');
    } catch (_) {
      return null;
    }
  }
}
