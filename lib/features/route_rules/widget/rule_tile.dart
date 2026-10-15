import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/widget/setting_detail_chips.dart';
import 'package:hiddify/features/rule_sets/notifier/rule_sets_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/platform_utils.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';

class RuleTile extends HookConsumerWidget {
  const RuleTile({super.key, required this.index, required this.rule});

  final Rule rule;
  final int index;

  Map detailChipsValue() {
    final map = rule.toProto3Json()! as Map<String, dynamic>;
    map.removeWhere((key, value) => ['list_order', 'enabled', 'name', 'outbound'].contains(key));
    map.updateAll(
      (key, value) => value is List
          ? value.length
          : value is ProtobufEnum
          ? value.name
          : value,
    );
    return map;
  }

  Map<String, String> mergeTranslation(List<Map<String, String>> translations) {
    return Map.fromEntries(translations.expand((map) => map.entries).toList());
  }

  Future handleDelete(BuildContext context, WidgetRef ref) async {
    final t = ref.watch(translationsProvider).requireValue;
    final result = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(
          title: t.dialogs.confirmation.routeRule.delete.title,
          message: t.dialogs.confirmation.routeRule.delete.msg(rulename: rule.name),
          positiveBtnTxt: t.common.delete,
        );
    if (result == true) {
      await ref.read(rulesNotifierProvider.notifier).deleteRule(rule.listOrder);
      // A rule set only has an effect through the rules that reference it, so
      // the ones this deletion orphaned go away with it. Otherwise the market
      // keeps showing them as "already added" while nothing uses them, and they
      // had to be removed a second time from the rule set list.
      final referencedTags = ref.read(rulesNotifierProvider).expand((rule) => rule.ruleSets).toSet();
      final removed = ref.read(ruleSetsProvider.notifier).removeUnreferenced(referencedTags);
      if (removed.isNotEmpty && context.mounted) {
        ref
            .read(inAppNotificationControllerProvider)
            .showInfoToast(
              t.pages.settings.routing.ruleSets.msg.removedUnreferenced(tags: removed.join(', ')),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final scrollController = useScrollController();
    ref.listen(rulesNotifierProvider, (_, _) {
      if (scrollController.offset > 0) scrollController.jumpTo(0);
    });
    return Material(
      child: InkWell(
        onTap: () {
          context.goNamed('rule', pathParameters: {'orderId': rule.listOrder.toString()});
        },
        onLongPress: () async => await handleDelete(context, ref),
        onSecondaryTapUp: PlatformUtils.isDesktop
            ? (details) {
                final offset = details.globalPosition;
                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx, offset.dy),
                  items: [
                    PopupMenuItem(
                      child: Text(t.pages.settings.routing.routeRule.delete),
                      onTap: () async => await handleDelete(context, ref),
                    ),
                  ],
                );
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(
                t.pages.settings.routing.routeRule.rule.outbound[rule.outbound.name] ?? rule.outbound.name,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              subtitle: Text(rule.name, style: Theme.of(context).textTheme.bodyLarge),
              leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle_rounded)),
              trailing: Switch(
                value: rule.enabled,
                onChanged: (value) async =>
                    await ref.read(rulesNotifierProvider.notifier).updateEnabled(value, rule.listOrder),
              ),
            ),
            SettingDetailChips<MapEntry>(
              values: detailChipsValue().entries.toList(),
              scrollController: scrollController,
              t: mergeTranslation([
                t.pages.settings.routing.routeRule.rule.tileTitle,
                t.pages.settings.routing.routeRule.rule.network,
                t.pages.settings.routing.routeRule.rule.outbound,
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
