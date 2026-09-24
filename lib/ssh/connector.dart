import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/ids.dart';
import '../core/keygen.dart';
import '../core/totp.dart';
import '../data/models.dart';
import '../data/vault.dart';

/// UI hooks the connector needs. Implemented by the app shell so the SSH layer
/// stays free of Flutter widgets.
abstract class SshPrompter {
  Future<bool> trustNewHostKey(String endpoint, String type, String fingerprint);

  Future<bool> acceptChangedHostKey(
    String endpoint,
    String type,
    String oldFingerprint,
    String newFingerprint,
  );

  /// Returns null when the user cancels.
  Future<String?> askText(String title, String prompt, {bool secret = true});
}

class SshConnectException implements Exception {
  SshConnectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Effective credentials after merging host fields with its identity.
class Credentials {
  const Credentials({this.username, this.password, this.key});
  final String? username;
  final String? password;
  final SshKey? key;
}

/// A live authenticated client plus the jump-host clients it rides on.
class SshConnection {
  SshConnection(this.client, this.chain, this.host);

  final SSHClient client;
  final List<SSHClient> chain;
  final Host host;

  Future<void> get done => client.done;
  bool get isClosed => client.isClosed;

  void close() {
    client.close();
    for (final c in chain.reversed) {
      c.close();
    }
  }
}

class SshConnector {
  SshConnector(this.vault, this.prompter);

  final Vault vault;
  final SshPrompter prompter;

  static const _maxJumpDepth = 6;

  Credentials resolve(Host host) {
    final identity = vault.byId<Identity>(host.identityId);
    final keyId = host.keyId ?? identity?.keyId;
    return Credentials(
      username: host.username ?? identity?.username,
      password: host.password ?? identity?.password,
      key: vault.byId<SshKey>(keyId),
    );
  }

  Future<SshConnection> connect(
    Host host, {
    void Function(String line)? log,
    int depth = 0,
  }) async {
    if (depth > _maxJumpDepth) {
      throw SshConnectException('Jump host chain is too deep (loop?)');
    }

    final creds = resolve(host);
    var username = creds.username;
    if (username == null || username.isEmpty) {
      username = await prompter.askText(
        'Username',
        'Username for ${host.displayName}',
        secret: false,
      );
      if (username == null || username.isEmpty) {
        throw SshConnectException('Cancelled');
      }
    }

    final identities =
        creds.key == null ? null : await _loadKey(creds.key!, host);

    final chain = <SSHClient>[];
    SSHSocket socket;
    final jump = vault.byId<Host>(host.jumpHostId);
    if (jump != null) {
      log?.call('Connecting via jump host ${jump.displayName}');
      final via = await connect(jump, log: log, depth: depth + 1);
      chain
        ..addAll(via.chain)
        ..add(via.client);
      try {
        socket = await via.client.forwardLocal(host.address, host.port);
      } catch (e) {
        via.close();
        throw SshConnectException(
            'Jump host could not reach ${host.address}:${host.port}: $e');
      }
    } else {
      log?.call('Connecting to ${host.address}:${host.port}');
      try {
        socket = await SSHSocket.connect(
          host.address,
          host.port,
          timeout: const Duration(seconds: 12),
        ).timeout(const Duration(seconds: 15));
      } catch (e) {
        throw SshConnectException(
            'Cannot reach ${host.address}:${host.port} ($e)');
      }
    }

    log?.call('TCP connected, negotiating keys');
    var passwordAttempts = 0;
    final endpoint = '${host.address}:${host.port}';

    final client = SSHClient(
      socket,
      username: username,
      identities: identities,
      keepAliveInterval: Duration(seconds: host.keepAliveSeconds.clamp(5, 300)),
      handshakeTimeout: const Duration(seconds: 20),
      // Generous: covers the time the user spends in password / 2FA dialogs.
      authTimeout: const Duration(minutes: 3),
      ident: 'UrTerminal_0.1',
      printDebug: kDebugMode ? (m) => _debug(host.address, m) : null,
      onAuthenticated: () => log?.call('Authenticated as $username'),
      onVerifyHostKey: (type, fingerprint) =>
          _verifyHostKey(endpoint, type, fingerprint),
      onPasswordRequest: () async {
        passwordAttempts++;
        if (passwordAttempts == 1 && creds.password != null) {
          return creds.password;
        }
        return prompter.askText(
          'Password',
          'Password for $username@${host.address}',
        );
      },
      onUserInfoRequest: (request) => _answerInteractive(
        request,
        host,
        creds,
      ),
      onUserauthBanner: (banner) => log?.call(banner.trimRight()),
    );

    try {
      await client.authenticated;
    } catch (e) {
      client.close();
      for (final c in chain.reversed) {
        c.close();
      }
      throw SshConnectException(_describe(e));
    }
    return SshConnection(client, chain, host);
  }

