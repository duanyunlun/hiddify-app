import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/core_update/model/kernel_release.dart';
import 'package:hiddify/features/core_update/notifier/kernel_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lets the user pick a core (kernel) version, download it and stage it, then
/// restart the app so the staged core is applied.
///
/// The swap happens during startup, before the native library is loaded: a
/// loaded library cannot be overwritten on Windows, so a restart is required for
/// a new core to take effect.
class CoreUpdatePage extends HookConsumerWidget {
  const CoreUpdatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final strings = t.pages.settings.coreUpdate;
    final state = ref.watch(kernelUpdateProvider);
    final notifier = ref.read(kernelUpdateProvider.notifier);
    final repoController = useTextEditingController(text: notifier.repository);
    final includePreReleases = useState(true);

    useEffect(() {
      if (state.releases.isEmpty && !state.isLoading) {
        Future.microtask(() => notifier.loadReleases(includePreReleases: includePreReleases.value));
      }
      return null;
    }, const []);

    if (!isKernelReplaceable) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(strings.notSupported, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.title),
        actions: [
          if (state.isLoading)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              tooltip: strings.reload,
              onPressed: () => notifier.loadReleases(includePreReleases: includePreReleases.value),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (state.hasPendingRestart)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.pendingRestart(tag: state.pendingTag!),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: () => _restartApp(context),
                          child: Text(strings.restartNow),
                        ),
                        const Gap(8),
                        TextButton(
                          onPressed: notifier.discardPending,
                          child: Text(strings.discard),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              strings.current(tag: state.currentTag ?? strings.unknown),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              strings.currentNote,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: repoController,
              decoration: InputDecoration(
                labelText: strings.repository,
                helperText: strings.repositoryHelper,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: strings.apply,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () async {
                    await notifier.setRepository(repoController.text);
                    await notifier.loadReleases(includePreReleases: includePreReleases.value);
                  },
                ),
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(strings.includePreReleases),
            value: includePreReleases.value,
            onChanged: (value) {
              includePreReleases.value = value;
              notifier.loadReleases(includePreReleases: value);
            },
          ),
          if (state.isWorking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
          const Divider(height: 24),
          if (!state.isLoading && state.releases.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                strings.empty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ...state.releases.map((release) {
            final isPending = state.pendingTag == release.tag;
            final isCurrent = state.currentTag == release.tag;
            return ListTile(
              leading: Icon(
                release.preRelease ? Icons.science_rounded : Icons.memory_rounded,
                color: release.preRelease ? theme.colorScheme.tertiary : theme.colorScheme.primary,
              ),
              title: Text(release.tag, style: const TextStyle(fontFamily: 'monospace')),
              subtitle: Text(
                '${_formatDate(release.publishedAt)}'
                '${release.asset?.size != null && release.asset!.size > 0 ? ' · ${_formatSize(release.asset!.size)}' : ''}',
              ),
              trailing: isCurrent
                  ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                  : isPending
                  ? Text(strings.pending)
                  : IconButton(
                      tooltip: strings.install,
                      icon: const Icon(Icons.download_rounded),
                      onPressed: state.isWorking ? null : () => _confirmAndInstall(context, ref, release),
                    ),
            );
          }),
        ],
      ),
    );
  }

  /// Confirmation shown before a core is downloaded and staged.
  Future<void> _confirmAndInstall(BuildContext context, WidgetRef ref, KernelRelease release) async {
    final strings = ref.read(translationsProvider).requireValue.pages.settings.coreUpdate;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.confirmTitle(tag: release.tag)),
        content: Text(strings.confirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(strings.cancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(strings.install)),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    final ok = await ref.read(kernelUpdateProvider.notifier).install(release);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? strings.installStaged(tag: release.tag) : strings.installFailed)),
    );
  }

  /// Restarts the application so a staged core is picked up at startup.
  ///
  /// The new process is started before this one exits, so the staged core is
  /// applied by the fresh instance.
  Future<void> _restartApp(BuildContext context) async {
    try {
      if (Platform.isWindows) {
        // `start` detaches the child so it survives this process exiting.
        await Process.start('cmd', ['/c', 'start', '', Platform.resolvedExecutable], mode: ProcessStartMode.detached);
      } else {
        await Process.start(Platform.resolvedExecutable, const [], mode: ProcessStartMode.detached);
      }
      exit(0);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not restart automatically: $e')),
      );
    }
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
