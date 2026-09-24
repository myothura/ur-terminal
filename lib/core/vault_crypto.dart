import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';

import 'ids.dart';

/// Argon2id parameters stored alongside the vault so they can be raised later
/// without breaking existing vaults.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  factory KdfParams.fresh() => KdfParams(salt: randomBytes(16));

  factory KdfParams.fromJson(Map<String, dynamic> j) => KdfParams(
        salt: base64.decode(j['salt'] as String),
        memoryKiB: j['m'] as int,
        iterations: j['t'] as int,
        parallelism: j['p'] as int,
      );

  final List<int> salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() => {
        'alg': 'argon2id',
        'salt': base64.encode(salt),
        'm': memoryKiB,
        't': iterations,
        'p': parallelism,
      };
}

/// AEAD sealed payload (XChaCha20-Poly1305).
class SealedBox {
  const SealedBox(this.nonce, this.cipherText, this.mac);

  factory SealedBox.fromJson(Map<String, dynamic> j) => SealedBox(
        base64.decode(j['n'] as String),
        base64.decode(j['c'] as String),
        base64.decode(j['m'] as String),
      );

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, dynamic> toJson() => {
        'n': base64.encode(nonce),
        'c': base64.encode(cipherText),
        'm': base64.encode(mac),
      };
}

class WrongPasswordException implements Exception {
  @override
  String toString() => 'Wrong master password';
}

/// Zero-knowledge crypto for the vault.
///
/// master password --Argon2id--> KEK --wraps--> random 256-bit data key (DEK)
/// DEK --XChaCha20-Poly1305--> every record (record id + kind bound as AAD)
///
/// Changing the master password only re-wraps the DEK. Cloud backends only
/// ever see sealed records, the wrapped DEK and the KDF salt.
class VaultCrypto {
  VaultCrypto._();

  static final Cipher _aead = Xchacha20.poly1305Aead();

  static Future<List<int>> deriveKek(String password, KdfParams p) {
    final salt = List<int>.from(p.salt);
    final m = p.memoryKiB, t = p.iterations, par = p.parallelism;
    // Argon2id is deliberately slow; keep it off the UI isolate.
    return Isolate.run(() async {
      final kdf = Argon2id(
        parallelism: par,
        memory: m,
        iterations: t,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );
      return key.extractBytes();
    });
  }

  static List<int> newDataKey() => randomBytes(32);

  static Future<SealedBox> seal(
    List<int> key,
    List<int> plain, {
    List<int> aad = const [],
  }) async {
    final box = await _aead.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: randomBytes(24),
      aad: aad,
    );
    return SealedBox(box.nonce, box.cipherText, box.mac.bytes);
  }

  static Future<List<int>> open(
    List<int> key,
    SealedBox sealed, {
    List<int> aad = const [],
  }) {
    return _aead.decrypt(
      SecretBox(sealed.cipherText,
          nonce: sealed.nonce, mac: Mac(sealed.mac)),
      secretKey: SecretKey(key),
      aad: aad,
    );
  }

  static Future<SealedBox> sealJson(
    List<int> key,
    Map<String, dynamic> json, {
    List<int> aad = const [],
  }) =>
      seal(key, utf8.encode(jsonEncode(json)), aad: aad);

  static Future<Map<String, dynamic>> openJson(
    List<int> key,
    SealedBox sealed, {
    List<int> aad = const [],
  }) async {
    final bytes = await open(key, sealed, aad: aad);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  static Future<SealedBox> wrapKey(List<int> kek, List<int> dek) =>
      seal(kek, dek, aad: utf8.encode('ur.dek.v1'));

  static Future<List<int>> unwrapKey(List<int> kek, SealedBox wrapped) async {
    try {
      return await open(kek, wrapped, aad: utf8.encode('ur.dek.v1'));
    } on SecretBoxAuthenticationError {
      throw WrongPasswordException();
    }
  }
}