  Future<List<SSHKeyPair>> _loadKey(SshKey key, Host host) async {
    final pem = key.privatePem;
    var passphrase = key.passphrase;
    if (passphrase == null && SSHKeyPair.isEncryptedPem(pem)) {
      passphrase = await prompter.askText(
        'Key passphrase',
        'Passphrase for key "${key.label}"',
      );
      if (passphrase == null) throw SshConnectException('Cancelled');
    }
    try {
      // bcrypt-protected keys are CPU heavy to open; keep the UI smooth.
      return await KeyTools.parseInBackground(pem, passphrase);
    } catch (e) {
      throw SshConnectException('Cannot load key "${key.label}": $e');
    }
  }

  Future<bool> _verifyHostKey(
    String endpoint,
    String type,
    Uint8List fingerprintBytes,
  ) async {
    final fp = utf8.decode(fingerprintBytes, allowMalformed: true);
    debugPrint('[ssh $endpoint] host key $type $fp');
    final known = vault.knownHostFor(endpoint);
    if (known != null && known.fingerprint == fp) return true;

    final bool accepted;
    if (known == null) {
      accepted = await prompter.trustNewHostKey(endpoint, type, fp);
    } else {
      accepted = await prompter.acceptChangedHostKey(
          endpoint, type, known.fingerprint, fp);
    }
    if (accepted) {
      await vault.put(KnownHost(
        id: known?.id ?? newId(),
        endpoint: endpoint,
        keyType: type,
        fingerprint: fp,
        addedAt: DateTime.now(),
      ));
    }
    return accepted;
  }

  Future<List<String>?> _answerInteractive(
    SSHUserInfoRequest request,
    Host host,
    Credentials creds,
  ) async {
    final answers = <String>[];
    for (final prompt in request.prompts) {
      final text = prompt.promptText;
      final lower = text.toLowerCase();
      if (host.totpSecret != null && Totp.looksLikeOtpPrompt(text)) {
        answers.add(await Totp.generate(host.totpSecret!));
      } else if (lower.contains('password') && creds.password != null) {
        answers.add(creds.password!);
      } else {
        final a = await prompter.askText(
          request.name.isNotEmpty ? request.name : host.displayName,
          [
            if (request.instruction.isNotEmpty) request.instruction,
            text.trim(),
          ].join('\n'),
          secret: !prompt.echo,
        );
        if (a == null) return null;
        answers.add(a);
      }
    }
    return answers;
  }

  /// Handshake / auth diagnostics only; per-packet chatter is dropped.
  static void _debug(String address, String? m) {
    if (m == null) return;
    if (m.contains('SSHChannel') ||
        m.contains('_processPackets') ||
        m.contains('_consumeEncryptedPacket') ||
        m.contains('_sendWindowAdjust') ||
        m.contains('_uploadLoop')) {
      return;
    }
    debugPrint('[ssh $address] $m');
  }

  static String _describe(Object e) {
    if (e is SSHAuthFailError) return 'Authentication failed: ${e.message}';
    if (e is SSHAuthAbortError) return 'Authentication aborted: ${e.message}';
    if (e is SSHHostkeyError) return 'Host key rejected';
    if (e is SSHHandshakeError && e.message.contains('timed out')) {
      return 'No SSH reply from server (TCP connected, but no SSH banner '
          'within 20s). Check the port, or a VPN / proxy on this Mac that '
          'intercepts the connection.';
    }
    return e.toString();
  }
}
