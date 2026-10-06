import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/rule_sets/notifier/rule_sets_notifier.dart';
import 'package:hiddify/features/rule_sets/overview/rule_set_route_prompt.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Browses a remote rule set catalog and adds entries to the configuration.
///
/// The catalog format is the one `GUI-for-Cores/Ruleset-Hub` publishes
/// (`{geosite, geoip, list[]}`); the address is editable so any mirror or a self
/// hosted catalog works.
class RuleSetCatalogSheet extends HookConsumerWidget {
  const RuleSetCatalogSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(translationsProvider).requireValue.pages.settings.routing.ruleSets;
    final c = strings.catalog;
    final state = ref.watch(ruleSetsProvider);
    final notifier = ref.read(ruleSetsProvider.notifier);

    final urlController = useTextEditingController(text: state.catalogUrl);
    final query = useState('');
    final filterType = useState<String?>(null);

    useEffect(() {
      // Load once when the sheet opens.
      Future.microtask(notifier.loadCatalog);
      return null;
    }, const []);

    final entries = state.catalog.entries.where((entry) {
      if (filterType.value != null && entry.type != filterType.value) return false;
      if (query.value.isEmpty) return true;
      final needle = query.value.toLowerCase();
      return entry.name.toLowerCase().contains(needle) || entry.description.toLowerCase().contains(needle);
    }).toList();

    final availableTypes = state.catalog.entries.map((e) => e.type).toSet().toList()..sort();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(c.title, style: theme.textTheme.titleLarge)),
                if (state.isLoadingCatalog)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    tooltip: c.reload,
                    onPressed: notifier.loadCatalog,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: c.urlLabel,
                helperText: c.urlHelper,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: c.useThisUrl,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () async {
                    await notifier.setCatalogUrl(urlController.text);
                    await notifier.loadCatalog();
                  },
                ),
              ),
              maxLines: 2,
              minLines: 1,
            ),
          ),
          if (state.catalogError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    c.loadFailed(error: state.catalogError!),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
          if (state.catalog.entries.isNotEmpty) ...[
            const Gap(12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => query.value = value,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: c.searchHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (availableTypes.length > 1) ...[
              const Gap(8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    ChoiceChip(
                      label: Text(c.all),
                      selected: filterType.value == null,
                      onSelected: (_) => filterType.value = null,
                    ),
                    for (final type in availableTypes) ...[
                      const Gap(8),
                      ChoiceChip(
                        label: Text(type),
                        selected: filterType.value == type,
                        onSelected: (_) => filterType.value = type,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const Gap(8),
          const Divider(height: 1),
          Expanded(
            child: state.catalog.entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        state.isLoadingCatalog ? c.loading : c.empty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final already = state.containsTag(entry.tag);
                      return ListTile(
                        dense: true,
                        leading: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(entry.type, style: theme.textTheme.labelSmall),
                        ),
                        title: Text(entry.name, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                          entry.count > 0
                              ? '${c.rulesCount(count: entry.count.toString())}${entry.description.isEmpty ? '' : ' · ${entry.description}'}'
                              : entry.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: already
                            ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                            : IconButton(
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                onPressed: () async {
                                  final ok = notifier.addFromCatalog(entry);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? c.added(tag: entry.tag) : c.addFailed(tag: entry.tag)),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                  // A rule set on its own routes nothing: only a
                                  // rule that references its tag has an effect,
                                  // so offer to create one right away.
                                  if (ok) {
                                    await offerRouteRuleForRuleSet(context, ref, tag: entry.tag);
                                  }
                                },
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
