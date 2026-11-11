import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _resolveSource(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) {
    return direct;
  }
  final inPlugin = File('plugins/tray/$relativePath');
  if (inPlugin.existsSync()) {
    return inPlugin;
  }
  return direct;
}

String _method(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  return source.substring(start, source.indexOf('\n    }\n', start));
}

void _expectInOrder(String body, List<String> parts) {
  var from = 0;
  for (final part in parts) {
    final index = body.indexOf(part, from);
    expect(index, isNonNegative, reason: 'missing or out of order: $part');
    from = index + part.length;
  }
}

void main() {
  test(
    'macOS sends a menu selection only after the menu ends tracking, '
    'so an Exit cannot kill the process mid-tracking and strand the Dock',
    () {
      final source = _resolveSource(
        'macos/tray/Sources/tray/TrayPlugin.swift',
      ).readAsStringSync();

      expect(source, contains('self?.select(id)'));
      expect(source, contains('result(openMenu())'));
      _expectInOrder(_method(source, 'private func openMenu()'), [
        'isMenuOpen = true',
        'statusItem.openMenu(menu)',
        'isMenuOpen = false',
        'menuSelection = nil',
        'sendSelection(id)',
      ]);
      _expectInOrder(_method(source, 'private func select('), [
        'if isMenuOpen {',
        'menuSelection = id',
        '} else {',
        'sendSelection(id)',
      ]);
    },
  );
}
