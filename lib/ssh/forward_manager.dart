import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/vault.dart';
import 'connector.dart';

enum ForwardState { stopped, starting, running, reconnecting, failed }

class ActiveForward {
  ActiveForward(this.rule);

  final ForwardRule rule;
  ForwardState state = ForwardState.starting;
  String? error;
  int openConnections = 0;
  int totalConnections = 0;
  int bytesIn = 0;
  int bytesOut = 0;

  SshConnection? _conn;
  ServerSocket? _server;
  SSHRemoteForward? _remote;
  SSHDynamicForward? _dynamic;
  final Set<Socket> _sockets = {};
  Timer? _retry;
  int _attempt = 0;
  bool _stopping = false;

  Future<void> _closeResources() async {
    await _server?.close();
    _server = null;
    _remote?.close();
    _remote = null;
    await _dynamic?.close();
    _dynamic = null;
    for (final s in _sockets.toList()) {
      s.destroy();
    }
    _sockets.clear();
    _conn?.close();
    _conn = null;
    openConnections = 0;
  }
}

/// Runs port forwarding rules. Each rule owns a dedicated SSH connection so a
/// terminal tab closing never kills a tunnel (and vice versa). Rules reconnect
/// with exponential backoff when the connection drops.
class ForwardManager extends ChangeNotifier {
  ForwardManager(this.vault, this.connector);

  final Vault vault;
  final SshConnector connector;
  final Map<String, ActiveForward> _active = {};

  Timer? _tick;

  ActiveForward? stateOf(String ruleId) => _active[ruleId];

  int get runningCount =>
      _active.values.where((a) => a.state == ForwardState.running).length;

  bool isActive(String ruleId) {
    final a = _active[ruleId];
    return a != null && a.state != ForwardState.stopped;
  }

  Future<void> startAutoRules() async {
    for (final r in vault.forwards.where((r) => r.autoStart)) {
      if (!isActive(r.id)) unawaited(start(r));
    }
  }

  Future<void> toggle(ForwardRule rule) =>
      isActive(rule.id) ? stop(rule.id) : start(rule);

  Future<void> start(ForwardRule rule) async {
    await stop(rule.id);
    final a = ActiveForward(rule);
    _active[rule.id] = a;
    _ensureTicker();
    notifyListeners();
    await _run(a);
  }

  Future<void> _run(ActiveForward a) async {
    final rule = a.rule;
    final host = vault.byId<Host>(rule.hostId);
    if (host == null) {
      a
        ..state = ForwardState.failed
        ..error = 'Host not found';
      notifyListeners();
      return;
    }
    try {
      final conn = await connector.connect(host);
      if (a._stopping) {
        conn.close();
        return;
      }
      a._conn = conn;
      switch (rule.type) {
        case ForwardType.local:
          await _startLocal(a, conn);
        case ForwardType.remote:
          await _startRemote(a, conn);
        case ForwardType.dynamic:
          a._dynamic = await conn.client.forwardDynamic(
            bindHost: rule.bindHost,
            bindPort: rule.bindPort,
          );
      }
      a
        ..state = ForwardState.running
        ..error = null
        .._attempt = 0;
      notifyListeners();

      unawaited(conn.done.whenComplete(() => _onDropped(a)).catchError((_) {}));
    } catch (e) {
      await a._closeResources();
      if (a._stopping) return;
      a
        ..state = ForwardState.failed
        ..error = '$e';
      notifyListeners();
      if (e is! SshConnectException || e.message != 'Cancelled') {
        _scheduleRetry(a);
      }
    }
  }

  Future<void> _startLocal(ActiveForward a, SshConnection conn) async {
    final rule = a.rule;
    final server = await ServerSocket.bind(rule.bindHost, rule.bindPort);
    a._server = server;
    server.listen((socket) async {
      a._sockets.add(socket);
      a.openConnections++;
      a.totalConnections++;
      try {
        final channel =
            await conn.client.forwardLocal(rule.destHost, rule.destPort);
        _pipe(a, socket, channel);
      } catch (e) {
        socket.destroy();
        _connectionClosed(a, socket);
      }
    });
  }

  Future<void> _startRemote(ActiveForward a, SshConnection conn) async {
    final rule = a.rule;
    final remote = await conn.client.forwardRemote(
      host: rule.bindHost,
      port: rule.bindPort,
    );
    if (remote == null) {
      throw Exception(
          'Server refused remote forward on ${rule.bindHost}:${rule.bindPort}'
          ' (check GatewayPorts / AllowTcpForwarding)');
    }
    a._remote = remote;
    remote.connections.listen((channel) async {
      a.openConnections++;
      a.totalConnections++;
      try {
        final socket = await Socket.connect(rule.destHost, rule.destPort,
            timeout: const Duration(seconds: 10));
        a._sockets.add(socket);
        _pipe(a, socket, channel);
      } catch (_) {
        channel.destroy();
        a.openConnections--;
        notifyListeners();
      }
    });
  }

  void _pipe(ActiveForward a, Socket socket, SSHForwardChannel channel) {
    var closed = false;
    void done() {
      if (closed) return;
      closed = true;
      socket.destroy();
      channel.destroy();
      _connectionClosed(a, socket);
    }

    channel.stream.listen(
      (data) {
        a.bytesIn += data.length;
        socket.add(data);
      },
      onDone: done,
      onError: (_) => done(),
      cancelOnError: true,
    );
    socket.listen(
      (data) {
        a.bytesOut += data.length;
        channel.sink.add(data);
      },
      onDone: done,
      onError: (_) => done(),
      cancelOnError: true,
    );
    notifyListeners();
  }

  void _connectionClosed(ActiveForward a, Socket socket) {
    if (a._sockets.remove(socket)) {
      a.openConnections = (a.openConnections - 1).clamp(0, 1 << 30);
    }
    notifyListeners();
  }

  Future<void> _onDropped(ActiveForward a) async {
    if (a._stopping || _active[a.rule.id] != a) return;
    await a._closeResources();
    a
      ..state = ForwardState.reconnecting
      ..error = 'Connection lost';
    notifyListeners();
    _scheduleRetry(a);
  }

  void _scheduleRetry(ActiveForward a) {
    if (a._stopping) return;
    a._attempt++;
    final seconds = (1 << a._attempt.clamp(0, 6)).clamp(2, 60);
    a._retry?.cancel();
    a._retry = Timer(Duration(seconds: seconds), () {
      if (a._stopping || _active[a.rule.id] != a) return;
      a.state = ForwardState.reconnecting;
      notifyListeners();
      _run(a);
    });
  }

  Future<void> stop(String ruleId) async {
    final a = _active.remove(ruleId);
    if (a == null) return;
    a._stopping = true;
    a._retry?.cancel();
    await a._closeResources();
    a.state = ForwardState.stopped;
    notifyListeners();
  }

  Future<void> stopAll() async {
    for (final id in _active.keys.toList()) {
      await stop(id);
    }
  }

  /// Traffic counters change constantly; repaint the list at most once a
  /// second instead of on every packet.
  void _ensureTicker() {
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active.isEmpty) {
        _tick?.cancel();
        _tick = null;
      } else {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    stopAll();
    super.dispose();
  }
}
