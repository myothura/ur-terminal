import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class ForwardEditor extends StatefulWidget {
  const ForwardEditor({super.key, this.rule});

  final ForwardRule? rule;

  @override
  State<ForwardEditor> createState() => _ForwardEditorState();
}

class _ForwardEditorState extends State<ForwardEditor> {
  late final ForwardRule? r = widget.rule;
  late ForwardType _type = r?.type ?? ForwardType.local;
  late String? _hostId = r?.hostId;
  late final _label = TextEditingController(text: r?.label);
  late final _bindHost =
      TextEditingController(text: r?.bindHost ?? '127.0.0.1');
  late final _bindPort =
      TextEditingController(text: r == null ? '' : '${r!.bindPort}');
  late final _destHost =
      TextEditingController(text: r?.destHost ?? '127.0.0.1');
  late final _destPort = TextEditingController(
      text: r == null || r!.destPort == 0 ? '' : '${r!.destPort}');
  late bool _auto = r?.autoStart ?? false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_label, _bindHost, _bindPort, _destHost, _destPort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final bindPort = int.tryParse(_bindPort.text.trim());
    final destPort = int.tryParse(_destPort.text.trim()) ?? 0;
    if (_hostId == null) {
      setState(() => _error = 'Choose the SSH host to tunnel through.');
      return;
    }
    if (bindPort == null || bindPort < 1 || bindPort > 65535) {
      setState(() => _error = 'Enter a valid bind port.');
      return;
    }
    if (_type != ForwardType.dynamic && (destPort < 1 || destPort > 65535)) {
      setState(() => _error = 'Enter a valid destination port.');
      return;
    }
    final rule = ForwardRule(
      id: r?.id ?? newId(),
      label: _label.text.trim(),
      type: _type,
      hostId: _hostId!,
      bindHost: _bindHost.text.trim().isEmpty
          ? (_type == ForwardType.remote ? 'localhost' : '127.0.0.1')
          : _bindHost.text.trim(),
      bindPort: bindPort,
      destHost: _destHost.text.trim().isEmpty
          ? '127.0.0.1'
          : _destHost.text.trim(),
      destPort: destPort,
      autoStart: _auto,
    );
    await AppState.I.vault.put(rule);
    // Apply edits to a running tunnel immediately.
    if (AppState.I.forwards.isActive(rule.id)) {
      await AppState.I.forwards.start(rule);
    }
    if (mounted) Navigator.of(context).pop();
  }

  String get _help {
    switch (_type) {
      case ForwardType.local:
        return 'ssh -L  |  Connections to this Mac on bind port are carried '
            'to destination as seen from the server. Example: 127.0.0.1:3307 '
            '-> 127.0.0.1:3306 to reach a server-only MySQL.';
      case ForwardType.remote:
        return 'ssh -R  |  The server listens on bind port and sends '
            'connections back to destination as seen from this Mac. Example: '
            'expose localhost:8000 dev server on the VPS.';
      case ForwardType.dynamic:
        return 'ssh -D  |  A SOCKS5 proxy on this Mac that exits through the '
            'server. Point a browser or curl --proxy socks5h://127.0.0.1:1080.';
    }
  }

  Widget _portRow(String title, TextEditingController host,
      TextEditingController port, String hostHint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldLabel(title),
              TextField(
                controller: host,
                style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
                decoration: InputDecoration(hintText: hostHint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Port'),
              TextField(
                controller: port,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hosts = AppState.I.vault.hosts;
    return SheetScaffold(
      title: r == null ? 'New forwarding rule' : 'Edit forwarding rule',
      onSave: _save,
      children: [
        const FieldLabel('Type'),
        SegmentedButton<ForwardType>(
          segments: [
            for (final t in ForwardType.values)
              ButtonSegment(value: t, label: Text('${t.code}  ${t.title}')),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 10),
        Text(_help,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const FieldLabel('Label'),
        TextField(
          controller: _label,
          decoration: const InputDecoration(hintText: 'Prod MySQL'),
        ),
        const FieldLabel('SSH host'),
        IdDropdown<Host>(
          value: _hostId,
          items: hosts,
          idOf: (h) => h.id,
          labelOf: (h) => h.displayName,
          noneLabel: 'Choose host',
          onChanged: (v) => setState(() => _hostId = v),
        ),
        _portRow(
          _type == ForwardType.remote ? 'Bind on server' : 'Bind on this Mac',
          _bindHost,
          _bindPort,
          '127.0.0.1',
        ),
        if (_type != ForwardType.dynamic)
          _portRow(
            _type == ForwardType.local
                ? 'Destination (from server)'
                : 'Destination (from this Mac)',
            _destHost,
            _destPort,
            '127.0.0.1',
          ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _auto,
          onChanged: (v) => setState(() => _auto = v),
          title: const Text('Start automatically'),
          subtitle: const Text('When the vault is unlocked',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
