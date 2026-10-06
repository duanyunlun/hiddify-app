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

  group('validateSystemProxyBypassEntry', () {
    test('accepts ordinary patterns', () {
      for (final entry in ['*.example.com', '10.0.0.0/8', 'example.org', '192.168.1.5']) {
        expect(validateSystemProxyBypassEntry(entry), isNull, reason: entry);
      }
    });

    test('rejects what windows cannot store', () {
      expect(validateSystemProxyBypassEntry(''), 'empty');
      expect(validateSystemProxyBypassEntry('   '), 'empty');
      // A semicolon is the separator, so it would silently become two entries.
      expect(validateSystemProxyBypassEntry('a.com;b.com'), 'separator');
      expect(validateSystemProxyBypassEntry('a b.com'), 'whitespace');
    });
  });
}
