import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/rule_sets/overview/rule_sets_page.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A rule set only routes anything through the rules that reference it, so the
/// list has to make that relationship visible. These tests pin the two states:
/// referenced by a rule (show the rule and its outbound) and referenced by
/// nothing (say so, and offer to create the rule).
class _RulesWithReference extends RulesNotifier {
  @override
  List<Rule> build() => [
    Rule(name: 'geosite-test', outbound: Outbound.direct, ruleSets: ['geosite-test']),
  ];
}

class _RulesWithoutReference extends RulesNotifier {
  @override
  List<Rule> build() => [Rule(name: 'unrelated', outbound: Outbound.proxy)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> pageWith({required bool referenced}) async {
    SharedPreferences.setMockInitialValues({
      'custom-rule-sets': jsonEncode([
        {
          'tag': 'geosite-test',
          'url': 'https://example.com/test.srs',
          'type': 'remote',
          'format': 'binary',
          'update_interval': '120h',
          'enabled': true,
        },
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    // Resolve the translation up front and hand it over synchronously: the page
    // reads `requireValue`, so a pending AsyncLoading would throw instead of
    // rendering.
    final translations = await AppLocale.en.build();
    return ProviderScope(
      overrides: [
        translationsProvider.overrideWith((ref) => translations),
        // Returning the value directly keeps the state synchronous, which the
        // rule set notifier needs: it reads `requireValue` in its constructor.
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        rulesNotifierProvider.overrideWith(referenced ? _RulesWithReference.new : _RulesWithoutReference.new),
      ],
      child: const MaterialApp(home: RuleSetsPage()),
    );
  }

  testWidgets('shows the referencing rule and its outbound', (tester) async {
    await tester.pumpWidget(await pageWith(referenced: true));
    await tester.pumpAndSettle();

    expect(find.text('geosite-test'), findsOneWidget);
    // The chip names the effective outbound so the list answers "what does this
    // rule set do".
    expect(find.text('routing rule · Direct'), findsOneWidget);
    expect(find.text('No routing rule references it yet, so it has no effect'), findsNothing);
  });

  testWidgets('warns when no rule references the rule set', (tester) async {
    await tester.pumpWidget(await pageWith(referenced: false));
    await tester.pumpAndSettle();

    expect(find.text('No routing rule references it yet, so it has no effect'), findsOneWidget);
    expect(find.text('Create rule'), findsOneWidget);
    // A rule exists, but not for this tag.
    expect(find.text('routing rule · Proxy'), findsNothing);
  });

  testWidgets('renders the tile without throwing', (tester) async {
    // The tile is a Column inside a ListView item. That combination is fine in
    // Flutter (RenderFlex falls back to its children's extent when the height
    // constraint is unbounded), but it is worth a plain render check so a future
    // change to the tile cannot turn into an exception at runtime.
    await tester.pumpWidget(await pageWith(referenced: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
