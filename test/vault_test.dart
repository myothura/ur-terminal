import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ur_terminal/core/ids.dart';
import 'package:ur_terminal/core/vault_crypto.dart';
import 'package:ur_terminal/data/models.dart';
import 'package:ur_terminal/data/vault.dart';

const pw = 'correct horse battery';

KdfParams fastKdf() =>
    KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);

Directory tempDir() => Directory.systemTemp.createTempSync('ur_vault_test_');

Future<Vault> newVault({String node = 'A'}) async {
  final v = Vault.forTest(node: node);
  await v.initAt(tempDir());
  await v.create(pw, kdf: fastKdf());
  return v;
}

/// Second device: starts from a copy of [source]'s file.
Future<Vault> cloneDevice(Vault source, {String node = 'B'}) async {
  await source.flush();
  final dir = tempDir();
  File('${dir.path}/vault.json')
      .writeAsStringSync(jsonEncode(source.exportForSync()));
  final v = Vault.forTest(node: node);
  await v.initAt(dir);
  await v.unlock(pw);
  return v;
}

Host host(String id, String label) =>
    Host(id: id, label: label, address: '203.0.113.7', port: 2222,
        username: 'root', password: 's3cret-pass');

void main() {
  test('create, lock, reopen from disk, unlock', () async {
    final v = await newVault();
    await v.put(host('h1', 'Prod API'));
    await v.put(const Snippet(id: 's1', label: 'up', command: 'uptime'));
    await v.lock();
    expect(v.hosts, isEmpty);

    final again = Vault.forTest(node: 'A');
    await again.initAt(File(v.filePath).parent);
    expect(again.status, VaultStatus.locked);
    await again.unlock(pw);
    expect(again.hosts.single.label, 'Prod API');
    expect(again.snippets.single.command, 'uptime');
  });

  test('wrong master password is rejected', () async {
    final v = await newVault();
    await v.lock();
    await expectLater(v.unlock('nope'), throwsA(isA<WrongPasswordException>()));
  });

  test('v2 export leaks no metadata: only {"b": sealed} per record', () async {
    final v = await newVault();
    await v.put(host('h1', 'Prod API'));
    await v.put(const Snippet(id: 's1', label: 'restart', command: 'reboot'));
    await v.put(const HostGroup(id: 'g1', name: 'Production Servers'));
    await v.delete('s1');

    final export = v.exportForSync();
    expect(export['version'], 2);
    final text = jsonEncode(export);
    for (final leak in [
      // Only long tokens: short ones could appear in base64 by chance.
      'Prod API', '203.0.113.7', 's3cret-pass', 'reboot', 'Production',
      '"host"', '"snippet"', '"group"', '"k"', '"u"', '"d"',
    ]) {
      expect(text.contains(leak), isFalse, reason: 'leaked $leak');
    }

    final records = export['records'] as Map<String, dynamic>;
    expect(records.length, 3); // tombstone still present, indistinguishable
    for (final entry in records.values) {
      final e = entry as Map<String, dynamic>;
      expect(e.keys, ['b']);
      final cipher = base64.decode((e['b'] as Map)['c'] as String);
      expect(cipher.length % 256, 0, reason: 'padded to 256-byte buckets');
    }
  });

  test('two devices converge: adds, last-write-wins edits, deletes', () async {
    final a = await newVault(node: 'A');
    await a.put(host('shared', 'v0'));
    final b = await cloneDevice(a, node: 'B');

    // Independent adds.
    await a.put(host('onlyA', 'from A'));
    await b.put(host('onlyB', 'from B'));

    // Same record edited on both; B edits later, so B wins.
    await a.put(host('shared', 'edited on A'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.put(host('shared', 'edited on B'));

    await a.mergeRemote(b.exportForSync());
    await b.mergeRemote(a.exportForSync());

    List<String> labels(Vault v) => v.hosts.map((h) => h.label).toList()..sort();
    expect(labels(a), ['edited on B', 'from A', 'from B']);
    expect(labels(b), labels(a));

    // Delete on A reaches B.
    await a.delete('onlyB');
    expect(await b.mergeRemote(a.exportForSync()), isTrue);
    expect(b.byId<Host>('onlyB'), isNull);

    // Merging again changes nothing.
    expect(await b.mergeRemote(a.exportForSync()), isFalse);
  });

  test('vault from another device is detected and can be adopted', () async {
    final mine = await newVault(node: 'A');
    await mine.put(host('m', 'mine'));
    final other = await newVault(node: 'B');
    await other.put(host('o', 'theirs'));

    final cloud = other.exportForSync();
    expect(mine.sharesKeyWith(cloud), isFalse);

    await mine.adoptRemote(cloud, pw);
    expect(mine.hosts.single.label, 'theirs');
    expect(mine.sharesKeyWith(cloud), isTrue);
  });

  test('v1 vault is upgraded to v2 on unlock; old tombstones collected',
      () async {
    final kdf = fastKdf();
    final kek = await VaultCrypto.deriveKek(pw, kdf);
    final dek = VaultCrypto.newDataKey();
    final wrapped = await VaultCrypto.wrapKey(kek, dek);
    final live = await VaultCrypto.sealJson(dek, host('h1', 'Legacy').toJson(),
        aad: utf8.encode('h1|host'));
    final v1 = {
      'format': 'ur.vault',
      'version': 1,
      'kdf': kdf.toJson(),
      'dek': wrapped.toJson(),
      'records': {
        'h1': {'k': 'host', 'u': '${DateTime.now().millisecondsSinceEpoch}-0000-x',
            'b': live.toJson()},
        'old': {'k': 'host', 'u': '1577836800000-0000-x', 'd': true},
      },
    };
    final dir = tempDir();
    File('${dir.path}/vault.json').writeAsStringSync(jsonEncode(v1));

    final v = Vault.forTest();
    await v.initAt(dir);
    await v.unlock(pw);
    await v.flush();
    expect(v.hosts.single.label, 'Legacy');

    final onDisk = jsonDecode(File(v.filePath).readAsStringSync()) as Map;
    expect(onDisk['version'], 2);
    final records = onDisk['records'] as Map;
    expect(records.keys, ['h1']); // 2020 tombstone dropped
    expect((records['h1'] as Map).keys, ['b']);
  });

  test('v1 cloud copy (older app) merges into a v2 vault', () async {
    final kdf = fastKdf();
    final kek = await VaultCrypto.deriveKek(pw, kdf);
    final dek = VaultCrypto.newDataKey();
    final wrapped = await VaultCrypto.wrapKey(kek, dek);

    Future<Map<String, dynamic>> v1With(String label, int millis) async => {
          'format': 'ur.vault',
          'version': 1,
          'kdf': kdf.toJson(),
          'dek': wrapped.toJson(),
          'records': {
            'h1': {
              'k': 'host',
              'u': '${millis.toString().padLeft(13, '0')}-0000-old',
              'b': (await VaultCrypto.sealJson(dek, host('h1', label).toJson(),
                      aad: utf8.encode('h1|host')))
                  .toJson(),
            },
          },
        };

    final now = DateTime.now().millisecondsSinceEpoch;
    final dir = tempDir();
    File('${dir.path}/vault.json')
        .writeAsStringSync(jsonEncode(await v1With('first', now)));
    final v = Vault.forTest(node: 'new');
    await v.initAt(dir);
    await v.unlock(pw);
    expect(v.hosts.single.label, 'first');

    final newer = await v1With('edited by old app', now + 60000);
    expect(v.sharesKeyWith(newer), isTrue);
    expect(await v.mergeRemote(newer), isTrue);
    expect(v.hosts.single.label, 'edited by old app');
    // Stored back as v2.
    final entry = (v.exportForSync()['records'] as Map)['h1'] as Map;
    expect(entry.keys, ['b']);
  });

  test('device-local secrets round-trip with the vault key', () async {
    final v = await newVault();
    final box = await v.sealLocal('gho_token');
    expect(await v.openLocal(box), 'gho_token');
  });
}
