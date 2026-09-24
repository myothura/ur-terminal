import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../../data/ssh_config_import.dart';
import '../../data/termius_import.dart';
import '../editors/host_editor.dart';
import '../theme.dart';
import '../widgets.dart';

class HostsPage extends StatefulWidget {
  const HostsPage({super.key});

  static Future<void> requestNew(BuildContext context) =>
      showSideSheet(context, const HostEditor());

  @override
  State<HostsPage> createState() => _HostsPageState();
}

const _allGroups = '__all__';
const _ungrouped = '__none__';

class _HostsPageState extends State<HostsPage> {
  final _search = TextEditingController();
  String _group = _allGroups;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Host> _filtered(List<Host> hosts) {
    final q = _search.text.trim().toLowerCase();
    return hosts.where((h) {
      if (_group == _ungrouped && h.groupId != null) return false;
      if (_group != _allGroups && _group != _ungrouped && h.groupId != _group) {
        return false;
      }
      if (q.isEmpty) return true;
      return h.label.toLowerCase().contains(q) ||
          h.address.toLowerCase().contains(q) ||
          (h.username ?? '').toLowerCase().contains(q) ||
          h.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _importConfig() async {
    final report = await SshConfigImporter(AppState.I.vault).importFile();
    if (!mounted) return;
    final warn = report.warnings.isEmpty
        ? ''
        : '  (${report.warnings.length} skipped)';
    toast(context,
        'Imported ${report.hosts} hosts and ${report.keys} keys$warn');
  }

  Future<void> _importTermius() async {
    await importTermius(context);
  }

  Future<void> _newGroup() async {
    final name = await AppState.I.connector.prompter
        .askText('New group', 'Group name', secret: false);
    if (name == null || name.trim().isEmpty) return;
    await AppState.I.vault.put(HostGroup(id: newId(), name: name.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppState.I.vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final hosts = _filtered(vault.hosts);
        final groups = vault.groups;
        if (_group != _allGroups &&
            _group != _ungrouped &&
            !groups.any((g) => g.id == _group)) {
          _group = _allGroups;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Hosts',
              subtitle: '${vault.hosts.length} saved',
              actions: [
                SearchBox(controller: _search, hint: 'Search hosts, tags'),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'More',
                  onSelected: (a) => a(),
                  itemBuilder: (_) => [
                    menuItem('New group', Icons.create_new_folder_outlined,
                        _newGroup),
                    menuItem('Import ~/.ssh/config', Icons.download_outlined,
                        _importConfig),
                    menuItem('Import from Termius...', Icons.move_down,
                        _importTermius),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_horiz, color: AppColors.textMuted),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => HostsPage.requestNew(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New host'),
                ),
              ],
            ),
            if (groups.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _chip('All', _allGroups),
                    for (final g in groups) _groupChip(g),
                    _chip('Ungrouped', _ungrouped),
                  ],
                ),
              ),
            Expanded(
              child: vault.hosts.isEmpty
                  ? EmptyState(
                      icon: Icons.dns_outlined,
                      title: 'No hosts yet',
                      message: 'Add a server, or import everything from your '
                          '~/.ssh/config in one click.',
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: _importConfig,
                            child: const Text('Import ~/.ssh/config'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => HostsPage.requestNew(context),
                            child: const Text('New host'),
                          ),
                        ],
                      ),
                    )
                  : hosts.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message: 'Try a different search or group.',
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            mainAxisExtent: 70,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: hosts.length,
                          itemBuilder: (context, i) => _HostCard(hosts[i]),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(String label, String value) {
    final selected = _group == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.accentDim,
        onSelected: (_) => setState(() => _group = value),
      ),
    );
  }

  Widget _groupChip(HostGroup g) {
    return GestureDetector(
      onSecondaryTap: () async {
        final ok = await confirmDialog(
          context,
          title: 'Delete group "${g.name}"?',
          message: 'Hosts in this group are kept and become ungrouped.',
        );
        if (!ok) return;
        final vault = AppState.I.vault;
        for (final h in vault.hosts.where((h) => h.groupId == g.id).toList()) {
          await vault.put(Host.fromJson({...h.toJson(), 'groupId': null}));
        }
        await vault.delete(g.id);
      },
      child: _chip(g.name, g.id),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard(this.host);

  final Host host;

  @override
  Widget build(BuildContext context) {
    final app = AppState.I;
    final creds = app.connector.resolve(host);
    final user = creds.username;
    final sub = '${user == null ? '' : '$user@'}${host.address}'
        '${host.port == 22 ? '' : ':${host.port}'}';
    return ItemTile(
      leading: IconBox(
        creds.key != null ? Icons.vpn_key_outlined : Icons.dns_outlined,
      ),
      title: host.displayName,
      subtitle: sub,
      mono: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (host.jumpHostId != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Badge2('jump', color: AppColors.info),
            ),
          if (host.totpSecret != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Badge2('2FA', color: AppColors.warning),
            ),
        ],
      ),
      onDoubleTap: () => app.openHost(host),
      menu: [
        menuItem('Connect', Icons.play_arrow_rounded,
            () => app.openHost(host)),
        menuItem('Edit', Icons.edit_outlined,
            () => showSideSheet(context, HostEditor(host: host))),
        menuItem('Duplicate', Icons.copy_all_outlined, () {
          app.vault.put(Host.fromJson({
            ...host.toJson(),
            'id': newId(),
            'label': '${host.displayName} copy',
          }));
        }),
        menuItem('Copy ssh command', Icons.terminal, () {
          final p = host.port == 22 ? '' : ' -p ${host.port}';
          copyToClipboard(
            context,
            'ssh$p ${user == null ? '' : '$user@'}${host.address}',
            what: 'ssh command copied',
          );
        }),
        const PopupMenuDivider(),
        menuItem('Delete', Icons.delete_outline, () async {
          final ok = await confirmDialog(
            context,
            title: 'Delete "${host.displayName}"?',
            message: 'Port forwarding rules that use this host stop working.',
          );
          if (ok) await app.vault.delete(host.id);
        }, danger: true),
      ],
    );
  }
}

/// Imports hosts.json produced by termius-local-export.
Future<void> importTermius(BuildContext context) async {
  final app = AppState.I;
  var path = TermiusImporter.defaultPath;
  if (!await File(path).exists()) {
    final picked = await app.connector.prompter.askText(
      'Import from Termius',
      'Path to hosts.json from termius-local-export\n'
          '(default ~/termius-export/hosts.json was not found)',
      secret: false,
    );
    if (picked == null || picked.trim().isEmpty) return;
    path = picked.trim();
  }
  final r = await TermiusImporter(app.vault).importFile(path);
  if (!context.mounted) return;
  final skipped = r.warnings.isEmpty ? '' : '  (${r.warnings.length} skipped)';
  toast(context, 'Imported ${r.hosts} hosts and ${r.keys} keys from Termius$skipped');
  for (final w in r.warnings) {
    debugPrint('termius import: $w');
  }
}
