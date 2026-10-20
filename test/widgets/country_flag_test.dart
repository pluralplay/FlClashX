import 'dart:io';

import 'package:fl_clash/ui/flag.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _flagsDir = 'assets/images/flags';

void main() {
  final files = Directory(_flagsDir)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.svg'))
      .toList();

  test('countryFlagCodes lists exactly the bundled flags', () {
    final bundled = {
      for (final file in files) p.basenameWithoutExtension(file.path),
    };
    expect(countryFlagCodes, bundled);
  });

  test('every bundled flag compiles with flutter_svg', () async {
    for (final file in files) {
      await expectLater(
        SvgStringLoader(file.readAsStringSync()).loadBytes(null),
        completes,
        reason: file.path,
      );
    }
  });

  test('has() matches case-insensitively and rejects unknown codes', () {
    expect(CountryFlag.has('GB'), isTrue);
    expect(CountryFlag.has('gb'), isTrue);
    expect(CountryFlag.has('T1'), isFalse);
    expect(CountryFlag.has(''), isFalse);
    expect(CountryFlag.has(null), isFalse);
  });
}
