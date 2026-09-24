import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../core/vault_crypto.dart';
import '../../sync/folder_provider.dart';
import '../../sync/github_provider.dart';
import '../../sync/sync_manager.dart';
import '../theme.dart';
import '../widgets.dart';

/// Settings > Sync.
class SyncSection extends StatelessWidget {
  const SyncSection({super.key, required this.group, required this.row});

  /// Settings page's group / row builders, so the look stays consistent.
  final Widget Function(String title, List<Widget> children) group;
  final Widget Function({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) row;

  @override
  Widget build(BuildContext context) {
    final sync = SyncManager.I;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final p = sync.provider;
        if (p == null) return group('Sync', _choices(context, sync));

        final (color, status) = switch (sync.state) {
          SyncState.syncing => (AppColors.warning, 'Syncing...'),
          SyncState.error => (AppColors.danger, sync.error ?? 'Error'),
          SyncState.conflict => (AppColors.danger, sync.error ?? 'Conflict'),
          _ => (
              AppColors.accent,
              sync.lastSync == null
                  ? 'Connected'
                  : 'Synced ${_ago(sync.lastSync!)}'
            ),
        };
        return group('Sync', [
          row(
            icon: p.type == 'github' ? Icons.merge_type : Icons.cloud_done_outlined,
            title: p.title,
            subtitle: 'End-to-end encrypted  |  $status',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusDot(color),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: sync.state == SyncState.syncing ? null : sync.syncNow,
                  child: const Text('Sync now'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Disconnect sync?',
                        message: 'The cloud copy is kept. This Mac stops syncing.',
                        confirm: 'Disconnect');
                    if (ok) await sync.disconnect();
                  },
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ),
          if (sync.state == SyncState.conflict)
            row(
              icon: Icons.warning_amber_rounded,
              title: 'Different vault in the cloud',
              subtitle: 'Keep this Mac (overwrites the cloud copy), or switch '
                  'this Mac to the cloud vault (needs its master password).',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => _keepLocal(context),
                    child: const Text('Keep this Mac'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _useCloud(context),
                    child: const Text('Use cloud vault'),
                  ),
                ],
              ),
            ),
        ]);
      },
    );
  }

  List<Widget> _choices(BuildContext context, SyncManager sync) {
    final folders = FolderSyncProvider.detect();
    return [
      for (final f in folders)
        row(
          icon: f.label.startsWith('iCloud')
              ? Icons.apple
              : f.label.startsWith('Google')
                  ? Icons.add_to_drive
                  : Icons.cloud_outlined,
          title: f.label,
          subtitle: 'Encrypted vault file in ${_short(f.folder)}',
          action: FilledButton(
            onPressed: () => sync.use(f),
            child: const Text('Use'),
          ),
        ),
      row(
        icon: Icons.merge_type,
        title: 'GitHub private repo',
        subtitle: 'Sign in with GitHub. Each sync is a commit in '
            '<you>/ur-terminal-vault (version history)',
        action: FilledButton(
          onPressed: () => _connectGitHub(context),
          child: const Text('Connect'),
        ),
      ),
      row(
        icon: Icons.folder_open_outlined,
        title: 'Custom folder',
        subtitle: 'Any synced folder: NAS, Syncthing, OneDrive...',
        action: OutlinedButton(
          onPressed: () async {
            final path = await AppState.I.connector.prompter.askText(
                'Custom sync folder', 'Folder path', secret: false);
            if (path == null || path.trim().isEmpty) return;
            final home = Platform.environment['HOME'] ?? '';
            final folder = path.trim().replaceFirst(RegExp(r'^~'), home);
            await sync.use(FolderSyncProvider(folder, label: _short(folder)));
          },
          child: const Text('Choose'),
        ),
      ),
      if (sync.error != null)
        row(
          icon: Icons.error_outline,
          title: 'Last error',
          subtitle: sync.error!,
        ),
    ];
  }

  Future<void> _keepLocal(BuildContext context) async {
    final ok = await confirmDialog(context,
        title: 'Overwrite the cloud copy?',
        message: 'The vault in the cloud will be replaced by this Mac\'s '
            'vault. Other devices will need this vault\'s master password.',
        confirm: 'Overwrite');
    if (ok) await SyncManager.I.replaceCloudWithLocal();
  }

  Future<void> _useCloud(BuildContext context) async {
    final ok = await confirmDialog(context,
        title: 'Switch to the cloud vault?',
        message: 'Hosts and keys on this Mac that are not in the cloud vault '
            'will be replaced.',
        confirm: 'Continue');
    if (!ok) return;
    final pw = await AppState.I.connector.prompter
        .askText('Cloud vault', 'Master password of the cloud vault');
    if (pw == null) return;
    try {
      await SyncManager.I.adoptCloud(pw);
      if (context.mounted) toast(context, 'Switched to the cloud vault');
    } on WrongPasswordException {
      if (context.mounted) toast(context, 'Wrong master password');
    }
  }

  Future<void> _connectGitHub(BuildContext context) async {
    var clientId = kGitHubClientId;
    if (clientId.isEmpty) {
      final id = await AppState.I.connector.prompter.askText(
        'GitHub OAuth App',
        'Client ID of your GitHub OAuth App (Device Flow enabled)',
        secret: false,
      );
      if (id == null || id.trim().isEmpty) return;
      clientId = id.trim();
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GitHubLoginDialog(clientId: clientId),
    );
  }

  static String _short(String path) {
    final home = Platform.environment['HOME'] ?? '';
    return path.startsWith(home) ? '~${path.substring(home.length)}' : path;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }
}

class _GitHubLoginDialog extends StatefulWidget {
  const _GitHubLoginDialog({required this.clientId});

  final String clientId;

  @override
  State<_GitHubLoginDialog> createState() => _GitHubLoginDialogState();
}

class _GitHubLoginDialogState extends State<_GitHubLoginDialog> {
  DeviceCode? _code;
  String? _error;
  String _status = 'Requesting a code from GitHub...';
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final code = await GitHubSyncProvider.startDeviceFlow(widget.clientId);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: code.userCode));
      setState(() {
        _code = code;
        _status = 'Code copied. Approve it in the browser...';
      });
      await Process.run('open', [code.verificationUri]);
      final token = await GitHubSyncProvider.waitForToken(
        widget.clientId,
        code,
        cancelled: () => _cancelled,
      );
      if (!mounted) return;
      setState(() => _status = 'Preparing private repo...');
      final provider = await GitHubSyncProvider.connect(token);
      await SyncManager.I.use(provider, token: token);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted && !_cancelled) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return AlertDialog(
      title: Text('Connect GitHub', style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (code != null) ...[
              const Text('Enter this code on github.com/login/device:'),
              const SizedBox(height: 14),
              Center(
                child: SelectableText(
                  code.userCode,
                  style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_error == null)
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_status)),
                ],
              )
            else
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 10),
            const Text(
              'Ur.Terminal asks for the "repo" scope to create and update a '
              'private ur-terminal-vault repository. Only encrypted data is '
              'stored there.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
      actions: [
        if (code != null && _error == null)
          TextButton(
            onPressed: () => Process.run('open', [code.verificationUri]),
            child: const Text('Open GitHub again'),
          ),
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context);
          },
          child: Text(_error == null ? 'Cancel' : 'Close'),
        ),
      ],
    );
  }
}
