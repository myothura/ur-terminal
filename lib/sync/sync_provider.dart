/// A place the encrypted vault is mirrored to.
///
/// Providers only move opaque JSON: the payload is `Vault.exportForSync()`,
/// already end-to-end encrypted with the master-password-derived key.
abstract class SyncProvider {
  /// Stable type id stored in sync.json.
  String get type;

  /// Short human label, e.g. "iCloud Drive" or "GitHub myothura/ur-terminal-vault".
  String get title;

  /// Returns null when nothing has been uploaded yet.
  Future<Map<String, dynamic>?> download();

  Future<void> upload(Map<String, dynamic> vaultJson);

  /// Serializable settings (secrets are sealed by the caller).
  Map<String, dynamic> toConfig();
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}
