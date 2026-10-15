import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/rule_sets/model/rule_set.dart';
import 'package:hiddify/features/rule_sets/notifier/rule_sets_notifier.dart';

void main() {
  RuleSetEntry entry(String tag) => RuleSetEntry(tag: tag, url: 'https://example.com/$tag.srs');

  group('RuleSetsNotifier.unreferencedTags', () {
    test('keeps rule sets that a rule still references', () {
      expect(
        RuleSetsNotifier.unreferencedTags(
          ruleSets: [entry('geosite-github'), entry('geosite-steam')],
          referencedTags: {'geosite-github', 'geosite-steam'},
        ),
        isEmpty,
      );
    });

    test('reports the ones left behind when a rule is deleted', () {
      // Regression: deleting the last rule that referenced a rule set used to
      // leave the entry in the config, so the market still showed it as
      // "already added" and it had to be deleted a second time by hand.
      expect(
        RuleSetsNotifier.unreferencedTags(
          ruleSets: [entry('geosite-github'), entry('geosite-steam'), entry('geosite-cn')],
          referencedTags: {'geosite-steam'},
        ),
        ['geosite-github', 'geosite-cn'],
      );
    });

    test('reports everything when no rule references any rule set', () {
      expect(
        RuleSetsNotifier.unreferencedTags(ruleSets: [entry('geosite-github')], referencedTags: const {}),
        ['geosite-github'],
      );
    });

    test('references to built in tags do not protect custom rule sets', () {
      expect(
        RuleSetsNotifier.unreferencedTags(
          ruleSets: [entry('geosite-github')],
          referencedTags: {'geosite-cn', 'geoip-cn'},
        ),
        ['geosite-github'],
      );
    });

    test('is empty when nothing was added', () {
      expect(RuleSetsNotifier.unreferencedTags(ruleSets: const [], referencedTags: const {'x'}), isEmpty);
    });

    test('references to a rule set that is not part of the list are ignored', () {
      expect(
        RuleSetsNotifier.unreferencedTags(ruleSets: [entry('a')], referencedTags: {'a', 'not-added'}),
        isEmpty,
      );
    });
  });
}
