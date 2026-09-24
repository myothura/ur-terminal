import 'dart:async';

import 'package:flutter/material.dart';

import 'data/models.dart';
import 'data/prefs.dart';
import 'data/vault.dart';
import 'ssh/connector.dart';
import 'ssh/forward_manager.dart';
import 'ssh/terminal_session.dart';
import 'sync/sync_manager.dart';
import 'ui/prompts.dart';

enum Section {
  hosts('Hosts', Icons.dns_outlined),
  keychain('Keychain', Icons.key_outlined),
  forwards('Port Forwarding', Icons.swap_horiz),
  snippets('Snippets', Icons.code),
  knownHosts('Known Hosts', Icons.verified_user_outlined),
  settings('Settings', Icons.tune);

  const Section(this.title, this.icon);
  final String title;
  final IconData icon;
}

final navigatorKey = GlobalKey<NavigatorState>();

/// App-wide state: open terminal tabs, current section, and the services.
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState I = AppState._();

  final Vault vault = Vault.instance;
  late final SshConnector connector =
      SshConnector(vault, DialogPrompter(navigatorKey));
  late final ForwardManager forwards = ForwardManager(vault, connector);

  final List<TerminalSession> sessions = [];
  Section section = Section.hosts;

  /// null means the vault pages are shown instead of a terminal.
  String? activeSessionId;

  bool paletteOpen = false;

  /// Terminal font size, adjustable with Cmd+= / Cmd+-.
  ValueNotifier<double> get fontSize => Prefs.I.fontSize;

  void zoomFont(double delta) {
    fontSize.value = (fontSize.value + delta).clamp(9.0, 28.0);
  }

  bool get terminalActive => active != null;

  TerminalSession? get active {
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return null;
  }

  void showSection(Section s) {
    section = s;
    activeSessionId = null;
    notifyListeners();
  }

  void showPages() {
    activeSessionId = null;
    notifyListeners();
  }

  void selectSession(String id) {
    activeSessionId = id;
    notifyListeners();
  }

  void selectIndex(int i) {
    if (i < 0 || i >= sessions.length) return;
    selectSession(sessions[i].id);
  }

  void cycle(int delta) {
    if (sessions.isEmpty) return;
    final current = sessions.indexWhere((s) => s.id == activeSessionId);
    final next = current < 0
        ? (delta > 0 ? 0 : sessions.length - 1)
        : (current + delta) % sessions.length;
    selectIndex(next < 0 ? next + sessions.length : next);
  }

  TerminalSession openHost(Host host) {
    final s = SshTerminalSession(host: host, connector: connector);
    _add(s);
    unawaited(s.start());
    return s;
  }

  TerminalSession openLocal() {
    final s = LocalTerminalSession();
    _add(s);
    unawaited(s.start());
    return s;
  }

  void _add(TerminalSession s) {
    sessions.add(s);
    activeSessionId = s.id;
    notifyListeners();
  }

  Future<void> closeSession(String id) async {
    final i = sessions.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final s = sessions.removeAt(i);
    if (activeSessionId == id) {
      activeSessionId = sessions.isEmpty
          ? null
          : sessions[(i - 1).clamp(0, sessions.length - 1)].id;
    }
    notifyListeners();
    await s.close();
    s.dispose();
  }

  Future<void> closeActive() async {
    final id = activeSessionId;
    if (id != null) await closeSession(id);
  }

  void runSnippet(Snippet snippet, String rendered) {
    final s = active;
    if (s == null || s.status != SessionStatus.connected) return;
    s.sendText('$rendered\r');
  }

  Future<void> onUnlocked() async {
    await forwards.startAutoRules();
    unawaited(SyncManager.I.start());
  }

  Future<void> lock() async {
    for (final s in sessions.toList()) {
      await closeSession(s.id);
    }
    await forwards.stopAll();
    await SyncManager.I.stop();
    section = Section.hosts;
    await vault.lock();
    notifyListeners();
  }
}
