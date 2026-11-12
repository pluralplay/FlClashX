import 'package:fl_clash/common/yaml.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merge keys fill what a map leaves unset', () {
    expect(
      loadPlainYaml('base: &base {a: 1, b: 2}\nnode: {<<: *base, b: 3}\n'),
      {
        'base': {'a': 1, 'b': 2},
        'node': {'a': 1, 'b': 3},
      },
    );
  });

  test('aliases that would expand to billions of nodes are refused', () {
    final layers = [
      'a0: &a0 [x, x, x, x, x, x, x, x, x, x]',
      for (var level = 1; level <= 9; level++)
        'a$level: &a$level [${List.filled(10, '*a${level - 1}').join(', ')}]',
    ];

    expect(
      () => loadPlainYaml(layers.join('\n')),
      throwsA(isA<FormatException>()),
    );
  });

  test('a chain of aliases nested past any real config is refused', () {
    final chain = [
      'n0: &n0 [x]',
      for (var level = 1; level <= 600; level++)
        'n$level: &n$level [*n${level - 1}]',
    ];

    expect(
      () => loadPlainYaml(chain.join('\n')),
      throwsA(isA<FormatException>()),
    );
  });

  test('merge keys that only repeat the map before them are bounded too', () {
    final layers = [
      'm0: &m0 {}',
      for (var level = 1; level <= 12; level++)
        'm$level: &m$level {<<: [${List.filled(10, '*m${level - 1}').join(', ')}]}',
    ];

    expect(
      () => loadPlainYaml(layers.join('\n')),
      throwsA(isA<FormatException>()),
    );
  });
}
