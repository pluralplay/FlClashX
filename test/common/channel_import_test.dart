import 'dart:io';

import 'package:fl_clash/common/channel_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

void main() {
  late Directory root;
  late String stable;
  late String pre;
  var defaultsCopied = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('channel_import_test');
    stable = join(root.path, 'com.follow.clashx');
    pre = join(root.path, 'com.follow.clashx.pre');
    defaultsCopied = 0;
    await Directory(join(stable, 'profiles')).create(recursive: true);
    await File(join(stable, 'database.sqlite')).writeAsString('db');
    await File(join(stable, 'database.sqlite-wal')).writeAsString('wal');
    await File(join(stable, 'database.sqlite-shm')).writeAsString('shm');
    await File(join(stable, 'profiles', '1.yaml')).writeAsString('proxies: []');
    await File(join(stable, 'FlClash.lock')).writeAsString('');
    await File(join(stable, 'config.yaml')).writeAsString('stable paths');
    await Directory(pre).create(recursive: true);
  });

  tearDown(() => root.delete(recursive: true));

  Future<bool> copy({bool hasOwnConfig = false}) => copyStableData(
    stableHome: stable,
    home: pre,
    hasOwnConfig: () async => hasOwnConfig,
    copyDefaults: () async => defaultsCopied++,
  );

  Map<String, String> snapshot(String dir) => {
    for (final entity in Directory(dir).listSync(recursive: true))
      if (entity is File)
        relative(entity.path, from: dir): entity.readAsStringSync(),
  };

  test('copies the stable data into a fresh pre-release store', () async {
    final before = snapshot(stable);

    expect(await copy(), isTrue);

    expect(File(join(pre, 'database.sqlite')).readAsStringSync(), 'db');
    expect(File(join(pre, 'database.sqlite-wal')).readAsStringSync(), 'wal');
    expect(File(join(pre, 'profiles', '1.yaml')).existsSync(), isTrue);
    expect(File(join(pre, 'database.sqlite-shm')).existsSync(), isFalse);
    expect(File(join(pre, 'FlClash.lock')).existsSync(), isFalse);
    expect(File(join(pre, 'config.yaml')).existsSync(), isFalse);
    expect(defaultsCopied, 1);
    expect(snapshot(stable), before);
  });

  test('leaves a pre-release store that has data of its own', () async {
    await File(join(pre, 'database.sqlite')).writeAsString('own');

    expect(await copy(), isFalse);
    expect(File(join(pre, 'database.sqlite')).readAsStringSync(), 'own');
    expect(defaultsCopied, 0);
  });

  test('leaves a pre-release whose settings already exist', () async {
    expect(await copy(hasOwnConfig: true), isFalse);
    expect(File(join(pre, 'database.sqlite')).existsSync(), isFalse);
  });

  test('copies nothing when the stable app has no data', () async {
    await File(join(stable, 'database.sqlite')).delete();

    expect(await copy(), isFalse);
    expect(Directory(pre).listSync(), isEmpty);
    expect(defaultsCopied, 0);
  });

  test('never copies a store onto itself', () async {
    expect(
      await copyStableData(
        stableHome: stable,
        home: stable,
        hasOwnConfig: () async => false,
        copyDefaults: () async => defaultsCopied++,
      ),
      isFalse,
    );
    expect(defaultsCopied, 0);
  });

  group('preChannelTipDue', () {
    bool due({
      bool isAndroid = true,
      String packageName = 'com.follow.clashx.pre',
      bool hasProfiles = false,
      bool shown = false,
    }) => preChannelTipDue(
      isAndroid: isAndroid,
      packageName: packageName,
      hasProfiles: hasProfiles,
      shown: shown,
    );

    test('is due once on an Android pre-release without profiles', () {
      expect(due(), isTrue);
      expect(due(shown: true), isFalse);
      expect(due(hasProfiles: true), isFalse);
    });

    test('is never due for the stable or debug app or off Android', () {
      expect(due(packageName: 'com.follow.clashx'), isFalse);
      expect(due(packageName: 'com.follow.clashx.dev'), isFalse);
      expect(due(isAndroid: false), isFalse);
    });
  });
}
