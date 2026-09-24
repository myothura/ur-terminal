import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../ssh/terminal_session.dart';
import 'pages/hosts_page.dart';
import 'pages/snippets_page.dart';
import 'theme.dart';

class _Entry {
  const _Entry(this.title, this.subtitle, this.icon, this.run, {this.kind = ''});
  final String title;
  final String subtitle;
  final IconData icon;
  final String kind;
  final void Function(BuildContext context) run;
}

Future<void> showCommandPalette(BuildContext context) async {
  final app = AppState.I;
  if (app.paletteOpen) return;
  app.paletteOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (_) => const _Palette(),
    );
  } finally {
    app.paletteOpen = false;
  }
}

class _Palette extends StatefulWidget {
  const _Palette();

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;

  late final List<_Entry> _all = _build();

  List<_Entry> _build() {
    final app = AppState.I;
    final nav = Navigator.of(context);
    return [
      for (final h in app.vault.hosts)
        _Entry(h.displayName, '${h.address}:${h.port}', Icons.dns_outlined,
            (_) => app.openHost(h),
            kind: 'Connect'),
      for (final s in app.vault.snippets)
        _Entry(s.label, s.command, Icons.code, (ctx) async {
          final session = app.active;
          if (session == null || session.status != SessionStatus.connected) {
            return;
          }
          final r = await renderSnippet(ctx, s);
          if (r != null) session.sendText('$r\r');
        }, kind: 'Snippet'),
      _Entry('New local terminal', 'Cmd+T', Icons.laptop_mac,
          (_) => app.openLocal(),
          kind: 'Action'),
      _Entry('New host', 'Cmd+N', Icons.add, (ctx) {
        app.showSection(Section.hosts);
        HostsPage.requestNew(nav.context);
      }, kind: 'Action'),
      for (final sec in Section.values)
        _Entry('Go to ${sec.title}', '', sec.icon, (_) => app.showSection(sec),
            kind: 'Navigate'),
      _Entry('Lock vault', 'Cmd+L', Icons.lock_outline, (_) => app.lock(),
          kind: 'Action'),
    ];
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Entry> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    final words = q.split(RegExp(r'\s+'));
    return _all.where((e) {
      final hay = '${e.title} ${e.subtitle} ${e.kind}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  void _run(_Entry e) {
    final nav = Navigator.of(context);
    final rootCtx = nav.context;
    nav.pop();
    e.run(rootCtx);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final list = _filtered;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1).clamp(0, list.length - 1));
      _ensureVisible();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, list.length - 1));
      _ensureVisible();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && list.isNotEmpty) {
      _run(list[_index.clamp(0, list.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ensureVisible() {
    const rowH = 46.0;
    if (!_scroll.hasClients) return;
    final top = _index * rowH;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + rowH > _scroll.offset + view) {
      _scroll.jumpTo(top + rowH - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 620,
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  onChanged: (_) => setState(() => _index = 0),
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Connect to host, run snippet, or jump to...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixIcon: Icon(Icons.search, color: AppColors.textFaint),
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No results',
                            style: TextStyle(color: AppColors.textMuted)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemExtent: 46,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final e = list[i];
                          final sel = i == _index;
                          return InkWell(
                            onTap: () => _run(e),
                            onHover: (h) {
                              if (h) setState(() => _index = i);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.surface3
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                children: [
                                  Icon(e.icon,
                                      size: 16,
                                      color: sel
                                          ? AppColors.accent
                                          : AppColors.textMuted),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(text: e.title),
                                        if (e.subtitle.isNotEmpty)
                                          TextSpan(
                                            text: '   ${e.subtitle}',
                                            style: const TextStyle(
                                              color: AppColors.textFaint,
                                              fontFamily: kMonoFont,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(e.kind,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textFaint)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
