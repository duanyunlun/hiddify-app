import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hiddify/features/system_proxy/notifier/system_proxy_bypass_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lets the user add entries to the Windows system proxy bypass list.
///
/// The routing decision belongs to the core, so the list normally holds nothing
/// but the loopback and private ranges. It exists because a bypass list can also
/// be inherited from another program, and an entry there keeps traffic away from
/// the proxy no matter what the app's rules say.
class SystemProxyBypassPage extends ConsumerWidget {
  const SystemProxyBypassPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final s = t.pages.settings.routing.generalOptions.systemProxyBypass;
    final state = ref.watch(systemProxyBypassProvider);
    final notifier = ref.read(systemProxyBypassProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.reload,
            icon: const Icon(Icons.sync_rounded),
            onPressed: notifier.reloadFromSystem,
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(s.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.description, style: theme.textTheme.bodySmall),
                if (!state.applied) ...[
                  const Gap(8),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.outline),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          s.notApplied,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ],
                const Gap(12),
                Text(s.localAlwaysKept, style: theme.textTheme.labelLarge),
                const Gap(4),
                Text(kLocalSystemProxyBypass.join('  '), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Text(s.yourEntries, style: theme.textTheme.labelLarge),
                ),
              ),
              if (state.entries.isNotEmpty)
                TextButton(onPressed: notifier.clear, child: Text(s.clear)),
            ],
          ),
          Expanded(
            child: state.entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(s.empty, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: state.entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                    itemBuilder: (context, index) {
                      final entry = state.entries[index];
                      return ListTile(
                        leading: const Icon(Icons.block_rounded),
                        title: Text(entry, style: const TextStyle(fontFamily: 'monospace')),
                        onTap: () => _showEditor(context, ref, previous: entry),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: s.edit,
                              icon: const Icon(Icons.edit_rounded),
                              onPressed: () => _showEditor(context, ref, previous: entry),
                            ),
                            IconButton(
                              tooltip: s.delete,
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => notifier.remove(entry),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, WidgetRef ref, {String? previous}) {
    final t = ref.read(translationsProvider).requireValue;
    final s = t.pages.settings.routing.generalOptions.systemProxyBypass;
    final controller = TextEditingController(text: previous ?? '');
    final notifier = ref.read(systemProxyBypassProvider.notifier);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(previous == null ? s.add : s.edit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: s.pattern,
                hintText: '10.0.0.0/8',
                helperText: s.patternHelper,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
          FilledButton(
            onPressed: () {
              final problem = previous == null
                  ? notifier.add(controller.text)
                  : notifier.update(previous, controller.text);
              if (problem != null) {
                final label = switch (problem) {
                  'empty' => s.problems.empty,
                  'separator' => s.problems.separator,
                  'whitespace' => s.problems.whitespace,
                  'duplicate' => s.problems.duplicate,
                  _ => problem,
                };
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.invalid(problem: label))));
                return;
              }
              Navigator.of(context).pop();
            },
            child: Text(previous == null ? s.add : s.save),
          ),
        ],
      ),
    );
  }
}
