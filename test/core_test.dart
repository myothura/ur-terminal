import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ur_terminal/core/ids.dart';
import 'package:ur_terminal/core/keygen.dart';
import 'package:ur_terminal/core/totp.dart';
import 'package:ur_terminal/core/vault_crypto.dart';
import 'package:ur_terminal/data/models.dart';

void main() {
  group('TOTP', () {
    test('RFC 6238 SHA1 vector (6 digits)', () async {
      // ASCII "12345678901234567890" in base32.
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final code = await Totp.generate(
        secret,
        at: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true),
      );
      expect(code, '287082');
    });

    test('rejects invalid secrets', () {
      expect(Totp.isValidSecret('not base32 1!'), isFalse);
      expect(Totp.isValidSecret('JBSWY3DPEHPK3PXP'), isTrue);
    });
  });

  group('VaultCrypto', () {
    final fastKdf = KdfParams(salt: randomBytes(16), memoryKiB: 64, iterations: 1);

    test('wrap / unwrap data key', () async {
      final kek = await VaultCrypto.deriveKek('correct horse', fastKdf);
      final dek = VaultCrypto.newDataKey();
      final wrapped = await VaultCrypto.wrapKey(kek, dek);
      expect(await VaultCrypto.unwrapKey(kek, wrapped), dek);

      final wrong = await VaultCrypto.deriveKek('wrong', fastKdf);
      expect(() => VaultCrypto.unwrapKey(wrong, wrapped),
          throwsA(isA<WrongPasswordException>()));
    });

    test('record round trip is bound to its AAD', () async {
      final key = VaultCrypto.newDataKey();
      final aad = utf8.encode('id1|host');
      final box = await VaultCrypto.sealJson(key, {'a': 1}, aad: aad);
      expect(await VaultCrypto.openJson(key, box, aad: aad), {'a': 1});
      expect(
        () => VaultCrypto.openJson(key, box, aad: utf8.encode('id2|host')),
        throwsA(anything),
      );
    });
  });

  test('HLC stamps are monotonic and comparable', () {
    final hlc = Hlc('node');
    final a = hlc.now();
    final b = hlc.now();
    expect(b.compareTo(a) > 0, isTrue);
    hlc.observe('9999999999999-0000-other');
    expect(hlc.now().compareTo('9999999999999-0000-other') > 0, isTrue);
  });

  test('snippet placeholders', () {
    const s = Snippet(
      id: 'x',
      label: 'l',
      command: 'tail -n {{lines}} {{ file }} && echo {{lines}}',
    );
    expect(s.variables, ['lines', 'file']);
    expect(s.render({'lines': '50', 'file': '/var/log/syslog'}),
        'tail -n 50 /var/log/syslog && echo 50');
  });

  test('Ed25519 key generation produces a parseable OpenSSH key', () async {
    final g = await KeyTools.generateEd25519('test@ur');
    expect(g.publicLine, startsWith('ssh-ed25519 AAAA'));
    final info = KeyTools.inspect(g.privatePem, comment: 'test@ur');
    expect(info.publicLine, g.publicLine);
  });
}
