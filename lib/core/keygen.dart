import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';

class GeneratedKey {
  const GeneratedKey(this.privatePem, this.publicLine, this.type);
  final String privatePem;
  final String publicLine;
  final String type;
}

class KeyTools {
  KeyTools._();

  /// Generates an OpenSSH-format Ed25519 key pair.
  static Future<GeneratedKey> generateEd25519(String comment) async {
    final pair = await Ed25519().newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final pub = (await pair.extractPublicKey()).bytes;
    final keyPair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(pub),
      Uint8List.fromList([...seed, ...pub]),
      comment,
    );
    return GeneratedKey(
      keyPair.toPem(),
      publicLineOf(keyPair, comment),
      'ssh-ed25519',
    );
  }

  static String publicLineOf(SSHKeyPair pair, String comment) {
    final blob = base64.encode(pair.toPublicKey().encode());
    return '${pair.name} $blob${comment.isEmpty ? '' : ' $comment'}';
  }

  /// Validates a pasted private key and derives its public line.
  /// Throws when the key cannot be parsed or the passphrase is wrong.
  static ({String publicLine, String type}) inspect(
    String pem, {
    String? passphrase,
    String comment = '',
  }) {
    final pairs = SSHKeyPair.fromPem(pem.trim(), passphrase);
    if (pairs.isEmpty) throw const FormatException('No key found');
    final p = pairs.first;
    return (publicLine: publicLineOf(p, comment), type: p.name);
  }

  /// [inspect] on a background isolate (bcrypt key decryption is slow).
  static Future<({String publicLine, String type})> inspectInBackground(
    String pem, {
    String? passphrase,
    String comment = '',
  }) =>
      Isolate.run(
          () => inspect(pem, passphrase: passphrase, comment: comment));

  /// Parses a private key on a background isolate.
  static Future<List<SSHKeyPair>> parseInBackground(
          String pem, String? passphrase) =>
      Isolate.run(() => SSHKeyPair.fromPem(pem, passphrase));
}
