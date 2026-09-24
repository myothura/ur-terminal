import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty2/flutter_pty2.dart';
import 'package:xterm2/xterm.dart';

import '../core/ids.dart';
import '../data/models.dart';
import 'connector.dart';

enum SessionStatus { connecting, connected, disconnected, failed }

/// A terminal tab: owns the emulator state and a backend (SSH or local PTY).
abstract class TerminalSession extends ChangeNotifier {
  TerminalSession({required String title}) : _title = title {
    terminal = Terminal(
      maxLines: 10000,
      platform: TerminalTargetPlatform.macos,
      onTitleChange: (t) {
        if (t.trim().isNotEmpty) {
          _remoteTitle = t.trim();
          notifyListeners();
        }
      },
    );
    terminal.onOutput = _onUserInput;
    terminal.onResize = (w, h, pw, ph) {
      _cols = w;
      _rows = h;
      onResize(w, h, pw, ph);
    };
  }

  final String id = newId();
  late final Terminal terminal;
  final TerminalController controller = TerminalController();

  final String _title;
  String? _remoteTitle;
  String get title => _remoteTitle ?? _title;
  String get baseTitle => _title;

  int _cols = 80;
  int _rows = 24;
  int get cols => _cols;
  int get rows => _rows;

  SessionStatus _status = SessionStatus.connecting;
  SessionStatus get status => _status;
  String? error;

  bool get isSsh;

  @protected
  set status(SessionStatus s) {
    _status = s;
    notifyListeners();
  }

  void _onUserInput(String data) {
    if (_status == SessionStatus.disconnected ||
        _status == SessionStatus.failed) {
      if (data == '\r') start();
      return;
    }
    sendBytes(Uint8List.fromList(utf8.encode(data)));
  }

  /// Sends raw [text] to the remote side (snippets, startup commands).
  void sendText(String text) {
    if (_status != SessionStatus.connected) return;
    sendBytes(Uint8List.fromList(utf8.encode(text)));
  }

  void info(String line) => terminal.write('\x1b[2m$line\x1b[0m\r\n');

  void errorLine(String line) => terminal.write('\x1b[31m$line\x1b[0m\r\n');

  Future<void> start();

  @protected
  void sendBytes(Uint8List bytes);

  @protected
  void onResize(int w, int h, int pw, int ph);

  Future<void> close();

  @protected
  void markEnded({String? reason, bool failed = false}) {
    if (_status == SessionStatus.disconnected ||
        _status == SessionStatus.failed) {
      return;
    }
    error = reason;
    terminal.write('\r\n');
    if (reason != null) errorLine(reason);
    info('Session ended. Press Enter to reconnect.');
    status = failed ? SessionStatus.failed : SessionStatus.disconnected;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------

class SshTerminalSession extends TerminalSession {
  SshTerminalSession({required this.host, required this.connector})
      : super(title: host.displayName);

  final Host host;
  final SshConnector connector;

  SshConnection? _conn;
  SSHSession? _shell;
  final List<StreamSubscription<String>> _subs = [];
  bool _closing = false;

  SshConnection? get connection => _conn;

  @override
  bool get isSsh => true;

  @override
  Future<void> start() async {
    await _teardown();
    _closing = false;
    error = null;
    status = SessionStatus.connecting;
    try {
      final conn = await connector.connect(host, log: info);
      if (_closing) {
        conn.close();
        return;
      }
      _conn = conn;
      final shell = await conn.client.shell(
        pty: SSHPtyConfig(width: cols, height: rows),
      );
      _shell = shell;
      const decoder = Utf8Decoder(allowMalformed: true);
      _subs
        ..add(shell.stdout
            .cast<List<int>>()
            .transform(decoder)
            .listen(terminal.write))
        ..add(shell.stderr
            .cast<List<int>>()
            .transform(decoder)
            .listen(terminal.write));
      status = SessionStatus.connected;

      final startup = host.startupCommand;
      if (startup != null && startup.trim().isNotEmpty) {
        shell.write(Uint8List.fromList(utf8.encode('$startup\n')));
      }

      unawaited(shell.done.then((_) {
        if (!_closing) markEnded();
      }, onError: (Object e) {
        if (!_closing) markEnded(reason: '$e', failed: true);
      }));
      unawaited(conn.done.then((_) {
        if (!_closing) markEnded(reason: 'Connection closed');
      }, onError: (Object e) {
        if (!_closing) markEnded(reason: 'Connection lost: $e', failed: true);
      }));
    } catch (e) {
      if (_closing) return;
      errorLine('$e');
      info('Press Enter to retry.');
      error = '$e';
      status = SessionStatus.failed;
    }
  }

  @override
  void sendBytes(Uint8List bytes) => _shell?.write(bytes);

  @override
  void onResize(int w, int h, int pw, int ph) =>
      _shell?.resizeTerminal(w, h, pw, ph);

  Future<void> _teardown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _shell?.close();
    _shell = null;
    _conn?.close();
    _conn = null;
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _teardown();
  }
}

// ---------------------------------------------------------------------------

class LocalTerminalSession extends TerminalSession {
  LocalTerminalSession() : super(title: 'Local');

  PtySession? _pty;
  StreamSubscription<String>? _sub;
  bool _closing = false;

  @override
  bool get isSsh => false;

  @override
  Future<void> start() async {
    await _teardown();
    _closing = false;
    status = SessionStatus.connecting;
    try {
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      final pty = await Pty.spawn(PtySpawnOptions(
        executable: shell,
        arguments: const ['-l'],
        workingDirectory: Platform.environment['HOME'],
        environment: PtyEnvironment.inherit(overrides: {
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'TERM_PROGRAM': 'UrTerminal',
          if (!(Platform.environment['LANG'] ?? '').contains('UTF-8'))
            'LANG': 'en_US.UTF-8',
        }),
        size: PtySize(columns: cols, rows: rows),
      ));
      _pty = pty;
      _sub = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
      status = SessionStatus.connected;
      unawaited(pty.processExit.then((_) {
        if (!_closing) markEnded();
      }));
    } catch (e) {
      errorLine('Cannot start local shell: $e');
      error = '$e';
      status = SessionStatus.failed;
    }
  }

  @override
  void sendBytes(Uint8List bytes) {
    final pty = _pty;
    if (pty == null) return;
    unawaited(pty.input.write(bytes).catchError((Object _) {}));
  }

  @override
  void onResize(int w, int h, int pw, int ph) {
    _pty?.resize(PtySize(
      columns: w,
      rows: h,
      pixelWidth: pw.clamp(0, 0xffff),
      pixelHeight: ph.clamp(0, 0xffff),
    ));
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final pty = _pty;
    _pty = null;
    if (pty != null) {
      pty.kill();
      await pty.close();
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _teardown();
  }
}
