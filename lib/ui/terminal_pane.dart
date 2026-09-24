import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

import '../app_state.dart';
import '../data/prefs.dart';
import '../ssh/terminal_session.dart';
import 'home_shell.dart';
import 'pages/snippets_page.dart';
import 'theme.dart';
import 'widgets.dart';

class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session, required this.active});

  final TerminalSession session;
  final bool active;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _focus = FocusNode(debugLabel: 'terminal');

  TerminalSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    if (widget.active) _focusSoon();
  }

  @override
  void didUpdateWidget(TerminalPane old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _focusSoon();
  }

  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pickSnippet() async {
    final picked = await pickAndRenderSnippet(context);
    if (picked != null) {
      AppState.I.runSnippet(picked.$1, picked.$2);
    }
    _focus.requestFocus();
  }

  String? get _selectedText {
    final range = s.controller.selection;
    if (range == null) return null;
    final text = s.terminal.buffer.getText(range);
    return text.isEmpty ? null : text;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) s.terminal.paste(text);
    _focus.requestFocus();
  }

  Future<void> _contextMenu(Offset global) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = _selectedText;
    final connected = s.status == SessionStatus.connected;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
          global & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (selected != null)
          menuItem('Copy', Icons.copy, () {
            Clipboard.setData(ClipboardData(text: selected));
            s.controller.clearSelection();
          }),
        menuItem('Paste', Icons.content_paste, _paste),
        const PopupMenuDivider(),
        if (connected) menuItem('Run snippet...', Icons.code, _pickSnippet),
        if (!connected && s.status != SessionStatus.connecting)
          menuItem('Reconnect', Icons.refresh, s.start),
        menuItem('Bigger text', Icons.text_increase,
            () => AppState.I.zoomFont(1)),
        menuItem('Smaller text', Icons.text_decrease,
            () => AppState.I.zoomFont(-1)),
        const PopupMenuDivider(),
        menuItem('Close tab', Icons.close,
            () => AppState.I.closeSession(s.id),
            danger: true),
      ],
    );
    action?.call();
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // No opaque backdrop: the terminal paints its own background at the
    // user's opacity so the native window blur shows through (glass).
    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              child: ListenableBuilder(
                listenable: Listenable.merge(
                    [Prefs.I.fontSize, Prefs.I.terminalOpacity]),
                builder: (context, _) => TerminalView(
                  s.terminal,
                  controller: s.controller,
                  focusNode: _focus,
                  theme: terminalTheme,
                  backgroundOpacity: Prefs.I.terminalOpacity.value,
                  textStyle: TerminalStyle(
                    fontSize: Prefs.I.fontSize.value,
                    height: 1.35,
                    fontFamily: kMonoFont,
                    fontFamilyFallback: kMonoFallback,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                  cursorType: TerminalCursorType.block,
                  onSecondaryTapDown: (d, _) => _contextMenu(d.globalPosition),
                  onKeyEvent: (node, event) => isAppShortcut(event)
                      ? KeyEventResult.skipRemainingHandlers
                      : KeyEventResult.ignored,
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: s,
            builder: (context, _) => _StatusBar(
              session: s,
              onSnippet: _pickSnippet,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.session, required this.onSnippet});

  final TerminalSession session;
  final VoidCallback onSnippet;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final (color, label) = switch (s.status) {
      SessionStatus.connecting => (AppColors.warning, 'Connecting'),
      SessionStatus.connected => (AppColors.accent, 'Connected'),
      SessionStatus.disconnected => (AppColors.textFaint, 'Disconnected'),
      SessionStatus.failed => (AppColors.danger, 'Failed'),
    };
    String detail = 'Local shell';
    if (s is SshTerminalSession) {
      final h = s.host;
      final user = s.connector.resolve(h).username;
      detail = '${user == null ? '' : '$user@'}${h.address}:${h.port}';
      if (h.jumpHostId != null) detail += '  via jump host';
    }
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.glassChrome,
        border: Border(top: BorderSide(color: Color(0x33000000))),
      ),
      child: Row(
        children: [
          StatusDot(color, size: 7),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              detail,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: kMonoFont,
                color: AppColors.textFaint,
              ),
            ),
          ),
          Text('${s.cols}x${s.rows}',
              style: const TextStyle(
                  fontSize: 11, fontFamily: kMonoFont, color: AppColors.textFaint)),
          const SizedBox(width: 10),
          if (s.status == SessionStatus.connected)
            _BarButton(icon: Icons.code, label: 'Snippets', onTap: onSnippet)
          else if (s.status != SessionStatus.connecting)
            _BarButton(icon: Icons.refresh, label: 'Reconnect', onTap: s.start),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
