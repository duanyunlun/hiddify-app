import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';
import 'package:hiddify/features/system_proxy/notifier/system_proxy_bypass_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A single text field for the Windows system proxy bypass list, separated by
/// semicolons, which is the shape Windows itself uses.
///
/// The routing decision belongs to the core, so the list normally holds nothing
/// but the loopback and private ranges. It exists because a bypass list can also
/// be inherited from another program, and an entry there keeps traffic away from
/// the proxy no matter what the app's rules say.
class SystemProxyBypassPage extends HookConsumerWidget {
  const SystemProxyBypassPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final s = t.pages.settings.routing.generalOptions.systemProxyBypass;
    final state = ref.watch(systemProxyBypassProvider);
    final notifier = ref.read(systemProxyBypassProvider.notifier);

    final controller = useTextEditingController();
    final pending = useRef<Timer?>(null);
    final filled = useRef(false);

    // The current value is read back from the system asynchronously, so the field
    // is filled once it arrives and never afterwards, or the text would be reset
    // while it is being typed in.
    useEffect(() {
      if (!state.loaded || filled.value) return null;
      filled.value = true;
      controller.text = formatUserEntryText(state.entries);
      return null;
    }, [state.loaded]);

    // Writing the setting on every keystroke would be wasteful, and the field
    // must not be reset while it is being typed in, so the value is committed
    // once the typing pauses.
    void commitAfterPause(String value) {
      pending.value?.cancel();
      pending.value = Timer(const Duration(milliseconds: 600), () {
        unawaited(notifier.setEntries(parseUserEntryText(value)));
      });
    }

    useEffect(() {
      return () => pending.value?.cancel();
    }, const []);

    if (!state.loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(s.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.reload,
            icon: const Icon(Icons.sync_rounded),
            onPressed: () async {
              pending.value?.cancel();
              await notifier.reloadFromSystem();
              if (!context.mounted) return;
              controller.text = formatUserEntryText(ref.read(systemProxyBypassProvider).entries);
            },
          ),
          TextButton(
            onPressed: () async {
              pending.value?.cancel();
              await notifier.clear();
              controller.text = '';
            },
            child: Text(s.clear),
          ),
          const Gap(8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.description, style: theme.textTheme.bodySmall),
            const Gap(16),
            Text(s.localAlwaysKept, style: theme.textTheme.labelLarge),
            const Gap(4),
            Text(notifier.localEntries.join('; '), style: theme.textTheme.bodySmall),
            const Gap(20),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              onChanged: commitAfterPause,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: s.yourEntries,
                hintText: '*.example.com; 10.0.0.0/8',
                helperText: s.entryHelper,
                border: const OutlineInputBorder(),
              ),
            ),
            if (state.canApply) ...[
              const Gap(12),
              Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 16, color: theme.colorScheme.primary),
                  const Gap(6),
                  Expanded(
                    child: Text(s.pendingNote, style: theme.textTheme.bodySmall),
                  ),
                  FilledButton(
                    onPressed: notifier.apply,
                    child: Text(s.save),
                  ),
                ],
              ),
            ],
            if (state.hasFailed || state.applyState == SystemProxyBypassApplyState.unsupported) ...[
              const Gap(12),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.outline),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      state.applyState == SystemProxyBypassApplyState.unsupported ? s.unsupportedNote : s.notApplied,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ],
            const Gap(20),
            Text(s.effective, style: theme.textTheme.labelLarge),
            const Gap(4),
            SelectableText(
              // Shown the way the platform stores it, so the value can be
              // compared with the registry on Windows or with
              // `networksetup -getproxybypassdomains` on macOS.
              notifier.effectiveEntries.join(notifier.separator),
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
