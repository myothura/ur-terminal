import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../../ssh/batch_runner.dart';
import '../../ssh/terminal_session.dart';
import '../theme.dart';
import '../widgets.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final list = vault.snippets
            .where((s) =>
                q.isEmpty ||
                s.label.toLowerCase().contains(q) ||
                s.command.toLowerCase().contains(q) ||
                s.tags.any((t) => t.toLowerCase().contains(q)))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Snippets',
              subtitle: 'Use {{name}} placeholders; values are asked on run',
              actions: [
                SearchBox(controller: _search, hint: 'Search snippets'),
                FilledButton.icon(
                  onPressed: () =>
                      showSideSheet(context, const SnippetEditor()),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New snippet'),
                ),
              ],
            ),
            Expanded(
              child: vault.snippets.isEmpty
                  ? const EmptyState(
                      icon: Icons.code,
                      title: 'No snippets yet',
                      message: 'Save commands you run often, like '
                          'systemctl restart xray or tail -f {{log}}. Run '
                          'them in a tab or on many servers at once.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _SnippetRow(list[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow(this.s);

  final Snippet s;

  Future<void> _runHere(BuildContext context) async {
    final app = AppState.I;
    final session = app.active ??
        app.sessions
            .where((x) => x.status == SessionStatus.connected)
            .firstOrNull;
    if (session == null || session.status != SessionStatus.connected) {
      toast(context, 'Open a connected terminal tab first');
      return;
    }
    final rendered = await renderSnippet(context, s);
    if (rendered == null) return;
    app.selectSession(session.id);
    session.sendText('$rendered\r');
  }

  Future<void> _runOnHosts(BuildContext context) async {
    final rendered = await renderSnippet(context, s);
    if (rendered == null || !context.mounted) return;
    final hosts = await showDialog<List<Host>>(
      context: context,
      builder: (_) => const _HostPicker(),
    );
    if (hosts == null || hosts.isEmpty || !context.mounted) return;
    final runner = BatchRunner(AppState.I.connector, hosts, rendered);
    runner.run();
    await showDialog<void>(
      context: context,
      builder: (_) => _BatchDialog(runner: runner, title: s.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ItemTile(
      leading: const IconBox(Icons.code, color: AppColors.info),
      title: s.label,
      subtitle: s.command.replaceAll('\n', '  ;  '),
      mono: true,
      onDoubleTap: () => showSideSheet(context, SnippetEditor(snippet: s)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => _runHere(context),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Run'),
          ),
          TextButton.icon(
            onPressed: () => _runOnHosts(context),
            icon: const Icon(Icons.dynamic_feed_outlined, size: 16),
            label: const Text('Run on hosts'),
          ),
        ],
      ),
      menu: [
        menuItem('Edit', Icons.edit_outlined,
            () => showSideSheet(context, SnippetEditor(snippet: s))),
        menuItem('Copy command', Icons.copy,
            () => copyToClipboard(context, s.command)),
        const PopupMenuDivider(),
        menuItem('Delete', Icons.delete_outline, () async {
          final ok = await confirmDialog(context,
              title: 'Delete snippet "${s.label}"?', message: s.command);
          if (ok) await AppState.I.vault.delete(s.id);
        }, danger: true),
      ],
    );
  }
}

/// Asks for `{{placeholder}}` values. Returns null when cancelled.
Future<String?> renderSnippet(BuildContext context, Snippet s) async {
  final vars = s.variables;
  if (vars.isEmpty) return s.command;
  final values = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _VariablesDialog(snippet: s),
  );
  return values == null ? null : s.render(values);
}

/// Snippet chooser used from the terminal status bar.
Future<(Snippet, String)?> pickAndRenderSnippet(BuildContext context) async {
  final s = await showDialog<Snippet>(
    context: context,
    builder: (_) => const _SnippetPicker(),
  );
  if (s == null || !context.mounted) return null;
  final r = await renderSnippet(context, s);
  return r == null ? null : (s, r);
}

class _VariablesDialog extends StatefulWidget {
  const _VariablesDialog({required this.snippet});

  final Snippet snippet;

  @override
  State<_VariablesDialog> createState() => _VariablesDialogState();
}

