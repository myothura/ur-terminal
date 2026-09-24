import 'dart:io';

import '../core/ids.dart';
import '../core/keygen.dart';
import 'models.dart';
import 'vault.dart';

class ImportReport {
  int hosts = 0;
  int keys = 0;
  final List<String> warnings = [];
}

/// Imports concrete `Host` blocks from `~/.ssh/config` (wildcards skipped).
class SshConfigImporter {
  SshConfigImporter(this.vault);

  final Vault vault;

  static String get defaultPath =>
      '${Platform.environment['HOME'] ?? ''}/.ssh/config';

  Future<ImportReport> importFile([String? path]) async {
    final report = ImportReport();
    final file = File(path ?? defaultPath);
    if (!await file.exists()) {
      report.warnings.add('${file.path} not found');
      return report;
    }

    final blocks = _parse(await file.readAsLines());
    final existing = {for (final h in vault.hosts) h.label: h};
    final keyByPath = <String, String>{};
    final idByAlias = <String, String>{};
    final pendingJumps = <String, String>{};

    for (final b in blocks) {
      if (existing.containsKey(b.alias)) {
        report.warnings.add('Skipped "${b.alias}" (already exists)');
        continue;
      }
      String? keyId;
      final identityFile = b.opts['identityfile'];
      if (identityFile != null) {
        final keyPath = _expand(identityFile);
        keyId = keyByPath[keyPath];
        if (keyId == null) {
          keyId = await _importKey(keyPath, report);
          if (keyId != null) keyByPath[keyPath] = keyId;
        }
      }
      final host = Host(
        id: newId(),
        label: b.alias,
        address: b.opts['hostname'] ?? b.alias,
        port: int.tryParse(b.opts['port'] ?? '') ?? 22,
        username: b.opts['user'],
        keyId: keyId,
        tags: const ['imported'],
      );
      idByAlias[b.alias] = host.id;
      final jump = b.opts['proxyjump'];
      if (jump != null && jump.toLowerCase() != 'none') {
        pendingJumps[host.id] = jump.split(',').first.split('@').last.trim();
      }
      await vault.put(host);
      report.hosts++;
    }

    for (final e in pendingJumps.entries) {
      final jumpId = idByAlias[e.value] ?? existing[e.value]?.id;
      final host = vault.byId<Host>(e.key);
      if (jumpId == null || host == null) {
        report.warnings.add('ProxyJump "${e.value}" not found in config');
        continue;
      }
      await vault.put(host.copyWith(jumpHostId: jumpId));
    }
    return report;
  }

  Future<String?> _importKey(String path, ImportReport report) async {
    final f = File(path);
    if (!await f.exists()) {
      report.warnings.add('Key $path not found');
      return null;
    }
    final pem = await f.readAsString();
    String? pub;
    String? type;
    try {
      final info = KeyTools.inspect(pem, comment: path.split('/').last);
      pub = info.publicLine;
      type = info.type;
    } catch (_) {
      // Encrypted key: keep it, passphrase will be asked on first connect.
      final pubFile = File('$path.pub');
      if (await pubFile.exists()) pub = (await pubFile.readAsString()).trim();
    }
    final key = SshKey(
      id: newId(),
      label: path.split('/').last,
      privatePem: pem,
      publicLine: pub,
      type: type,
    );
    await vault.put(key);
    report.keys++;
    return key.id;
  }

  static String _expand(String p) {
    final home = Platform.environment['HOME'] ?? '';
    var v = p.replaceAll('"', '');
    if (v.startsWith('~/')) v = '$home${v.substring(1)}';
    return v;
  }

  static List<_Block> _parse(List<String> lines) {
    final blocks = <_Block>[];
    List<_Block> current = [];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = RegExp(r'^(\S+)\s*[= ]\s*(.+)$').firstMatch(line);
      if (m == null) continue;
      final key = m.group(1)!.toLowerCase();
      final value = m.group(2)!.trim();
      if (key == 'host') {
        current = [
          for (final alias in value.split(RegExp(r'\s+')))
            if (!alias.contains('*') &&
                !alias.contains('?') &&
                !alias.startsWith('!'))
              _Block(alias),
        ];
        blocks.addAll(current);
      } else if (key == 'match') {
        current = [];
      } else {
        for (final b in current) {
          b.opts.putIfAbsent(key, () => value);
        }
      }
    }
    return blocks;
  }
}

class _Block {
  _Block(this.alias);
  final String alias;
  final Map<String, String> opts = {};
}
