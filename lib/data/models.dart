/// Plain data records stored (encrypted) in the vault.
///
/// Every record is a JSON map with an `id`. Records are immutable; editors
/// produce a new instance via `copyWith` and hand it to the vault.
library;

enum RecordKind { group, host, identity, key, snippet, forward, knownHost }

RecordKind recordKindFromName(String name) =>
    RecordKind.values.firstWhere((k) => k.name == name);

abstract class VaultRecord {
  String get id;
  RecordKind get kind;
  Map<String, dynamic> toJson();

  static VaultRecord fromJson(RecordKind kind, Map<String, dynamic> j) {
    switch (kind) {
      case RecordKind.group:
        return HostGroup.fromJson(j);
      case RecordKind.host:
        return Host.fromJson(j);
      case RecordKind.identity:
        return Identity.fromJson(j);
      case RecordKind.key:
        return SshKey.fromJson(j);
      case RecordKind.snippet:
        return Snippet.fromJson(j);
      case RecordKind.forward:
        return ForwardRule.fromJson(j);
      case RecordKind.knownHost:
        return KnownHost.fromJson(j);
    }
  }
}

String? _s(Object? v) {
  final s = v as String?;
  return (s == null || s.isEmpty) ? null : s;
}

List<String> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).map((e) => e as String).toList();

// ---------------------------------------------------------------------------

class HostGroup implements VaultRecord {
  const HostGroup({required this.id, required this.name});

  factory HostGroup.fromJson(Map<String, dynamic> j) =>
      HostGroup(id: j['id'] as String, name: j['name'] as String? ?? '');

  @override
  final String id;
  final String name;

  @override
  RecordKind get kind => RecordKind.group;

  HostGroup copyWith({String? name}) =>
      HostGroup(id: id, name: name ?? this.name);

  @override
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

// ---------------------------------------------------------------------------

class Host implements VaultRecord {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    this.port = 22,
    this.username,
    this.password,
    this.keyId,
    this.identityId,
    this.groupId,
    this.jumpHostId,
    this.tags = const [],
    this.totpSecret,
    this.startupCommand,
    this.keepAliveSeconds = 15,
    this.notes,
  });

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        address: j['address'] as String? ?? '',
        port: j['port'] as int? ?? 22,
        username: _s(j['username']),
        password: _s(j['password']),
        keyId: _s(j['keyId']),
        identityId: _s(j['identityId']),
        groupId: _s(j['groupId']),
        jumpHostId: _s(j['jumpHostId']),
        tags: _list(j['tags']),
        totpSecret: _s(j['totpSecret']),
        startupCommand: _s(j['startupCommand']),
        keepAliveSeconds: j['keepAlive'] as int? ?? 15,
        notes: _s(j['notes']),
      );

  @override
  final String id;
  final String label;
  final String address;
  final int port;
  final String? username;
  final String? password;
  final String? keyId;
  final String? identityId;
  final String? groupId;

  /// Host used as ProxyJump. Chains are followed recursively.
  final String? jumpHostId;
  final List<String> tags;

  /// Base32 TOTP secret used to auto-answer keyboard-interactive 2FA prompts
  /// (libpam-google-authenticator and similar).
  final String? totpSecret;
  final String? startupCommand;
  final int keepAliveSeconds;
  final String? notes;

  @override
  RecordKind get kind => RecordKind.host;

  String get displayName => label.isNotEmpty ? label : address;

  Host copyWith({
    String? label,
    String? address,
    int? port,
    String? username,
    String? password,
    String? keyId,
    String? identityId,
    String? groupId,
    String? jumpHostId,
    List<String>? tags,
    String? totpSecret,
    String? startupCommand,
    int? keepAliveSeconds,
    String? notes,
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        address: address ?? this.address,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        keyId: keyId ?? this.keyId,
        identityId: identityId ?? this.identityId,
        groupId: groupId ?? this.groupId,
        jumpHostId: jumpHostId ?? this.jumpHostId,
        tags: tags ?? this.tags,
        totpSecret: totpSecret ?? this.totpSecret,
        startupCommand: startupCommand ?? this.startupCommand,
        keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
        notes: notes ?? this.notes,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'port': port,
        'username': username,
        'password': password,
        'keyId': keyId,
        'identityId': identityId,
        'groupId': groupId,
        'jumpHostId': jumpHostId,
        'tags': tags,
        'totpSecret': totpSecret,
        'startupCommand': startupCommand,
        'keepAlive': keepAliveSeconds,
        'notes': notes,
      };
}

// ---------------------------------------------------------------------------

/// Reusable username + credential set shared by many hosts.
class Identity implements VaultRecord {
  const Identity({
    required this.id,
    required this.label,
    required this.username,
    this.password,
    this.keyId,
  });

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: _s(j['password']),
        keyId: _s(j['keyId']),
      );

  @override
  final String id;
  final String label;
  final String username;
  final String? password;
  final String? keyId;

  @override
  RecordKind get kind => RecordKind.identity;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'username': username,
        'password': password,
        'keyId': keyId,
      };
}

