import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../data/models.dart';
import '../../ssh/forward_manager.dart';
import '../editors/forward_editor.dart';
import '../theme.dart';
import '../widgets.dart';

class ForwardsPage extends StatelessWidget {
  const ForwardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    return ListenableBuilder(
      listenable: Listenable.merge([app.vault, app.forwards]),
      builder: (context, _) {
        final rules = app.vault.forwards;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Port Forwarding',
              subtitle: '${app.forwards.runningCount} of ${rules.length} '
                  'running  |  each rule keeps its own SSH connection',
              actions: [
                if (rules.isNotEmpty)
                  OutlinedButton(
                    onPressed: app.forwards.stopAll,
                    child: const Text('Stop all'),
                  ),
                FilledButton.icon(
                  onPressed: app.vault.hosts.isEmpty
                      ? null
                      : () => showSideSheet(context, const ForwardEditor()),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New rule'),
                ),
              ],
            ),
            Expanded(
              child: rules.isEmpty
                  ? EmptyState(
                      icon: Icons.swap_horiz,
                      title: 'No tunnels yet',
                      message: app.vault.hosts.isEmpty
                          ? 'Add a host first, then create Local (-L), '
                              'Remote (-R) or Dynamic SOCKS5 (-D) rules.'
                          : 'Create Local (-L), Remote (-R) or Dynamic '
                              'SOCKS5 (-D) rules. Auto-start rules come up '
                              'when the vault unlocks and reconnect on drops.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: rules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _RuleRow(rules[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow(this.rule);

  final ForwardRule rule;

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final a = app.forwards.stateOf(rule.id);
    final host = app.vault.byId<Host>(rule.hostId);
    final state = a?.state ?? ForwardState.stopped;
    final (color, label) = switch (state) {
      ForwardState.stopped => (AppColors.textFaint, 'Stopped'),
      ForwardState.starting => (AppColors.warning, 'Starting'),
      ForwardState.running => (AppColors.accent, 'Running'),
      ForwardState.reconnecting => (AppColors.warning, 'Reconnecting'),
      ForwardState.failed => (AppColors.danger, 'Failed'),
    };
    final stats = a == null || state != ForwardState.running
        ? (a?.error ?? '')
        : '${a.openConnections} open  |  ${a.totalConnections} total  |  '
            'in ${humanBytes(a.bytesIn)}  out ${humanBytes(a.bytesOut)}';

    return ItemTile(
      leading: IconBox(
        rule.type == ForwardType.dynamic ? Icons.hub_outlined : Icons.swap_horiz,
        color: color == AppColors.textFaint ? AppColors.textMuted : color,
      ),
      title: '${rule.label.isEmpty ? rule.summary : rule.label}'
          '   ${rule.type.code}',
      subtitle: [
        rule.summary,
        'via ${host?.displayName ?? 'missing host'}',
        if (stats.isNotEmpty) stats,
      ].join('   |   '),
      mono: true,
      onDoubleTap: () => showSideSheet(context, ForwardEditor(rule: rule)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rule.autoStart)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Badge2('auto'),
            ),
          StatusDot(color),
          const SizedBox(width: 6),
          SizedBox(
            width: 86,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
          ),
          Switch(
            value: state != ForwardState.stopped,
            onChanged: (_) => app.forwards.toggle(rule),
          ),
        ],
      ),
      menu: [
        menuItem('Edit', Icons.edit_outlined,
            () => showSideSheet(context, ForwardEditor(rule: rule))),
        if (rule.type != ForwardType.remote)
          menuItem('Copy local address', Icons.copy, () {
            copyToClipboard(context, '${rule.bindHost}:${rule.bindPort}');
          }),
        const PopupMenuDivider(),
        menuItem('Delete', Icons.delete_outline, () async {
          final ok = await confirmDialog(context,
              title: 'Delete rule?', message: rule.summary);
          if (!ok) return;
          await app.forwards.stop(rule.id);
          await app.vault.delete(rule.id);
        }, danger: true),
      ],
    );
  }
}
