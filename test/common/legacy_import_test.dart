import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/legacy_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

void main() {
  late Directory root;
  late String legacyHome;
  late String home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('legacy_import_test');
    legacyHome = join(root.path, 'com.follow.clash');
    home = join(root.path, 'com.follow.clashx');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, Object?> flClashX04() => {
    'proxiesStyle': {'cardType': 'oneline'},
    'appSetting': {'overrideProviderSettings': false},
    'profiles': [
      {'id': '1720000000000'},
    ],
  };

  Future<String?> Function(String) keys(Map<String, Object?> values) =>
      (key) async => values[key] == null ? null : json.encode(values[key]);

  void writeLegacyProfile(String name, String content) {
    File(join(legacyHome, profilesDirectoryName, name))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('copies a FlClashX 0.4 install and keeps its files in place', () async {
    writeLegacyProfile('1720000000000.yaml', 'proxies: []');
    writeLegacyProfile('notes.txt', 'skip');

    final imported = await importLegacyConfig(
      readKey: keys({
        configKey: flClashX04(),
        clashConfigKey: {'mixed-port': 1080},
      }),
      legacyHome: legacyHome,
      home: home,
    );

    expect(imported?.config['proxiesStyle'], isNotNull);
    expect(imported?.clashConfig, {'mixed-port': 1080});
    expect(
      File(
        join(home, profilesDirectoryName, '1720000000000.yaml'),
      ).readAsStringSync(),
      'proxies: []',
    );
    expect(
      File(join(home, profilesDirectoryName, 'notes.txt')).existsSync(),
      isFalse,
    );
    expect(
      File(
        join(legacyHome, profilesDirectoryName, '1720000000000.yaml'),
      ).existsSync(),
      isTrue,
    );
  });

  test('leaves an upstream FlClash config alone', () async {
    writeLegacyProfile('1.yaml', 'proxies: []');

    final imported = await importLegacyConfig(
      readKey: keys({
        configKey: {
          'proxiesStyle': {'cardType': 'shrink'},
          'appSetting': {'autoLaunch': true},
        },
      }),
      legacyHome: legacyHome,
      home: home,
    );

    expect(imported, isNull);
    expect(Directory(home).existsSync(), isFalse);
  });

  test('imports nothing without a saved config or from its own home', () async {
    expect(
      await importLegacyConfig(
        readKey: keys({}),
        legacyHome: legacyHome,
        home: home,
      ),
      isNull,
    );
    expect(
      await importLegacyConfig(
        readKey: keys({configKey: flClashX04()}),
        legacyHome: home,
        home: home,
      ),
      isNull,
    );
  });

  test('does not overwrite a profile file already in the new home', () async {
    writeLegacyProfile('1720000000000.yaml', 'old');
    File(join(home, profilesDirectoryName, '1720000000000.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('new');

    await importLegacyConfig(
      readKey: keys({configKey: flClashX04()}),
      legacyHome: legacyHome,
      home: home,
    );

    expect(
      File(
        join(home, profilesDirectoryName, '1720000000000.yaml'),
      ).readAsStringSync(),
      'new',
    );
  });
}
