import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Asks whether a routing rule should be created for a rule set that was just
/// added, and creates it when the user agrees.
///
/// A rule set only *defines* a list; nothing is routed until a rule references
/// its tag. Adding a rule set from the catalog almost always means "send this
/// category somewhere", so offer both steps at once instead of leaving the user
/// with a rule set that silently does nothing.
Future<void> offerRouteRuleForRuleSet(
  BuildContext context,
  WidgetRef ref, {
  required String tag,
}) async {
  final t = ref.read(translationsProvider).requireValue;
  final strings = t.pages.settings.routing.ruleSets.routeRuleOffer;
  final outboundLabels = t.pages.settings.routing.routeRule.rule.outbound;

  var outbound = Outbound.direct;

  final shouldCreate = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(strings.title(tag: tag)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.message, style: Theme.of(context).textTheme.bodySmall),
              const Gap(16),
              Text(strings.outbound, style: Theme.of(context).textTheme.labelLarge),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in Outbound.values)
                    ChoiceChip(
                      label: Text(outboundLabels[option.name] ?? option.name),
                      selected: outbound == option,
                      onSelected: (_) => setState(() => outbound = option),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.skip),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.create),
          ),
        ],
      ),
    ),
  );

  if (shouldCreate != true) return;

  await ref.read(rulesNotifierProvider.notifier).addRule(
    Rule(name: tag, outbound: outbound, ruleSets: [tag]),
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(strings.created(tag: tag))),
  );
}
