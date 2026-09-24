import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/models.dart';
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
import 'window_chrome.dart';

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
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.minus ||
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
    } else if (key == LogicalKeyboardKey.equal) {
      app.zoomFont(1);
    } else if (key == LogicalKeyboardKey.minus) {
      app.zoomFont(-1);
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
      backgroundColor: Colors.transparent,
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final terminalMode = app.terminalActive;
          final activeIndex =
              app.sessions.indexWhere((s) => s.id == app.activeSessionId);
          return Column(
            children: [
              _TitleBarTabs(app: app),
              Expanded(
                child: Row(
                  children: [
                    // Termius style: the vault sidebar gets out of the way
                    // while a terminal is in front.
                    if (!terminalMode) ...[
                      _Sidebar(app: app),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: IndexedStack(
                        index: activeIndex + 1,
                        sizing: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: AppColors.glassPage,
                            child: KeyedSubtree(
                              key: ValueKey(app.section),
                              child: _page(app.section),
                            ),
                          ),
                          for (final s in app.sessions)
                            TerminalPane(
                              key: ValueKey(s.id),
                              session: s,
                              active: s.id == app.activeSessionId,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
  const _Sidebar({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      color: AppColors.glassSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          for (final s in Section.values)
            _NavItem(
              section: s,
              selected: app.section == s,
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

// ---------------------------------------------------------------- title bar

class _TitleBarTabs extends StatelessWidget {
  const _TitleBarTabs({required this.app});

  final AppState app;

  Future<void> _quickConnect(BuildContext context, Offset at) async {
    final hosts = app.vault.hosts;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final picked = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
          at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        _item('local', Icons.laptop_mac, 'Local terminal'),
        if (hosts.isNotEmpty) const PopupMenuDivider(),
        for (final h in hosts.take(20))
          _item(h, Icons.dns_outlined, h.displayName),
      ],
    );
    if (picked == 'local') app.openLocal();
    if (picked is Host) app.openHost(picked);
  }

  @override
  Widget build(BuildContext context) {
    final terminalMode = app.terminalActive;
    return Container(
      height: WindowChrome.titleBarHeight,
      decoration: const BoxDecoration(
        color: AppColors.glassChrome,
        border: Border(bottom: BorderSide(color: Color(0x33000000))),
      ),
      child: Row(
        children: [
          // Room for the traffic lights; also draggable.
          const WindowDragArea(
            child: SizedBox(
                width: WindowChrome.trafficLightsInset, height: double.infinity),
          ),
          _Tab(
            label: 'Vaults',
            icon: Icons.grid_view_rounded,
            selected: !terminalMode,
            onTap: app.showPages,
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
          ),
          Builder(
            builder: (ctx) => Tooltip(
              message: 'New tab  (Cmd+T local)',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18, color: AppColors.textMuted),
                onPressed: () {
                  final box = ctx.findRenderObject()! as RenderBox;
                  _quickConnect(
                      ctx, box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                },
              ),
            ),
          ),
          const Expanded(
            child: WindowDragArea(child: SizedBox.expand()),
          ),
          Tooltip(
            message: 'Command palette  (Cmd+K)',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.search, size: 17, color: AppColors.textMuted),
              onPressed: () => showCommandPalette(context),
            ),
          ),
          const SizedBox(width: 8),
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

PopupMenuItem<Object> _item(Object value, IconData icon, String label) =>
    PopupMenuItem<Object>(
      value: value,
      height: 34,
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );

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
    final isSession = w.onClose != null;
    final borderColor = w.selected
        ? (isSession ? AppColors.accent.withValues(alpha: 0.55) : AppColors.border)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: w.onTap,
        onTertiaryTapUp: isSession ? (_) => w.onClose!() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          padding: EdgeInsets.only(left: 11, right: isSession ? 4 : 12),
          constraints: const BoxConstraints(maxWidth: 230, minWidth: 64),
          decoration: BoxDecoration(
            color: w.selected
                ? (isSession ? AppColors.accentDim : AppColors.surface2)
                : (_hover ? AppColors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (w.dot != null) ...[
                StatusDot(w.dot!, size: 7),
                const SizedBox(width: 8),
              ],
              if (w.icon != null) ...[
                Icon(w.icon,
                    size: 14,
                    color: w.selected ? AppColors.text : AppColors.textMuted),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  w.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: w.selected ? FontWeight.w600 : FontWeight.w400,
                    color: w.selected ? AppColors.text : AppColors.textMuted,
                  ),
                ),
              ),
              if (isSession)
                SizedBox(
                  width: 24,
                  child: (_hover || w.selected)
                      ? InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: w.onClose,
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close,
                                size: 13, color: AppColors.textMuted),
                          ),
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
