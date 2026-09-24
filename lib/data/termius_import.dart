import 'dart:convert';
import 'dart:io';

import '../core/ids.dart';
import '../core/keygen.dart';
import 'models.dart';
import 'ssh_config_import.dart';
import 'termius_db_import.dart';
import 'vault.dart';

/// Imports the `hosts.json` written by termius-local-export
/// (https://github.com/ZeroP27/termius-local-export).
///
/// Each entry: alias, label, address, port, username, password,
/// identityFile (path to an exported private key), group.
class TermiusImporter {
  TermiusImporter(this.vault);

  final Vault vault;

  static String get _dir =>
      '${Platform.environment['HOME'] ?? ''}/termius-export';

  /// Prefers the full decrypted dump (hosts, keys, tags, snippets, tunnels,
  /// known hosts); falls back to the tool's normalized hosts.json.
  static String get defaultPath {
    final dump = File('$_dir/decrypted-indexeddb.json');
    return dump.existsSync() ? dump.path : '$_dir/hosts.json';
  }

  Future<ImportReport> importFile(String path) async {
    final report = ImportReport();
    final file = File(_expand(path));
    if (!await file.exists()) {
      report.warnings.add('${file.path} not found');
      return report;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (TermiusDbImporter.looksLikeDump(decoded)) {
      return TermiusDbImporter(vault)
          .importDump((decoded as Map).cast<String, dynamic>());
    }
    final List<dynamic> entries = switch (decoded) {
      {'hosts': final List<dynamic> h} => h,
      final List<dynamic> l => l,
      _ => const [],
    };
    if (entries.isEmpty) {
      report.warnings.add('No hosts found in ${file.path}');
      return report;
    }

    // Skip hosts that already exist (same address + port + user).
    final existing = {
      for (final h in vault.hosts) '${h.address}:${h.port}:${h.username ?? ''}',
    };
    final groupIds = {for (final g in vault.groups) g.name: g.id};
    final keyIds = <String, String>{}; // key file path or pem -> key id
    for (final k in vault.keys) {
      keyIds[k.privatePem.trim()] = k.id;
    }

    for (final raw in entries) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();
      final address = (e['address'] as String? ?? '').trim();
      if (address.isEmpty) continue;
      final port = switch (e['port']) {
        final int p => p,
        final String s => int.tryParse(s) ?? 22,
        _ => 22,
      };
      final username = _s(e['username']);
      final sig = '$address:$port:${username ?? ''}';
      if (existing.contains(sig)) {
        report.warnings.add('Skipped ${e['label'] ?? address} (exists)');
        continue;
      }

      String? groupId;
      final groupName = _s(e['group']);
      if (groupName != null) {
        groupId = groupIds[groupName];
        if (groupId == null) {
          groupId = newId();
          await vault.put(HostGroup(id: groupId, name: groupName));
          groupIds[groupName] = groupId;
        }
      }

      String? keyId;
      final keyPath = _s(e['identityFile']);
      if (keyPath != null) {
        // The export folder may have been moved: fall back to keys/<name>
        // next to hosts.json.
        var resolved = _expand(keyPath);
        if (!await File(resolved).exists()) {
          resolved = '${file.parent.path}/keys/${resolved.split('/').last}';
        }
        keyId = await _importKey(resolved, keyIds, report);
      }

      await vault.put(Host(
        id: newId(),
        label: _s(e['label']) ?? _s(e['alias']) ?? address,
        address: address,
        port: port,
        username: username,
        password: _s(e['password']),
        keyId: keyId,
        groupId: groupId,
        tags: const ['termius'],
      ));
      existing.add(sig);
      report.hosts++;
    }
    return report;
  }

  Future<String?> _importKey(
    String path,
    Map<String, String> keyIds,
    ImportReport report,
  ) async {
    final f = File(_expand(path));
    if (!await f.exists()) {
      report.warnings.add('Key file $path not found');
      return null;
    }
    final pem = (await f.readAsString()).trim();
    final known = keyIds[pem];
    if (known != null) return known;

    final name = f.path.split('/').last;
    String? pub;
    String? type;
    try {
      final info = KeyTools.inspect(pem, comment: name);
      pub = info.publicLine;
      type = info.type;
    } catch (_) {
      // Encrypted: passphrase is asked on first connect.
    }
    final key = SshKey(
      id: newId(),
      label: name,
      privatePem: '$pem\n',
      publicLine: pub,
      type: type,
    );
    await vault.put(key);
    keyIds[pem] = key.id;
    report.keys++;
    return key.id;
  }

  static String? _s(Object? v) {
    final s = (v is String) ? v.trim() : null;
    return (s == null || s.isEmpty) ? null : s;
  }

  static String _expand(String p) {
    final home = Platform.environment['HOME'] ?? '';
    var v = p.trim();
    if (v.startsWith('~/')) v = '$home${v.substring(1)}';
    return v;
  }
}
