import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/system_proxy/model/system_proxy_bypass.dart';

void main() {
  group('userSystemProxyBypassEntries', () {
    test('keeps only what the app does not own', () {
      // The value a previous tool left behind: the local ranges it also wrote,
      // plus its own entries.
      const stale =
          'localhost;127.*;10.*;172.16.*;192.168.*.*;<local>;*.steampowered.com;linux.do;*.example.com';
      expect(userSystemProxyBypassEntries(stale), ['*.steampowered.com', 'linux.do', '*.example.com']);
    });

    test('is empty when only local entries are present', () {
      expect(userSystemProxyBypassEntries(systemProxyOverrideValue(const [])), isEmpty);
    });

    test('tolerates a missing or empty value', () {
      expect(userSystemProxyBypassEntries(null), isEmpty);
      expect(userSystemProxyBypassEntries(''), isEmpty);
      expect(userSystemProxyBypassEntries(';;'), isEmpty);
    });

    test('matches local entries regardless of case', () {
      expect(userSystemProxyBypassEntries('LOCALHOST;<Local>'), isEmpty);
    });
  });

  group('composeSystemProxyOverride', () {
    test('always keeps the local entries first', () {
      final composed = composeSystemProxyOverride(['*.example.com']);
      expect(composed.take(kLocalSystemProxyBypass.length), kLocalSystemProxyBypass);
      expect(composed.last, '*.example.com');
    });

    test('drops duplicates', () {
      final composed = composeSystemProxyOverride(['*.example.com', '*.EXAMPLE.com', '10.*']);
      expect(composed.where((entry) => entry.toLowerCase() == '*.example.com'), hasLength(1));
      // '10.*' is already a local entry, so it is not added again.
      expect(composed.where((entry) => entry == '10.*'), hasLength(1));
    });

    test('ignores blank entries', () {
      final composed = composeSystemProxyOverride(['', '   ', '*.example.com']);
      expect(composed.where((entry) => entry.trim().isEmpty), isEmpty);
      expect(composed, contains('*.example.com'));
    });

    test('joins with the separator windows expects', () {
      expect(systemProxyOverrideValue(const []), kLocalSystemProxyBypass.join(';'));
      expect(systemProxyOverrideValue(['*.example.com']), endsWith(';*.example.com'));
    });
  });

  group('parseUserEntryText', () {
    test('splits on semicolons and trims', () {
      expect(parseUserEntryText('*.a.com; 10.0.0.0/8 ;*.b.com'), ['*.a.com', '10.0.0.0/8', '*.b.com']);
    });

    test('accepts the full width semicolon a chinese keyboard produces', () {
      // Rejecting this would look like the app silently dropped the input.
      expect(parseUserEntryText('*.a.com；*.b.com'), ['*.a.com', '*.b.com']);
    });

    test('drops blanks and duplicates', () {
      expect(parseUserEntryText(';*.a.com;; *.A.com ;'), ['*.a.com']);
    });

    test('drops entries with whitespace, which windows cannot store', () {
      expect(parseUserEntryText('*.a.com; two words ;*.b.com'), ['*.a.com', '*.b.com']);
    });

    test('tolerates null and empty input', () {
      expect(parseUserEntryText(null), isEmpty);
      expect(parseUserEntryText(''), isEmpty);
      expect(parseUserEntryText('  ;  '), isEmpty);
    });

    test('round trips through formatUserEntryText', () {
      const entries = ['*.a.com', '10.0.0.0/8'];
      expect(parseUserEntryText(formatUserEntryText(entries)), entries);
    });
  });
}
