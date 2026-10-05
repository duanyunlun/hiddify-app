import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/rule_sets/model/rule_set.dart';
import 'package:hiddify/features/rule_sets/notifier/rule_sets_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Adds or edits a single rule set.
class RuleSetEditorSheet extends HookConsumerWidget {
  const RuleSetEditorSheet({super.key, this.existing});

  /// When set the sheet edits this entry instead of adding a new one.
  final RuleSetEntry? existing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(translationsProvider).requireValue.pages.settings.routing.ruleSets;
    final s = strings.editor;
    final isEditing = existing != null;

    final tagController = useTextEditingController(text: existing?.tag ?? '');
    final urlController = useTextEditingController(text: existing?.url ?? '');
    final pathController = useTextEditingController(text: existing?.localPath ?? '');
    final intervalController = useTextEditingController(
      text: existing?.updateInterval ?? RuleSetEntry.defaultUpdateInterval,
    );
    final type = useState(existing?.type ?? RuleSetType.remote);
    final format = useState(existing?.format ?? RuleSetFormat.binary);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? s.editTitle : s.addTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const Gap(8),
            SegmentedButton<RuleSetType>(
              segments: [
                ButtonSegment(value: RuleSetType.remote, label: Text(s.typeRemote), icon: const Icon(Icons.cloud_rounded)),
                ButtonSegment(value: RuleSetType.local, label: Text(s.typeLocal), icon: const Icon(Icons.folder_rounded)),
              ],
              selected: {type.value},
              onSelectionChanged: (value) => type.value = value.first,
            ),
            const Gap(16),
            TextField(
              controller: tagController,
              enabled: !isEditing,
              decoration: InputDecoration(
                labelText: s.tag,
                helperText: s.tagHelper,
                border: const OutlineInputBorder(),
              ),
            ),
            const Gap(16),
            if (type.value == RuleSetType.remote)
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: s.url,
                  helperText: s.urlHelper,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                minLines: 1,
              )
            else
              TextField(
                controller: pathController,
                decoration: InputDecoration(
                  labelText: s.path,
                  helperText: s.pathHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            const Gap(16),
            DropdownButtonFormField<RuleSetFormat>(
              initialValue: format.value,
              decoration: InputDecoration(labelText: s.format, border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: RuleSetFormat.binary, child: Text(s.formatBinary)),
                DropdownMenuItem(value: RuleSetFormat.source, child: Text(s.formatSource)),
              ],
              onChanged: (value) => format.value = value ?? RuleSetFormat.binary,
            ),
            if (type.value == RuleSetType.remote) ...[
              const Gap(16),
              TextField(
                controller: intervalController,
                decoration: InputDecoration(
                  labelText: s.updateInterval,
                  helperText: s.updateIntervalHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const Gap(24),
            FilledButton.icon(
              onPressed: () {
                final notifier = ref.read(ruleSetsProvider.notifier);
                final tag = tagController.text.trim();
                final url = urlController.text.trim();
                final path = pathController.text.trim();
                if (tag.isEmpty) {
                  _toast(context, s.tagRequired);
                  return;
                }
                if (type.value == RuleSetType.remote && url.isEmpty) {
                  _toast(context, s.urlRequired);
                  return;
                }
                if (type.value == RuleSetType.local && path.isEmpty) {
                  _toast(context, s.pathRequired);
                  return;
                }
                final entry = RuleSetEntry(
                  tag: tag,
                  url: url,
                  type: type.value,
                  format: format.value,
                  updateInterval: intervalController.text.trim().isEmpty
                      ? RuleSetEntry.defaultUpdateInterval
                      : intervalController.text.trim(),
                  enabled: existing?.enabled ?? true,
                  localPath: type.value == RuleSetType.local ? path : null,
                );
                if (isEditing) {
                  notifier.replace(entry);
                } else if (!notifier.add(entry)) {
                  _toast(context, s.duplicate(tag: tag));
                  return;
                }
                Navigator.of(context).pop();
              },
              icon: Icon(isEditing ? Icons.save_rounded : Icons.add_rounded),
              label: Text(isEditing ? s.save : s.add),
            ),
            if (isEditing) ...[
              const Gap(8),
              TextButton.icon(
                onPressed: () {
                  ref.read(ruleSetsProvider.notifier).remove(existing!.tag);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(strings.tile.delete),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
