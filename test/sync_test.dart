import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ur_terminal/core/ids.dart';
import 'package:ur_terminal/core/vault_crypto.dart';
import 'package:ur_terminal/data/models.dart';
import 'package:ur_terminal/data/vault.dart';
import 'package:ur_terminal/sync/folder_provider.dart';
import 'package:ur_terminal/sync/sync_manager.dart';

const pw = 'correct horse battery';

KdfParams fastKdf() =>
    KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);

Directory tempDir() => Directory.systemTemp.createTempSync('ur_sync_test_');

Future<Vault> newVault(String node) async {
  final v = Vault.forTest(node: node);
  await v.initAt(tempDir());
  await v.create(pw, kdf: fastKdf());
  return v;
}

Future<Vault> cloneDevice(Vault source, String node) async {
  await source.flush();
  final dir = tempDir();
  File('${dir.path}/vault.json')
      .writeAsStringSync(jsonEncode(source.exportForSync()));
  final v = Vault.forTest(node: node);
  await v.initAt(dir);
  await v.unlock(pw);
  return v;
}

SyncManager manager(Vault v) {
  final m = SyncManager.forTest(v);
  addTearDown(m.disconnect);
  return m;
}

void main() {
  test('two Macs sync through a shared cloud folder', () async {
    final cloud = FolderSyncProvider(tempDir().path, label: 'test cloud');

    final a = await newVault('A');
    await a.put(const Host(id: 'h1', label: 'first', address: '10.0.0.1'));
    final syncA = manager(a);
    await syncA.use(cloud);
    expect(syncA.state, SyncState.idle, reason: syncA.error);
    expect(File('${cloud.folder}/${FolderSyncProvider.fileName}').existsSync(),
        isTrue);

    final b = await cloneDevice(a, 'B');
    final syncB = manager(b);
    await syncB.use(cloud);

    await a.put(const Host(id: 'h2', label: 'added on A', address: '10.0.0.2'));
    await syncA.syncNow();
    await syncB.syncNow();
    expect(b.byId<Host>('h2')?.label, 'added on A');

    await b.delete('h1');
    await syncB.syncNow();
    await syncA.syncNow();
    expect(a.byId<Host>('h1'), isNull);
    expect(a.hosts.map((h) => h.id), ['h2']);
  });

  test('a different vault in the cloud is a conflict, not a merge', () async {
    final cloud = FolderSyncProvider(tempDir().path, label: 'test cloud');

    final a = await newVault('A');
    await a.put(const Host(id: 'a', label: 'from A', address: '10.0.0.1'));
    await manager(a).use(cloud);

    final c = await newVault('C'); // created independently, other data key
    await c.put(const Host(id: 'c', label: 'from C', address: '10.0.0.3'));
    final syncC = manager(c);
    await syncC.use(cloud);

    expect(syncC.state, SyncState.conflict);
    expect(c.hosts.single.label, 'from C', reason: 'nothing merged');

    // Keep this Mac: cloud now holds C's vault.
    await syncC.replaceCloudWithLocal();
    expect(syncC.state, SyncState.idle, reason: syncC.error);
    final remote = await cloud.download();
    expect(c.sharesKeyWith(remote!), isTrue);
  });

  test('adopting the cloud vault needs its master password', () async {
    final cloud = FolderSyncProvider(tempDir().path, label: 'test cloud');
    final a = await newVault('A');
    await a.put(const Host(id: 'a', label: 'from A', address: '10.0.0.1'));
    await manager(a).use(cloud);

    final c = await newVault('C');
    final syncC = manager(c);
    await syncC.use(cloud);
    expect(syncC.state, SyncState.conflict);

    await expectLater(syncC.adoptCloud('wrong'),
        throwsA(isA<WrongPasswordException>()));
    await syncC.adoptCloud(pw);
    expect(syncC.state, SyncState.idle, reason: syncC.error);
    expect(c.hosts.single.label, 'from A');
  });

  test('no upload when nothing changed', () async {
    final dir = tempDir().path;
    final cloud = FolderSyncProvider(dir, label: 'test cloud');
    final a = await newVault('A');
    final sync = manager(a);
    await sync.use(cloud);

    final file = File('$dir/${FolderSyncProvider.fileName}');
    final before = file.lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await sync.syncNow();
    expect(file.lastModifiedSync(), before);
  });
}
