import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/validators.dart';

void main() {
  group('isDomainSuffix', () {
    test('accepts single label (TLD) suffixes', () {
      expect(isDomainSuffix('.com'), isTrue);
      expect(isDomainSuffix('.ir'), isTrue);
      expect(isDomainSuffix('.xn--fiqs8s'), isTrue);
    });

    test('accepts multi label suffixes', () {
      // Regression: the field rejected every real domain suffix because the
      // pattern only allowed `.<single label>`.
      expect(isDomainSuffix('.onedrive.com'), isTrue);
      expect(isDomainSuffix('.steamcontent.com'), isTrue);
      expect(isDomainSuffix('.co.uk'), isTrue);
      expect(isDomainSuffix('.1drv.com'), isTrue);
      expect(isDomainSuffix('.microsoftpersonalcontent.com'), isTrue);
    });

    test('accepts the spellings users actually type', () {
      expect(isDomainSuffix('onedrive.com'), isTrue);
      expect(isDomainSuffix('*.onedrive.com'), isTrue);
      expect(isDomainSuffix('a-b.example.com'), isTrue);
    });

    test('rejects malformed values', () {
      expect(isDomainSuffix(''), isFalse);
      expect(isDomainSuffix('.'), isFalse);
      expect(isDomainSuffix('..com'), isFalse);
      expect(isDomainSuffix('onedrive..com'), isFalse);
      expect(isDomainSuffix('*onedrive.com'), isFalse);
      expect(isDomainSuffix('*.com.'), isFalse);
      expect(isDomainSuffix('onedrive.com/path'), isFalse);
    });
  });

  group('isDomain', () {
    test('still behaves as before', () {
      expect(isDomain('onedrive.live.com'), isTrue);
      expect(isDomain('skyapi.onedrive.live.com'), isTrue);
      expect(isDomain('localhost'), isFalse);
      expect(isDomain('.onedrive.com'), isFalse);
    });
  });
}
