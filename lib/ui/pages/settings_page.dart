import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/vault_crypto.dart';
import '../../data/prefs.dart';
import '../../data/ssh_config_import.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final p = AppState.I.connector.prompter;
    final current = await p.askText('Change master password', 'Current password');
    if (current == null) return;
    final next = await p.askText('Change master password',
        'New password (at least 8 characters)');
    if (next == null) return;
    if (next.length < 8) {
      if (context.mounted) toast(context, 'Password too short');
      return;
    }
    final again = await p.askText('Change master password', 'Repeat new password');
    if (again != next) {
      if (context.mounted) toast(context, 'Passwords do not match');
      return;
    }
    try {
      await AppState.I.vault.changePassword(current, next);
      if (context.mounted) toast(context, 'Master password changed');
    } on WrongPasswordException {
      if (context.mounted) toast(context, 'Current password is wrong');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const PageHeader(title: 'Settings'),
        _Group(
          title: 'Appearance',
          children: [
            _Row(
              icon: Icons.blur_on,
              title: 'Terminal transparency',
              subtitle: 'Glass blur shows the desktop behind the terminal',
              action: SizedBox(
                width: 220,
                child: ValueListenableBuilder<double>(
                  valueListenable: Prefs.I.terminalOpacity,
                  builder: (_, v, _) => Slider(
                    value: v,
                    min: 0.4,
                    max: 1.0,
                    divisions: 12,
                    label: '${(v * 100).round()}%',
                    onChanged: (x) => Prefs.I.terminalOpacity.value = x,
                  ),
                ),
              ),
            ),
            _Row(
              icon: Icons.format_size,
              title: 'Terminal font size',
              subtitle: 'JetBrains Mono with Myanmar fallback  (Cmd+= / Cmd+-)',
              action: SizedBox(
                width: 220,
                child: ValueListenableBuilder<double>(
                  valueListenable: Prefs.I.fontSize,
                  builder: (_, v, _) => Slider(
                    value: v,
                    min: 10,
                    max: 24,
                    divisions: 28,
                    label: v.toStringAsFixed(1),
                    onChanged: (x) => Prefs.I.fontSize.value = x,
                  ),
                ),
              ),
            ),
          ],
        ),
        _Group(
          title: 'Security',
          children: [
            _Row(
              icon: Icons.password,
              title: 'Master password',
              subtitle: 'Argon2id key derivation, XChaCha20-Poly1305 records',
              action: OutlinedButton(
                onPressed: () => _changePassword(context),
                child: const Text('Change'),
              ),
            ),
            _Row(
              icon: Icons.lock_clock_outlined,
              title: 'Lock now',
              subtitle: 'Closes all sessions and tunnels  (Cmd+L)',
              action: OutlinedButton(
                onPressed: AppState.I.lock,
                child: const Text('Lock'),
              ),
            ),
          ],
        ),
        _Group(
          title: 'Sync',
          children: const [
            _Row(
              icon: Icons.cloud_outlined,
              title: 'Google Drive',
              subtitle: 'Hidden app folder, end-to-end encrypted',
              action: Badge2('next build'),
            ),
            _Row(
              icon: Icons.merge_type,
              title: 'GitHub',
              subtitle: 'Private repo, version history per sync',
              action: Badge2('next build'),
            ),
            _Row(
              icon: Icons.apple,
              title: 'iCloud',
              subtitle: 'Sign in with Apple, shared with iOS app',
              action: Badge2('next build'),
            ),
          ],
        ),
        _Group(
          title: 'Data',
          children: [
            _Row(
              icon: Icons.download_outlined,
              title: 'Import ~/.ssh/config',
              subtitle: 'Hosts, users, ports, IdentityFile and ProxyJump',
              action: OutlinedButton(
                onPressed: () async {
                  final r = await SshConfigImporter(vault).importFile();
                  if (context.mounted) {
                    toast(context,
                        'Imported ${r.hosts} hosts and ${r.keys} keys');
                  }
                },
                child: const Text('Import'),
              ),
            ),
            _Row(
              icon: Icons.folder_outlined,
              title: 'Vault file',
              subtitle: vault.filePath,
              action: OutlinedButton(
                onPressed: () => copyToClipboard(context, vault.filePath),
                child: const Text('Copy path'),
              ),
            ),
          ],
        ),
        const _Group(
          title: 'About',
          children: [
            _Row(
              icon: Icons.info_outline,
              title: 'Ur.Terminal 0.1.0',
              subtitle: 'MIT licensed. github.com/myothura/ur-terminal',
            ),
          ],
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
