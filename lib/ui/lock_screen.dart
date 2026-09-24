import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/vault_crypto.dart';
import '../data/vault.dart';
import 'theme.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Vault get vault => AppState.I.vault;
  bool get _creating => vault.status == VaultStatus.empty;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pw = _pw.text;
    setState(() => _error = null);
    if (_creating) {
      if (pw.length < 8) {
        setState(() => _error = 'Use at least 8 characters.');
        return;
      }
      if (pw != _pw2.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    } else if (pw.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      if (_creating) {
        await vault.create(pw);
      } else {
        await vault.unlock(pw);
      }
      await AppState.I.onUnlocked();
    } on WrongPasswordException {
      if (mounted) {
        setState(() => _error = 'Wrong master password.');
        _pw.selection =
            TextSelection(baseOffset: 0, extentOffset: _pw.text.length);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Logo(),
              const SizedBox(height: 28),
              Text(
                _creating ? 'Create your vault' : 'Unlock Ur.Terminal',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _creating
                    ? 'Your hosts, keys and snippets are encrypted with this '
                        'master password before they are stored or synced. '
                        'It cannot be recovered if you forget it.'
                    : 'Enter your master password.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pw,
                autofocus: true,
                obscureText: _obscure,
                enabled: !_busy,
                onSubmitted: (_) =>
                    _creating ? FocusScope.of(context).nextFocus() : _submit(),
                decoration: InputDecoration(
                  hintText: 'Master password',
                  prefixIcon: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.textFaint),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_creating) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _pw2,
                  obscureText: _obscure,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: 'Confirm master password',
                    prefixIcon: Icon(Icons.lock_outline,
                        size: 18, color: AppColors.textFaint),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_creating ? 'Create vault' : 'Unlock'),
              ),
              const SizedBox(height: 18),
              const Text(
                'End-to-end encrypted  |  Argon2id + XChaCha20-Poly1305',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Ur_',
          style: TextStyle(
            fontFamily: kMonoFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
