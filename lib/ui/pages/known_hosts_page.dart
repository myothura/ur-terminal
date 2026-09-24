import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../widgets.dart';

class KnownHostsPage extends StatelessWidget {
  const KnownHostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final list = vault.knownHosts;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Known Hosts',
              subtitle: 'Trusted server fingerprints (synced with your vault)',
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: 'Nothing trusted yet',
                      message: 'Fingerprints are saved the first time you '
                          'accept a server. A changed key is always flagged.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final k = list[i];
                        return ItemTile(
                          leading: const IconBox(Icons.verified_user_outlined),
                          title: k.endpoint,
                          subtitle: '${k.keyType}   ${k.fingerprint}',
                          mono: true,
                          menu: [
                            menuItem('Copy fingerprint', Icons.copy,
                                () => copyToClipboard(context, k.fingerprint)),
                            menuItem('Forget', Icons.delete_outline, () async {
                              final ok = await confirmDialog(context,
                                  title: 'Forget ${k.endpoint}?',
                                  message: 'You will be asked to verify the '
                                      'fingerprint again on next connect.',
                                  confirm: 'Forget');
                              if (ok) await vault.delete(k.id);
                            }, danger: true),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
