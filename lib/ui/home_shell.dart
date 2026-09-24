import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ssh/terminal_session.dart';
import 'command_palette.dart';
import 'pages/forwards_page.dart';
import 'pages/hosts_page.dart';
import 'pages/keychain_page.dart';
import 'pages/known_hosts_page.dart';
import 'pages/settings_page.dart';
import 'pages/snippets_page.dart';
import 'terminal_pane.dart';
import 'theme.dart';
import 'widgets.dart';

/// App shortcuts. Checked both globally and inside terminals so the
/// terminal never swallows them.
bool isAppShortcut(KeyEvent e) {
  final k = HardwareKeyboard.instance;
  if (k.isMetaPressed && !k.isAltPressed) {
    final key = e.logicalKey;
    return key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.keyT ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.digit0 ||
        _digits.contains(key);
  }
  if (k.isControlPressed && e.logicalKey == LogicalKeyboardKey.tab) {
    return true;
  }
  return false;
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppState get app => AppState.I;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !isAppShortcut(e)) return false;
    // Let modal dialogs / sheets keep their own keyboard handling.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final k = HardwareKeyboard.instance;
    final key = e.logicalKey;
    if (k.isControlPressed && key == LogicalKeyboardKey.tab) {
      app.cycle(k.isShiftPressed ? -1 : 1);
    } else if (key == LogicalKeyboardKey.keyK) {
      showCommandPalette(context);
    } else if (key == LogicalKeyboardKey.keyT) {
      app.openLocal();
    } else if (key == LogicalKeyboardKey.keyW) {
      app.closeActive();
    } else if (key == LogicalKeyboardKey.keyL) {
      app.lock();
    } else if (key == LogicalKeyboardKey.keyN) {
      app.showSection(Section.hosts);
      HostsPage.requestNew(context);
    } else if (key == LogicalKeyboardKey.digit0) {
      app.showPages();
    } else {
      app.selectIndex(_digits.indexOf(key));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => Row(
          children: [
            const _Sidebar(),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const _TabStrip(),
                  const Divider(height: 1),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final activeIndex =
        app.sessions.indexWhere((s) => s.id == app.activeSessionId);
    return IndexedStack(
      index: activeIndex + 1,
      sizing: StackFit.expand,
      children: [
        KeyedSubtree(key: ValueKey(app.section), child: _page(app.section)),
        for (final s in app.sessions)
          TerminalPane(
            key: ValueKey(s.id),
            session: s,
            active: s.id == app.activeSessionId,
          ),
      ],
    );
  }

  Widget _page(Section s) {
    switch (s) {
      case Section.hosts:
        return const HostsPage();
      case Section.keychain:
        return const KeychainPage();
      case Section.forwards:
        return const ForwardsPage();
      case Section.snippets:
        return const SnippetsPage();
      case Section.knownHosts:
        return const KnownHostsPage();
      case Section.settings:
        return const SettingsPage();
    }
  }
}

// ---------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return Container(
      width: 216,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Row(
              children: [
                Text(
                  'Ur',
                  style: TextStyle(
                    fontFamily: kMonoFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.accent,
                  ),
                ),
                Text(
                  '.Terminal',
                  style: TextStyle(
                    fontFamily: kMonoFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          for (final s in Section.values)
            _NavItem(
              section: s,
              selected: app.activeSessionId == null && app.section == s,
              trailing: s == Section.forwards
                  ? ListenableBuilder(
                      listenable: app.forwards,
                      builder: (_, _) => app.forwards.runningCount == 0
                          ? const SizedBox.shrink()
                          : Badge2('${app.forwards.runningCount}',
                              color: AppColors.accent),
                    )
                  : null,
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: app.lock,
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Lock'),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Command palette  (Cmd+K)',
                  child: OutlinedButton(
                    onPressed: () => showCommandPalette(context),
                    child: const Icon(Icons.search, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    this.trailing,
  });

  final Section section;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => AppState.I.showSection(section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 17,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? AppColors.text : AppColors.textMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tabs

class _TabStrip extends StatelessWidget {
  const _TabStrip();

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return Container(
      height: 42,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _Tab(
            label: 'Vault',
            icon: Icons.grid_view_rounded,
            selected: app.activeSessionId == null,
            onTap: app.showPages,
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in app.sessions)
                  ListenableBuilder(
                    listenable: s,
                    builder: (_, _) => _Tab(
                      label: s.title,
                      dot: _statusColor(s.status),
                      icon: s.isSsh ? null : Icons.laptop_mac,
                      selected: s.id == app.activeSessionId,
                      onTap: () => app.selectSession(s.id),
                      onClose: () => app.closeSession(s.id),
                    ),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: 'New local terminal  (Cmd+T)',
            child: IconButton(
              icon: const Icon(Icons.add, size: 18, color: AppColors.textMuted),
              onPressed: app.openLocal,
            ),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(SessionStatus s) {
    switch (s) {
      case SessionStatus.connecting:
        return AppColors.warning;
      case SessionStatus.connected:
        return AppColors.accent;
      case SessionStatus.disconnected:
        return AppColors.textFaint;
      case SessionStatus.failed:
        return AppColors.danger;
    }
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dot,
    this.onClose,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;
  final VoidCallback? onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: w.onTap,
        onTertiaryTapUp: w.onClose == null ? null : (_) => w.onClose!(),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.only(left: 12, right: 6),
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(
            color: w.selected
                ? AppColors.surface2
                : (_hover ? AppColors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: w.selected ? AppColors.border : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.dot != null) ...[
                StatusDot(w.dot!, size: 7),
                const SizedBox(width: 8),
              ],
              if (w.icon != null) ...[
                Icon(w.icon, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  w.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: w.selected ? AppColors.text : AppColors.textMuted,
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: w.onClose != null && (_hover || w.selected)
                    ? InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: w.onClose,
                        child: const Icon(Icons.close,
                            size: 13, color: AppColors.textMuted),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
