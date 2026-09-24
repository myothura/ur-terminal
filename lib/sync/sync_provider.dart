import '../data/vault.dart';

/// A place the encrypted vault can be mirrored to.
///
/// Implementations (Phase 2):
///  * Google Drive `appDataFolder`   (Google Sign-In, scope drive.appdata)
///  * GitHub private repo            (OAuth Device Flow, commit per sync)
///  * iCloud CloudKit private DB     (Sign in with Apple, native channel)
///
/// Providers only move opaque bytes: the payload is [Vault.exportForSync],
/// which is already end-to-end encrypted with the master-password-derived key.
abstract class SyncProvider {
  String get id;
  String get title;

  Future<bool> get isSignedIn;
  Future<void> signIn();
  Future<void> signOut();

  /// Returns null when nothing has been uploaded yet.
  Future<Map<String, dynamic>?> download();
  Future<void> upload(Map<String, dynamic> vaultJson);
}

class SyncEngine {
  SyncEngine(this.vault);

  final Vault vault;

  /// Pull, merge per record (last write wins by HLC stamp), push.
  Future<void> syncOnce(SyncProvider provider) async {
    final remote = await provider.download();
    if (remote != null) {
      await vault.mergeRemote(remote);
    }
    await vault.flush();
    await provider.upload(vault.exportForSync());
  }
}
