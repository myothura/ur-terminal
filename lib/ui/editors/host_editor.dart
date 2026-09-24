import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../core/totp.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets.dart';

class HostEditor extends StatefulWidget {
  const HostEditor({super.key, this.host});

  final Host? host;

  @override
  State<HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends State<HostEditor> {
  late final Host? h = widget.host;
  late final _label = TextEditingController(text: h?.label);
  late final _address = TextEditingController(text: h?.address);
  late final _port = TextEditingController(text: '${h?.port ?? 22}');
  late final _user = TextEditingController(text: h?.username);
  late final _password = TextEditingController(text: h?.password);
  late final _tags = TextEditingController(text: h?.tags.join(', '));
  late final _startup = TextEditingController(text: h?.startupCommand);
  late final _totp = TextEditingController(text: h?.totpSecret);
  late final _keepAlive =
      TextEditingController(text: '${h?.keepAliveSeconds ?? 15}');
  late final _notes = TextEditingController(text: h?.notes);

  late String? _groupId = h?.groupId;
  late String? _identityId = h?.identityId;
  late String? _keyId = h?.keyId;
  late String? _jumpId = h?.jumpHostId;

  bool _showPassword = false;
  String? _error;
  String? _totpCode;
  Timer? _totpTimer;

  @override
  void initState() {
    super.initState();
    _totp.addListener(_refreshTotp);
    _refreshTotp();
    _totpTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refreshTotp());
  }

  Future<void> _refreshTotp() async {
    final s = _totp.text.trim();
    final code =
        s.isNotEmpty && Totp.isValidSecret(s) ? await Totp.generate(s) : null;
    if (mounted && code != _totpCode) setState(() => _totpCode = code);
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    for (final c in [
      _label,
      _address,
      _port,
      _user,
      _password,
      _tags,
      _startup,
      _totp,
      _keepAlive,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    final address = _address.text.trim();
    final port = int.tryParse(_port.text.trim());
    final totp = _t(_totp);
    if (address.isEmpty) {
      setState(() => _error = 'Address is required.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Port must be 1-65535.');
      return;
    }
    if (totp != null && !Totp.isValidSecret(totp)) {
      setState(() => _error = '2FA secret must be base32 (A-Z, 2-7).');
      return;
    }
    final host = Host(
      id: h?.id ?? newId(),
      label: _label.text.trim(),
      address: address,
      port: port,
      username: _t(_user),
      password: _password.text.isEmpty ? null : _password.text,
      keyId: _keyId,
      identityId: _identityId,
      groupId: _groupId,
      jumpHostId: _jumpId,
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      totpSecret: totp?.replaceAll(' ', '').toUpperCase(),
      startupCommand: _t(_startup),
      keepAliveSeconds: int.tryParse(_keepAlive.text.trim()) ?? 15,
      notes: _t(_notes),
    );
    await AppState.I.vault.put(host);
    if (mounted) Navigator.of(context).pop(host);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${h!.displayName}"?',
      message: 'This cannot be undone.',
    );
    if (!ok) return;
    await AppState.I.vault.delete(h!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    final otherHosts = vault.hosts.where((x) => x.id != h?.id).toList();
    return SheetScaffold(
      title: h == null ? 'New host' : 'Edit host',
      onSave: _save,
      onDelete: h == null ? null : _delete,
      children: [
        const FieldLabel('Label'),
        TextField(
          controller: _label,
          autofocus: h == null,
          decoration: const InputDecoration(hintText: 'Production API'),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Address'),
                  TextField(
                    controller: _address,
                    style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
                    decoration:
                        const InputDecoration(hintText: 'IP or hostname'),
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
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              ),
            ),
          ],
        ),
        const FieldLabel('Group'),
        IdDropdown<HostGroup>(
          value: _groupId,
          items: vault.groups,
          idOf: (g) => g.id,
          labelOf: (g) => g.name,
          onChanged: (v) => setState(() => _groupId = v),
        ),
        const SectionTitle('Credentials'),
        const FieldLabel('Identity',
            hint: 'Shared username + key/password from Keychain'),
        IdDropdown<Identity>(
          value: _identityId,
          items: vault.identities,
          idOf: (i) => i.id,
          labelOf: (i) => '${i.label}  (${i.username})',
          onChanged: (v) => setState(() => _identityId = v),
        ),
        const FieldLabel('Username', hint: 'Overrides identity'),
        TextField(
          controller: _user,
          decoration: const InputDecoration(hintText: 'root'),
        ),
        const FieldLabel('Password', hint: 'Optional'),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textFaint,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const FieldLabel('SSH key', hint: 'Overrides identity'),
        IdDropdown<SshKey>(
          value: _keyId,
          items: vault.keys,
          idOf: (k) => k.id,
          labelOf: (k) => k.label,
          onChanged: (v) => setState(() => _keyId = v),
        ),
        const FieldLabel('Two-factor (TOTP secret)',
            hint: 'Auto-fills Verification code prompts'),
        TextField(
          controller: _totp,
          style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Base32 secret from google-authenticator',
            suffixIcon: _totpCode == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _totpCode!,
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SectionTitle('Advanced'),
        const FieldLabel('Jump host', hint: 'ProxyJump through another host'),
        IdDropdown<Host>(
          value: _jumpId,
          items: otherHosts,
          idOf: (x) => x.id,
          labelOf: (x) => x.displayName,
          onChanged: (v) => setState(() => _jumpId = v),
        ),
        const FieldLabel('Startup command', hint: 'Runs after login'),
        TextField(
          controller: _startup,
          style: const TextStyle(fontFamily: kMonoFont, fontSize: 13),
          decoration: const InputDecoration(hintText: 'cd /var/www && ls'),
        ),
        const FieldLabel('Tags', hint: 'Comma separated'),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(hintText: 'vpn, sg, prod'),
        ),
        const FieldLabel('Keep-alive (seconds)'),
        TextField(
          controller: _keepAlive,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const FieldLabel('Notes'),
        TextField(controller: _notes, maxLines: 3, minLines: 2),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
      ],
    );
  }
}
