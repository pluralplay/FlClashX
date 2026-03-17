import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

class Protocol {

  factory Protocol() {
    _instance ??= Protocol._internal();
    return _instance!;
  }

  Protocol._internal();
  static Protocol? _instance;

  void register(String scheme) {
    final protocolRegKey = 'Software\\Classes\\$scheme';
    const protocolRegValue = RegistryValue.string(
      'URL Protocol',
      '',
    );
    const protocolCmdRegKey = r'shell\open\command';
    final protocolCmdRegValue = RegistryValue.string(
      '',
      '"${Platform.resolvedExecutable}" "%1"',
    );
    final regKey = Registry.currentUser.createKey(protocolRegKey);
    regKey.createValue(protocolRegValue);
    regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
  }
}

final protocol = Protocol();