class _VariablesDialogState extends State<_VariablesDialog> {
  late final Map<String, TextEditingController> _c = {
    for (final v in widget.snippet.variables) v: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() =>
      Navigator.pop(context, {for (final e in _c.entries) e.key: e.value.text});

  @override
  Widget build(BuildContext context) {
    final keys = _c.keys.toList();
    return AlertDialog(
      title: Text(widget.snippet.label,
          style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              FieldLabel(keys[i]),
              TextField(
                controller: _c[keys[i]],
                autofocus: i == 0,
                style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
                onSubmitted: (_) => i == keys.length - 1
                    ? _ok()
                    : FocusScope.of(context).nextFocus(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: const Text('Run')),
      ],
    );
  }
}

class _SnippetPicker extends StatefulWidget {
  const _SnippetPicker();

  @override
  State<_SnippetPicker> createState() => _SnippetPickerState();
}

class _SnippetPickerState extends State<_SnippetPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.toLowerCase();
    final list = AppState.I.vault.snippets
        .where((s) =>
            s.label.toLowerCase().contains(q) ||
            s.command.toLowerCase().contains(q))
        .toList();
    return Dialog(
      child: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (list.isNotEmpty) Navigator.pop(context, list.first);
                },
                decoration: const InputDecoration(hintText: 'Run snippet...'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('No snippets',
                          style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(list[i].label),
                        subtitle: Text(
                          list[i].command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: AppColors.textMuted),
                        ),
                        onTap: () => Navigator.pop(context, list[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostPicker extends StatefulWidget {
  const _HostPicker();

  @override
  State<_HostPicker> createState() => _HostPickerState();
}

class _HostPickerState extends State<_HostPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final hosts = AppState.I.vault.hosts;
    return AlertDialog(
      title: const Text('Run on hosts'),
      content: SizedBox(
        width: 440,
        height: 380,
        child: ListView(
          children: [
            CheckboxListTile(
              dense: true,
              value: _selected.length == hosts.length && hosts.isNotEmpty,
              title: const Text('Select all'),
              onChanged: (v) => setState(() {
                _selected.clear();
                if (v == true) _selected.addAll(hosts.map((h) => h.id));
              }),
            ),
            const Divider(height: 1),
            for (final h in hosts)
              CheckboxListTile(
                dense: true,
                value: _selected.contains(h.id),
                title: Text(h.displayName),
                subtitle: Text(h.address,
                    style: const TextStyle(
                        fontFamily: kMonoFont, fontSize: 11.5)),
                onChanged: (v) => setState(() =>
                    v == true ? _selected.add(h.id) : _selected.remove(h.id)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context, hosts.where((h) => _selected.contains(h.id)).toList()),
          child: Text('Run on ${_selected.length}'),
        ),
      ],
    );
  }
}

class _BatchDialog extends StatelessWidget {
  const _BatchDialog({required this.runner, required this.title});

  final BatchRunner runner;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 760,
        height: 560,
        child: ListenableBuilder(
          listenable: runner,
          builder: (context, _) {
            final done = runner.results.where((r) => !r.running).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('$title  |  $done/${runner.results.length}',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (!runner.finished)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      for (final r in runner.results)
                        _BatchResultTile(r: r),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BatchResultTile extends StatelessWidget {
  const _BatchResultTile({required this.r});

  final BatchResult r;

  @override
  Widget build(BuildContext context) {
    final color = r.running
        ? AppColors.warning
        : (r.ok ? AppColors.accent : AppColors.danger);
    final status = r.running
        ? 'running'
        : r.error != null
            ? 'error'
            : 'exit ${r.exitCode ?? '?'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                StatusDot(color),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(r.host.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(status,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (!r.running)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SingleChildScrollView(
                child: SelectableText(
                  r.error ?? (r.output.isEmpty ? '(no output)' : r.output),
                  style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11.5,
                    color:
                        r.error != null ? AppColors.danger : AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- editor

class SnippetEditor extends StatefulWidget {
  const SnippetEditor({super.key, this.snippet});

  final Snippet? snippet;

  @override
  State<SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<SnippetEditor> {
  late final Snippet? s = widget.snippet;
  late final _label = TextEditingController(text: s?.label);
  late final _cmd = TextEditingController(text: s?.command);
  late final _tags = TextEditingController(text: s?.tags.join(', '));
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _cmd.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_cmd.text.trim().isEmpty) {
      setState(() => _error = 'Command is required.');
      return;
    }
    await AppState.I.vault.put(Snippet(
      id: s?.id ?? newId(),
      label: _label.text.trim().isEmpty
          ? _cmd.text.trim().split('\n').first
          : _label.text.trim(),
      command: _cmd.text.trimRight(),
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: s == null ? 'New snippet' : 'Edit snippet',
      onSave: _save,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _label,
          autofocus: s == null,
          decoration: const InputDecoration(hintText: 'Restart Xray'),
        ),
        const FieldLabel('Command', hint: '{{placeholders}} are asked on run'),
        TextField(
          controller: _cmd,
          minLines: 4,
          maxLines: 12,
          style: const TextStyle(fontFamily: kMonoFont, fontSize: 12.5),
          decoration: const InputDecoration(
            hintText: 'systemctl restart xray && journalctl -u xray -n {{lines}}',
          ),
        ),
        const FieldLabel('Tags'),
        TextField(controller: _tags),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
