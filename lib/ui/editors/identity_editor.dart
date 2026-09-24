import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class IdentityEditor extends StatefulWidget {
  const IdentityEditor({super.key, this.identity});

  final Identity? identity;

  @override
  State<IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends State<IdentityEditor> {
  late final Identity? i = widget.identity;
  late final _label = TextEditingController(text: i?.label);
  late final _user = TextEditingController(text: i?.username);
  late final _pass = TextEditingController(text: i?.password);
  late String? _keyId = i?.keyId;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = _user.text.trim();
    if (user.isEmpty) {
      setState(() => _error = 'Username is required.');
      return;
    }
    await AppState.I.vault.put(Identity(
      id: i?.id ?? newId(),
      label: _label.text.trim().isEmpty ? user : _label.text.trim(),
      username: user,
      password: _pass.text.isEmpty ? null : _pass.text,
      keyId: _keyId,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: i == null ? 'New identity' : 'Edit identity',
      onSave: _save,
      children: [
        const FieldLabel('Name'),
        TextField(
          controller: _label,
          autofocus: i == null,
          decoration: const InputDecoration(hintText: 'Root on VPN servers'),
        ),
        const FieldLabel('Username'),
        TextField(controller: _user),
        const FieldLabel('Password', hint: 'Optional'),
        TextField(controller: _pass, obscureText: true),
        const FieldLabel('SSH key'),
        IdDropdown<SshKey>(
          value: _keyId,
          items: AppState.I.vault.keys,
          idOf: (k) => k.id,
          labelOf: (k) => k.label,
          onChanged: (v) => setState(() => _keyId = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
