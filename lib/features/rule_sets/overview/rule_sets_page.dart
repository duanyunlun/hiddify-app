import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/rule_sets/model/rule_set.dart';
import 'package:hiddify/features/rule_sets/notifier/rule_sets_notifier.dart';
import 'package:hiddify/features/rule_sets/overview/rule_set_catalog_sheet.dart';
import 'package:hiddify/features/rule_sets/overview/rule_set_editor_sheet.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Manages the rule sets that are part of the active configuration.
///
/// A rule set added here becomes a `route.rule_set` entry in the generated
/// config, so routing rules (and the built in region rules) can reference its
/// tag. Nothing is downloaded by the app itself: sing-box fetches remote rule
/// sets using `update_interval`, which is why the interval is editable.
class RuleSetsPage extends ConsumerWidget {
  const RuleSetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final strings = t.pages.settings.routing.ruleSets;
    final theme = Theme.of(context);
    final state = ref.watch(ruleSetsProvider);
    final notifier = ref.read(ruleSetsProvider.notifier);

    final enabledCount = state.enabledRuleSets.length;

    void openCatalog() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const RuleSetCatalogSheet(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.title),
        actions: [
          IconButton(
            tooltip: strings.browse,
            icon: const Icon(Icons.storefront_rounded),
            onPressed: openCatalog,
          ),
          IconButton(
            tooltip: strings.addByUrl,
            icon: const Icon(Icons.add_link_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const RuleSetEditorSheet(),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    enabledCount == 0
                        ? strings.noneEnabled
                        : strings.enabledCount(count: enabledCount.toString()),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (state.ruleSets.isNotEmpty)
                  TextButton(
                    onPressed: () => _confirmClear(context, ref),
                    child: Text(strings.clear),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.ruleSets.isEmpty
                ? _EmptyState(onBrowse: openCatalog)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: state.ruleSets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                    itemBuilder: (context, index) {
                      final entry = state.ruleSets[index];
                      return _RuleSetTile(
                        entry: entry,
                        onToggle: (value) => notifier.setEnabled(entry.tag, value),
                        onEdit: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => RuleSetEditorSheet(existing: entry),
                        ),
                        onDelete: () => notifier.remove(entry.tag),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).requireValue;
    final strings = t.pages.settings.routing.ruleSets;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.dialog.clearTitle),
        content: Text(strings.dialog.clearMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.dialog.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.dialog.remove)),
        ],
      ),
    );
    if (confirmed ?? false) ref.read(ruleSetsProvider.notifier).clear();
  }
}

class _RuleSetTile extends ConsumerWidget {
  const _RuleSetTile({
    required this.entry,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final RuleSetEntry entry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(translationsProvider).requireValue.pages.settings.routing.ruleSets;
    return ListTile(
      leading: Icon(
        entry.type == RuleSetType.local ? Icons.folder_rounded : Icons.cloud_download_rounded,
        color: entry.enabled ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(entry.tag, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text(
        entry.type == RuleSetType.local
            ? (entry.localPath ?? strings.tile.localFile)
            : '${entry.url}\n${strings.tile.updateEvery(interval: entry.updateInterval)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      isThreeLine: entry.type != RuleSetType.local,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch.adaptive(value: entry.enabled, onChanged: onToggle),
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (_) => [
              PopupMenuItem(onTap: onEdit, child: Text(strings.tile.edit)),
              PopupMenuItem(onTap: onDelete, child: Text(strings.tile.delete)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(translationsProvider).requireValue.pages.settings.routing.ruleSets;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rule_folder_rounded, size: 56, color: theme.colorScheme.outline),
            const Gap(16),
            Text(
              strings.empty.title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              strings.empty.message,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const Gap(24),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.storefront_rounded),
              label: Text(strings.browse),
            ),
          ],
        ),
      ),
    );
  }
}
