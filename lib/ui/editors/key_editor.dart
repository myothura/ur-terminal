import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../core/keygen.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class KeyEditor extends StatefulWidget {
  const KeyEditor({super.key, this.sshKey});

  final SshKey? sshKey;

  @override
  State<KeyEditor> createState() => _KeyEditorState();
}

class _KeyEditorState extends State<KeyEditor> {
  late final SshKey? k = widget.sshKey;
  late final _label = TextEditingController(text: k?.label);
  late final _pem = TextEditingController(text: k?.privatePem);
  late final _pass = TextEditingController(text: k?.passphrase);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _pem.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pem = _pem.text.trim();
    final pass = _pass.text.isEmpty ? null : _pass.text;
    final label = _label.text.trim().isEmpty ? 'Key' : _label.text.trim();
    if (!pem.contains('PRIVATE KEY')) {
      setState(() => _error = 'Paste a PEM / OpenSSH private key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await KeyTools.inspectInBackground(pem,
          passphrase: pass, comment: label);
      await AppState.I.vault.put(SshKey(
        id: k?.id ?? newId(),
        label: label,
        privatePem: '$pem\n',
        passphrase: pass,
        publicLine: info.publicLine,
        type: info.type,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not read key (wrong passphrase?): $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: k == null ? 'Add private key' : 'Edit key',
      busy: _busy,
      onSave: _save,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _label,
          autofocus: k == null,
          decoration: const InputDecoration(hintText: 'id_ed25519 work'),
        ),
        const FieldLabel('Private key',
            hint: 'OpenSSH, PEM RSA or EC formats'),
        TextField(
          controller: _pem,
          minLines: 8,
          maxLines: 14,
          style: const TextStyle(fontFamily: kMonoFont, fontSize: 11.5),
          decoration: const InputDecoration(
            hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
          ),
        ),
        const FieldLabel('Passphrase', hint: 'Only if the key is encrypted'),
        TextField(controller: _pass, obscureText: true),
        if (k?.publicLine != null) ...[
          const FieldLabel('Public key'),
          SelectableText(
            k!.publicLine!,
            style: const TextStyle(
              fontFamily: kMonoFont,
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
