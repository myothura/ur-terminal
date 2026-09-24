import 'dart:convert';
import 'dart:io';

import 'sync_provider.dart';

/// Syncs through a folder that a desktop client already mirrors to the cloud
/// (iCloud Drive, Google Drive for desktop, Dropbox, OneDrive, a NAS...).
class FolderSyncProvider implements SyncProvider {
  FolderSyncProvider(this.folder, {required this.label});

  factory FolderSyncProvider.fromConfig(Map<String, dynamic> c) =>
      FolderSyncProvider(c['folder'] as String, label: c['label'] as String);

  final String folder;
  final String label;

  static const fileName = 'ur-terminal-vault.json';

  File get _file => File('$folder/$fileName');

  @override
  String get type => 'folder';

  @override
  String get title => label;

  @override
  Map<String, dynamic> toConfig() =>
      {'type': type, 'folder': folder, 'label': label};

  @override
  Future<Map<String, dynamic>?> download() async {
    try {
      if (!await _file.exists()) return null;
      return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } on FileSystemException catch (e) {
      throw SyncException('Cannot read $folder: ${e.osError?.message ?? e.message}');
    }
  }

  @override
  Future<void> upload(Map<String, dynamic> vaultJson) async {
    try {
      await Directory(folder).create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(vaultJson), flush: true);
      await tmp.rename(_file.path);
    } on FileSystemException catch (e) {
      throw SyncException('Cannot write $folder: ${e.osError?.message ?? e.message}');
    }
  }

  /// Cloud folders found on this Mac, best first.
  static List<FolderSyncProvider> detect() {
    final home = Platform.environment['HOME'] ?? '';
    final found = <FolderSyncProvider>[];

    final icloud = Directory('$home/Library/Mobile Documents/com~apple~CloudDocs');
    if (icloud.existsSync()) {
      found.add(FolderSyncProvider('${icloud.path}/Ur.Terminal',
          label: 'iCloud Drive'));
    }

    final cloudStorage = Directory('$home/Library/CloudStorage');
    if (cloudStorage.existsSync()) {
      try {
        for (final e in cloudStorage.listSync()) {
          if (e is! Directory) continue;
          final name = e.path.split('/').last;
          if (name.startsWith('GoogleDrive-')) {
            final account = name.substring('GoogleDrive-'.length);
            final myDrive = Directory('${e.path}/My Drive');
            final base = myDrive.existsSync() ? myDrive.path : e.path;
            found.add(FolderSyncProvider('$base/Ur.Terminal',
                label: 'Google Drive ($account)'));
          } else if (name.startsWith('Dropbox')) {
            found.add(FolderSyncProvider('${e.path}/Ur.Terminal',
                label: 'Dropbox'));
          } else if (name.startsWith('OneDrive')) {
            found.add(FolderSyncProvider('${e.path}/Ur.Terminal',
                label: 'OneDrive'));
          }
        }
      } catch (_) {
        // Listing CloudStorage can be denied until the user approves access.
      }
    }
    return found;
  }
}