// ---------------------------------------------------------------------------

class SshKey implements VaultRecord {
  const SshKey({
    required this.id,
    required this.label,
    required this.privatePem,
    this.passphrase,
    this.publicLine,
    this.type,
  });

  factory SshKey.fromJson(Map<String, dynamic> j) => SshKey(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        privatePem: j['pem'] as String? ?? '',
        passphrase: _s(j['passphrase']),
        publicLine: _s(j['pub']),
        type: _s(j['type']),
      );

  @override
  final String id;
  final String label;
  final String privatePem;
  final String? passphrase;

  /// `ssh-ed25519 AAAA... comment` line for authorized_keys.
  final String? publicLine;
  final String? type;

  @override
  RecordKind get kind => RecordKind.key;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pem': privatePem,
        'passphrase': passphrase,
        'pub': publicLine,
        'type': type,
      };
}

// ---------------------------------------------------------------------------

class Snippet implements VaultRecord {
  const Snippet({
    required this.id,
    required this.label,
    required this.command,
    this.tags = const [],
  });

  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        command: j['command'] as String? ?? '',
        tags: _list(j['tags']),
      );

  @override
  final String id;
  final String label;
  final String command;
  final List<String> tags;

  @override
  RecordKind get kind => RecordKind.snippet;

  static final _varPattern = RegExp(r'\{\{\s*([A-Za-z0-9_\-]+)\s*\}\}');

  /// Placeholder names, e.g. `{{domain}}`, in order of first appearance.
  List<String> get variables {
    final seen = <String>{};
    for (final m in _varPattern.allMatches(command)) {
      seen.add(m.group(1)!);
    }
    return seen.toList();
  }

  String render(Map<String, String> values) =>
      command.replaceAllMapped(_varPattern, (m) => values[m.group(1)!] ?? '');

  @override
  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'command': command, 'tags': tags};
}

// ---------------------------------------------------------------------------

enum ForwardType {
  local('L', 'Local'),
  remote('R', 'Remote'),
  dynamic('D', 'Dynamic SOCKS5');

  const ForwardType(this.code, this.title);
  final String code;
  final String title;
}

class ForwardRule implements VaultRecord {
  const ForwardRule({
    required this.id,
    required this.label,
    required this.type,
    required this.hostId,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.destHost = '127.0.0.1',
    this.destPort = 0,
    this.autoStart = false,
  });

  factory ForwardRule.fromJson(Map<String, dynamic> j) => ForwardRule(
        id: j['id'] as String,
        label: j['label'] as String? ?? '',
        type: ForwardType.values.firstWhere(
          (t) => t.code == j['type'],
          orElse: () => ForwardType.local,
        ),
        hostId: j['hostId'] as String? ?? '',
        bindHost: j['bindHost'] as String? ?? '127.0.0.1',
        bindPort: j['bindPort'] as int? ?? 0,
        destHost: j['destHost'] as String? ?? '127.0.0.1',
        destPort: j['destPort'] as int? ?? 0,
        autoStart: j['autoStart'] as bool? ?? false,
      );

  @override
  final String id;
  final String label;
  final ForwardType type;
  final String hostId;

  /// Local bind address for L/D, remote bind address for R.
  final String bindHost;
  final int bindPort;

  /// Target for L (as seen from the server) and R (as seen from this Mac).
  final String destHost;
  final int destPort;
  final bool autoStart;

  @override
  RecordKind get kind => RecordKind.forward;

  String get summary {
    switch (type) {
      case ForwardType.local:
        return '$bindHost:$bindPort  ->  $destHost:$destPort';
      case ForwardType.remote:
        return 'server $bindHost:$bindPort  ->  $destHost:$destPort';
      case ForwardType.dynamic:
        return 'SOCKS5 $bindHost:$bindPort';
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.code,
        'hostId': hostId,
        'bindHost': bindHost,
        'bindPort': bindPort,
        'destHost': destHost,
        'destPort': destPort,
        'autoStart': autoStart,
      };
}

// ---------------------------------------------------------------------------

class KnownHost implements VaultRecord {
  const KnownHost({
    required this.id,
    required this.endpoint,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
  });

  factory KnownHost.fromJson(Map<String, dynamic> j) => KnownHost(
        id: j['id'] as String,
        endpoint: j['endpoint'] as String? ?? '',
        keyType: j['keyType'] as String? ?? '',
        fingerprint: j['fp'] as String? ?? '',
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  @override
  final String id;

  /// `address:port`
  final String endpoint;
  final String keyType;
  final String fingerprint;
  final DateTime addedAt;

  @override
  RecordKind get kind => RecordKind.knownHost;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'endpoint': endpoint,
        'keyType': keyType,
        'fp': fingerprint,
        'addedAt': addedAt.toIso8601String(),
      };
}
