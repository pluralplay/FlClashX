import 'dart:io';

import 'package:test/test.dart';

final _ink = RegExp(r'\b(?:InkWell|InkResponse)\(');

/// The arguments of the call opening at [start], up to its closing paren.
String _arguments(String source, int start) {
  var depth = 1;
  var end = start;
  while (depth > 0 && end < source.length) {
    switch (source[end]) {
      case '(':
        depth++;
      case ')':
        depth--;
    }
    end++;
  }
  return source.substring(start, end);
}

void main() {
  test('every InkWell and InkResponse passes the clickable cursor', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.contains('/generated/'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in _ink.allMatches(source)) {
        if (!_arguments(source, match.end).contains('mouseCursor:')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'InkWell has no theme slot for its cursor, so each one passes '
          'clickableCursor from lib/ui/cursor.dart (or a cursor of its own):\n'
          '${offenders.join('\n')}',
    );
  });

  test('nothing falls back to the arrow of adaptiveClickable', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('adaptiveClickable'))
        .map((file) => file.path)
        .toList();
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
