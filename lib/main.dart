import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data/vault.dart';
import 'ui/home_shell.dart';
import 'ui/lock_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UrTerminalApp());
  await AppState.I.vault.init();
}

class UrTerminalApp extends StatelessWidget {
  const UrTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ur.Terminal',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(),
      home: const _VaultGate(),
    );
  }
}

class _VaultGate extends StatelessWidget {
  const _VaultGate();

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        switch (vault.status) {
          case VaultStatus.loading:
            return const Scaffold(body: SizedBox.shrink());
          case VaultStatus.empty:
          case VaultStatus.locked:
            return const LockScreen(key: ValueKey('lock'));
          case VaultStatus.unlocked:
            return const HomeShell(key: ValueKey('home'));
        }
      },
    );
  }
}
