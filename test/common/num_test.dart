import 'dart:math' as math;

import 'package:fl_clash/common/num.dart';
import 'package:test/test.dart';

void main() {
  group('num.fixed', () {
    test('removes trailing zeros', () {
      expect(1.50.fixed(), '1.5');
    });

    test('keeps significant decimals', () {
      expect(1.23.fixed(), '1.23');
    });

    test('removes decimal point when all zeros', () {
      expect(5.00.fixed(), '5');
    });

    test('respects custom decimals', () {
      expect(1.2345.fixed(decimals: 3), '1.234');
    });

    test('handles integers', () {
      expect(42.fixed(), '42');
    });
  });

  group('num.traffic', () {
    test('bytes for small values', () {
      final result = 500.traffic;
      expect(result.value, '500');
      expect(result.unit, 'B');
    });

    test('kilobytes', () {
      final result = 1536.traffic;
      expect(result.value, '1.5');
      expect(result.unit, 'KB');
    });

    test('megabytes', () {
      final result = (1024 * 1024 * 2.5).traffic;
      expect(result.value, '2.5');
      expect(result.unit, 'MB');
    });

    test('gigabytes', () {
      final result = (1024 * 1024 * 1024 * 3.0).traffic;
      expect(result.value, '3');
      expect(result.unit, 'GB');
    });

    test('zero bytes', () {
      final result = 0.traffic;
      expect(result.value, '0');
      expect(result.unit, 'B');
    });
  });

  group('num.quota', () {
    test('keeps hundredths a tenth would round away', () {
      final result = (math.pow(1024, 4) * 14.65).quota;
      expect(result.value, '14.65');
      expect(result.unit, 'TB');
    });

    test('drops trailing zeros', () {
      expect((math.pow(1024, 3) * 14.7).quota.value, '14.7');
      expect((math.pow(1024, 3) * 100).quota.value, '100');
    });
  });

  group('num.shortTraffic', () {
    test('no decimal places', () {
      final result = 1536.shortTraffic;
      expect(result.value, '2');
      expect(result.unit, ' KB');
    });

    test('bytes', () {
      final result = 500.shortTraffic;
      expect(result.value, '500');
      expect(result.unit, ' B');
    });
  });
}
