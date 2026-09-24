import 'package:flutter/material.dart';

import '../ssh/connector.dart';
import 'theme.dart';

/// Shows SSH-related prompts (host keys, passwords, 2FA) as dialogs.
class DialogPrompter implements SshPrompter {
  DialogPrompter(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  BuildContext? get _ctx {
    final c = navigatorKey.currentContext;
    if (c == null) debugPrint('[prompt] no navigator context');
    return c;
  }

  @override
  Future<bool> trustNewHostKey(
      String endpoint, String type, String fingerprint) async {
    final ctx = _ctx;
    if (ctx == null) return false;
    final r = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => _HostKeyDialog(
        title: 'Unknown host',
        message: 'This is the first connection to $endpoint. '
            'Verify the fingerprint before trusting it.',
        type: type,
        fingerprint: fingerprint,
        confirm: 'Trust and connect',
        danger: false,
      ),
    );
    return r ?? false;
  }

  @override
  Future<bool> acceptChangedHostKey(String endpoint, String type,
      String oldFingerprint, String newFingerprint) async {
    final ctx = _ctx;
    if (ctx == null) return false;
    final r = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => _HostKeyDialog(
        title: 'Host key changed',
        message: 'The host key for $endpoint does not match the saved one. '
            'This can mean the server was reinstalled, or that someone is '
            'intercepting the connection.\n\nSaved: $oldFingerprint',
        type: type,
        fingerprint: newFingerprint,
        confirm: 'Replace key and connect',
        danger: true,
      ),
    );
    return r ?? false;
  }

  @override
  Future<String?> askText(String title, String prompt,
      {bool secret = true}) async {
    final ctx = _ctx;
    if (ctx == null) return null;
    return showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => _TextPromptDialog(
        title: title,
        prompt: prompt,
        secret: secret,
      ),
    );
  }
}

class _HostKeyDialog extends StatelessWidget {
  const _HostKeyDialog({
    required this.title,
    required this.message,
    required this.type,
    required this.fingerprint,
    required this.confirm,
    required this.danger,
  });

  final String title;
  final String message;
  final String type;
  final String fingerprint;
  final String confirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            danger ? Icons.gpp_bad_outlined : Icons.gpp_maybe_outlined,
            color: danger ? AppColors.danger : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                '$type\n$fingerprint',
                style: const TextStyle(
                  fontFamily: kMonoFont,
                  fontSize: 12,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.prompt,
    required this.secret,
  });

  final String title;
  final String prompt;
  final bool secret;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _c.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.prompt),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              obscureText: widget.secret,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
