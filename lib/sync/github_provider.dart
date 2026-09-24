import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_provider.dart';

/// OAuth App client id used for the GitHub Device Flow. Client ids are
/// public by design (no secret is used by the device flow). Register one at
/// https://github.com/settings/applications/new and tick "Enable Device Flow".
/// Can be overridden in Settings for forks.
const kGitHubClientId = '';

const _api = 'https://api.github.com';
const _repoName = 'ur-terminal-vault';
const _path = 'vault.json';

class DeviceCode {
  DeviceCode(this.deviceCode, this.userCode, this.verificationUri,
      this.interval, this.expiresIn);
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;
  final int expiresIn;
}

/// Syncs the vault as `vault.json` in a private repository. Every sync is a
/// commit, so the repository history doubles as version history / rollback.
class GitHubSyncProvider implements SyncProvider {
  GitHubSyncProvider({
    required this.token,
    required this.owner,
    this.repo = _repoName,
  });

  final String token;
  final String owner;
  final String repo;

  String? _sha;

  @override
  String get type => 'github';

  @override
  String get title => 'GitHub  $owner/$repo';

  /// The token is not included: the caller seals it with the vault key.
  @override
  Map<String, dynamic> toConfig() =>
      {'type': type, 'owner': owner, 'repo': repo};

  // ---------------------------------------------------------------- auth

  static Future<DeviceCode> startDeviceFlow(String clientId) async {
    final j = await _form('https://github.com/login/device/code', {
      'client_id': clientId,
      'scope': 'repo',
    });
    if (j['device_code'] == null) {
      throw SyncException(
          'GitHub refused the device flow: ${j['error_description'] ?? j['error'] ?? j}');
    }
    return DeviceCode(
      j['device_code'] as String,
      j['user_code'] as String,
      j['verification_uri'] as String,
      (j['interval'] as num?)?.toInt() ?? 5,
      (j['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// Polls until the user approves the code in the browser.
  static Future<String> waitForToken(
    String clientId,
    DeviceCode code, {
    bool Function()? cancelled,
  }) async {
    var interval = code.interval;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) throw SyncException('Cancelled');
      final j = await _form('https://github.com/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final token = j['access_token'];
      if (token is String && token.isNotEmpty) return token;
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        default:
          throw SyncException(
              'GitHub login failed: ${j['error_description'] ?? j['error']}');
      }
    }
    throw SyncException('GitHub login timed out');
  }

  /// Resolves the account and makes sure the private vault repo exists.
  static Future<GitHubSyncProvider> connect(String token) async {
    final user = await _json('GET', '$_api/user', token: token);
    final login = user['login'] as String;
    final p = GitHubSyncProvider(token: token, owner: login);
    final repo = await _json('GET', '$_api/repos/$login/$_repoName',
        token: token, allow404: true);
    if (repo.isEmpty) {
      await _json('POST', '$_api/user/repos', token: token, body: {
        'name': _repoName,
        'private': true,
        'auto_init': true,
        'description': 'Ur.Terminal encrypted vault (end-to-end encrypted)',
      });
    } else if (repo['private'] != true) {
      throw SyncException('$login/$_repoName exists and is public. '
          'Make it private or delete it first.');
    }
    return p;
  }

  // ---------------------------------------------------------------- data

  @override
  Future<Map<String, dynamic>?> download() async {
    final j = await _json('GET', '$_api/repos/$owner/$repo/contents/$_path',
        token: token, allow404: true);
    if (j.isEmpty) {
      _sha = null;
      return null;
    }
    _sha = j['sha'] as String?;
    var content = (j['content'] as String? ?? '').replaceAll('\n', '');
    if (content.isEmpty && j['download_url'] is String) {
      // Files over 1 MB come without inline content.
      content = base64.encode(
          utf8.encode(await _raw(j['download_url'] as String, token)));
    }
    return jsonDecode(utf8.decode(base64.decode(content)))
        as Map<String, dynamic>;
  }

  @override
  Future<void> upload(Map<String, dynamic> vaultJson) async {
    Future<void> put() => _json(
          'PUT',
          '$_api/repos/$owner/$repo/contents/$_path',
          token: token,
          body: {
            'message': 'Ur.Terminal sync ${DateTime.now().toUtc().toIso8601String()}',
            'content': base64.encode(utf8.encode(jsonEncode(vaultJson))),
            'sha': ?_sha,
          },
        ).then((j) {
          _sha = (j['content'] as Map?)?['sha'] as String? ?? _sha;
        });
    try {
      await put();
    } on _HttpError catch (e) {
      if (e.status != 409 && e.status != 422) rethrow;
      // Someone else committed in between: refresh sha and retry once.
      await download();
      await put();
    }
  }

  // ---------------------------------------------------------------- http

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'Ur.Terminal';

  static Future<Map<String, dynamic>> _form(
      String url, Map<String, String> fields) async {
    final req = await _client.postUrl(Uri.parse(url));
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(Uri(queryParameters: fields).query);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _json(
    String method,
    String url, {
    required String token,
    Map<String, dynamic>? body,
    bool allow404 = false,
  }) async {
    final req = await _client.openUrl(method, Uri.parse(url));
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set('X-GitHub-Api-Version', '2022-11-28');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404 && allow404) return const {};
    if (res.statusCode == 401) {
      throw SyncException('GitHub token expired or revoked. Connect again.');
    }
    if (res.statusCode >= 300) {
      throw _HttpError(res.statusCode, text);
    }
    return text.isEmpty ? const {} : jsonDecode(text) as Map<String, dynamic>;
  }

  static Future<String> _raw(String url, String token) async {
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final res = await req.close();
    return res.transform(utf8.decoder).join();
  }
}

class _HttpError extends SyncException {
  _HttpError(this.status, String body)
      : super('GitHub HTTP $status: ${body.length > 200 ? body.substring(0, 200) : body}');
  final int status;
}
