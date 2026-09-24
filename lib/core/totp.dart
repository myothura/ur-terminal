import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// RFC 6238 TOTP (Google Authenticator compatible: SHA1, 6 digits, 30s).
class Totp {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static bool isValidSecret(String secret) {
    try {
      return base32Decode(secret).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static List<int> base32Decode(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in clean.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) throw FormatException('Invalid base32 character: $ch');
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out;
  }

  static Future<String> generate(String secret, {DateTime? at}) async {
    final key = base32Decode(secret);
    final time = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 ~/ 30;
    final msg = ByteData(8)..setUint64(0, time);
    final mac = await Hmac.sha1().calculateMac(
      msg.buffer.asUint8List(),
      secretKey: SecretKey(key),
    );
    final h = mac.bytes;
    final offset = h[h.length - 1] & 0x0f;
    final code = ((h[offset] & 0x7f) << 24) |
        ((h[offset + 1] & 0xff) << 16) |
        ((h[offset + 2] & 0xff) << 8) |
        (h[offset + 3] & 0xff);
    return (code % 1000000).toString().padLeft(6, '0');
  }

  /// Heuristic for keyboard-interactive prompts that ask for a one-time code.
  static bool looksLikeOtpPrompt(String prompt) {
    final p = prompt.toLowerCase();
    return p.contains('verification code') ||
        p.contains('one-time') ||
        p.contains('one time') ||
        p.contains('otp') ||
        p.contains('2fa') ||
        p.contains('authenticator') ||
        p.contains('token');
  }
}
