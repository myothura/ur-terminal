import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../core/keygen.dart';
import '../../data/models.dart';
import '../editors/identity_editor.dart';
import '../editors/key_editor.dart';
import '../theme.dart';
import '../widgets.dart';

class KeychainPage extends StatelessWidget {
  const KeychainPage({super.key});

  Future<void> _generate(BuildContext context) async {
    final name = await AppState.I.connector.prompter.askText(
      'Generate Ed25519 key',
      'Key name',
      secret: false,
    );
    if (name == null || name.trim().isEmpty) return;
    final comment = '${name.trim().replaceAll(' ', '-')}@ur-terminal';
    final g = await KeyTools.generateEd25519(comment);
    await AppState.I.vault.put(SshKey(
      id: newId(),
      label: name.trim(),
      privatePem: g.privatePem,
      publicLine: g.publicLine,
      type: g.type,
    ));
    if (context.mounted) {
      await copyToClipboard(context, g.publicLine,
          what: 'Key generated. Public key copied to clipboard.');
    }
  }

  Future<void> _importFromSshDir(BuildContext context) async {
    final dir = Directory('${Platform.environment['HOME']}/.ssh');
    if (!await dir.exists()) {
      if (context.mounted) toast(context, '~/.ssh not found');
      return;
    }
    final vault = AppState.I.vault;
    final existing = vault.keys.map((k) => k.privatePem.trim()).toSet();
    var count = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      if (name.endsWith('.pub') ||
          name.startsWith('known_hosts') ||
          name == 'config' ||
          name == 'authorized_keys') {
        continue;
      }
      String pem;
      try {
        pem = await e.readAsString();
      } catch (_) {
        continue;
      }
      if (!pem.contains('PRIVATE KEY') || existing.contains(pem.trim())) {
        continue;
      }
      String? pub;
      String? type;
      try {
        final info = KeyTools.inspect(pem, comment: name);
        pub = info.publicLine;
        type = info.type;
      } catch (_) {
        final pubFile = File('${e.path}.pub');
        if (await pubFile.exists()) pub = (await pubFile.readAsString()).trim();
      }
      await vault.put(SshKey(
        id: newId(),
        label: name,
        privatePem: pem,
        publicLine: pub,
        type: type,
      ));
      count++;
    }
    if (context.mounted) toast(context, 'Imported $count keys from ~/.ssh');
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final keys = vault.keys;
        final ids = vault.identities;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            PageHeader(
              title: 'Keychain',
              subtitle: 'SSH keys and reusable identities',
              actions: [
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Add key',
                  onSelected: (a) => a(),
                  itemBuilder: (_) => [
                    menuItem('Generate Ed25519 key', Icons.auto_awesome,
                        () => _generate(context)),
                    menuItem('Paste private key', Icons.content_paste,
                        () => showSideSheet(context, const KeyEditor())),
                    menuItem('Import from ~/.ssh', Icons.download_outlined,
                        () => _importFromSshDir(context)),
                  ],
                  child: const _FakeButton(
                      icon: Icons.vpn_key_outlined, label: 'Add key'),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      showSideSheet(context, const IdentityEditor()),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New identity'),
                ),
              ],
            ),
            _sectionLabel('Keys  (${keys.length})'),
            if (keys.isEmpty)
              _hint('Generate an Ed25519 key or import your existing keys.')
            else
              for (final k in keys) _KeyRow(k),
            const SizedBox(height: 18),
            _sectionLabel('Identities  (${ids.length})'),
            if (ids.isEmpty)
              _hint('An identity is a username with a key or password '
                  'that many hosts can share.')
            else
              for (final i in ids) _IdentityRow(i),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
      );
}

class _FakeButton extends StatelessWidget {
  const _FakeButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.text),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow(this.k);

  final SshKey k;

  Future<void> _install(BuildContext context) async {
    final pub = k.publicLine;
    if (pub == null) {
      toast(context, 'Public key unknown for this key');
      return;
    }
    final host = await showDialog<Host>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Install public key on...'),
        children: [
          for (final h in AppState.I.vault.hosts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text(h.displayName),
            ),
        ],
      ),
    );
    if (host == null) return;
    final escaped = pub.replaceAll("'", r"'\''");
    final cmd = 'umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && '
        "(grep -qxF '$escaped' ~/.ssh/authorized_keys || "
        "echo '$escaped' >> ~/.ssh/authorized_keys)";
    try {
      final conn = await AppState.I.connector.connect(host);
      final r = await conn.client.runWithResult(cmd);
      conn.close();
      if (context.mounted) {
        toast(
            context,
            r.exitCode == 0
                ? 'Key installed on ${host.displayName}'
                : 'Install failed (exit ${r.exitCode})');
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Install failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: ItemTile(
        leading: const IconBox(Icons.vpn_key_outlined),
        title: k.label,
        subtitle: k.publicLine ?? 'Encrypted key (public part unknown)',
        mono: true,
        trailing: k.type == null
            ? null
            : Badge2(k.type!.replaceFirst('ssh-', '')),
        onDoubleTap: () => showSideSheet(context, KeyEditor(sshKey: k)),
        menu: [
          if (k.publicLine != null)
            menuItem('Copy public key', Icons.copy,
                () => copyToClipboard(context, k.publicLine!)),
          menuItem('Install on host...', Icons.upload_outlined,
              () => _install(context)),
          menuItem('Edit', Icons.edit_outlined,
              () => showSideSheet(context, KeyEditor(sshKey: k))),
          const PopupMenuDivider(),
          menuItem('Delete', Icons.delete_outline, () async {
            final ok = await confirmDialog(context,
                title: 'Delete key "${k.label}"?',
                message: 'Hosts using this key will fall back to password.');
            if (ok) await AppState.I.vault.delete(k.id);
          }, danger: true),
        ],
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow(this.i);

  final Identity i;

  @override
  Widget build(BuildContext context) {
    final key = AppState.I.vault.byId<SshKey>(i.keyId);
    final parts = [
      i.username,
      if (key != null) 'key: ${key.label}',
      if (i.password != null) 'password',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: ItemTile(
        leading: const IconBox(Icons.person_outline, color: AppColors.info),
        title: i.label,
        subtitle: parts.join('  |  '),
        onDoubleTap: () => showSideSheet(context, IdentityEditor(identity: i)),
        menu: [
          menuItem('Edit', Icons.edit_outlined,
              () => showSideSheet(context, IdentityEditor(identity: i))),
          menuItem('Delete', Icons.delete_outline, () async {
            final ok = await confirmDialog(context,
                title: 'Delete identity "${i.label}"?',
                message: 'Hosts using it will lose these credentials.');
            if (ok) await AppState.I.vault.delete(i.id);
          }, danger: true),
        ],
      ),
    );
  }
}
