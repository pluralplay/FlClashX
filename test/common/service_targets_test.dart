import 'dart:io';

import 'package:fl_clash/common/service_probe.dart';
import 'package:test/test.dart';

void main() {
  test('every service has an icon and a checker in the core', () {
    final checkers = RegExp(r'\{name: "([a-z-]+)"')
        .allMatches(File('core/service_check.go').readAsStringSync())
        .map((match) => match.group(1))
        .toSet();
    for (final target in ServiceTarget.values) {
      expect(
        File('assets/images/services/${target.icon}.svg').existsSync(),
        isTrue,
        reason: '${target.id} has no icon',
      );
      expect(checkers, contains(target.id));
    }
  });
}
