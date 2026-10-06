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

    final controller = useTextEditingController(text: formatUserEntryText(state.entries));
    final pending = useRef<Timer?>(null);

    // Writing the registry on every keystroke would be wasteful, and the field
    // must not be reset while it is being typed in, so the value is committed
    // once the typing pauses.
    void commitAfterPause(String value) {
      pending.value?.cancel();
      pending.value = Timer(const Duration(milliseconds: 600), () {
        notifier.setEntries(parseUserEntryText(value));
      });
    }

    useEffect(() {
      return () => pending.value?.cancel();
    }, const []);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.reload,
            icon: const Icon(Icons.sync_rounded),
            onPressed: () {
              pending.value?.cancel();
              notifier.reloadFromSystem();
              controller.text = formatUserEntryText(ref.read(systemProxyBypassProvider).entries);
            },
          ),
          TextButton(
            onPressed: () {
              pending.value?.cancel();
              notifier.clear();
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
            Text(kLocalSystemProxyBypass.join('; '), style: theme.textTheme.bodySmall),
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
            if (!state.applied) ...[
              const Gap(12),
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
            const Gap(20),
            Text(s.effective, style: theme.textTheme.labelLarge),
            const Gap(4),
            SelectableText(
              systemProxyOverrideValue(state.entries),
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
