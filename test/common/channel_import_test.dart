import 'dart:io';

import 'package:fl_clash/common/channel_import.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

void main() {
  late Directory root;
  late String stable;
  late String pre;
  late int preferencesCopied;
  late int released;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('channel_import_test');
    stable = join(root.path, 'com.follow.clashx');
    pre = join(root.path, 'com.follow.clashx.pre');
    preferencesCopied = 0;
    released = 0;
    await Directory(join(stable, 'profiles')).create(recursive: true);
    await File(join(stable, 'database.sqlite')).writeAsString('db');
    await File(join(stable, 'database.sqlite-wal')).writeAsString('wal');
    await File(join(stable, 'database.sqlite-journal')).writeAsString('jrnl');
    await File(join(stable, 'database.sqlite-shm')).writeAsString('shm');
    await File(join(stable, 'profiles', '1.yaml')).writeAsString('proxies: []');
    await File(join(stable, 'FlClash.lock')).writeAsString('');
    await File(join(stable, 'config.yaml')).writeAsString('stable paths');
    await Directory(pre).create(recursive: true);
  });

  tearDown(() => root.delete(recursive: true));

  StableSource source({
    bool hasOwnPreferences = false,
    bool busy = false,
    bool failPreferences = false,
  }) => (
    stableHome: stable,
    home: pre,
    hasOwnPreferences: () async => hasOwnPreferences,
    copyPreferences: () async {
      if (failPreferences) {
        throw const ProcessException('defaults', [], 'failed', 1);
      }
      preferencesCopied++;
    },
    lock: () async => busy ? null : () async => released++,
  );

  Map<String, String> snapshot(String dir) => {
    for (final entity in Directory(dir).listSync(recursive: true))
      if (entity is File)
        relative(entity.path, from: dir): entity.readAsStringSync(),
  };

  String read(String name) => File(join(pre, name)).readAsStringSync();

  bool exists(String name) =>
      FileSystemEntity.typeSync(join(pre, name)) !=
      FileSystemEntityType.notFound;

  test('copies the stable data into a fresh pre-release store', () async {
    final before = snapshot(stable);

    expect(await copyStableData(source()), StableImport.imported);

    expect(read('database.sqlite'), 'db');
    expect(read('database.sqlite-wal'), 'wal');
    expect(read('database.sqlite-journal'), 'jrnl');
    expect(exists(join('profiles', '1.yaml')), isTrue);
    for (final left in [
      'database.sqlite-shm',
      'FlClash.lock',
      'config.yaml',
      '.stable-import',
      '.stable-import-pending',
    ]) {
      expect(exists(left), isFalse, reason: left);
    }
    expect(exists('.stable-import-done'), isTrue);
    expect(preferencesCopied, 1);
    expect(released, 1);
    expect(snapshot(stable), before);
  });

  test('a finished import is not taken again', () async {
    await copyStableData(source());
    await File(join(pre, 'database.sqlite')).writeAsString('own');

    expect(await copyStableData(source()), StableImport.skipped);
    expect(read('database.sqlite'), 'own');
  });

  test('leaves a pre-release store that has data of its own', () async {
    await File(join(pre, 'database.sqlite')).writeAsString('own');

    expect(await copyStableData(source()), StableImport.skipped);
    expect(read('database.sqlite'), 'own');
    expect(
      await copyStableData(source(hasOwnPreferences: true)),
      isNot(StableImport.imported),
    );
    expect(preferencesCopied, 0);
  });

  test('waits for the stable app to quit, then replaces the start', () async {
    expect(await copyStableData(source(busy: true)), StableImport.deferred);
    expect(preferencesCopied, 0);
    expect(exists('database.sqlite'), isFalse);

    await File(join(pre, 'database.sqlite')).writeAsString('first run');
    await File(join(pre, 'database.sqlite-shm')).writeAsString('stale');

    expect(await copyStableData(source()), StableImport.imported);
    expect(read('database.sqlite'), 'db');
    expect(exists('database.sqlite-shm'), isFalse);
  });

  test('an import that fails is retried and never marked done', () async {
    await expectLater(
      copyStableData(source(failPreferences: true)),
      throwsA(isA<ProcessException>()),
    );
    expect(released, 1);
    expect(exists('.stable-import-done'), isFalse);
    expect(exists('.stable-import-pending'), isTrue);

    expect(await copyStableData(source()), StableImport.imported);
    expect(read('database.sqlite'), 'db');
  });

  test('copies nothing when the stable app has no data', () async {
    await File(join(stable, 'database.sqlite')).delete();

    expect(await copyStableData(source()), StableImport.skipped);
    expect(Directory(pre).listSync(), isEmpty);
  });

  test('never copies a store onto itself', () async {
    final itself = (
      stableHome: stable,
      home: stable,
      hasOwnPreferences: () async => false,
      copyPreferences: () async => preferencesCopied++,
      lock: () async => () async {},
    );

    expect(await copyStableData(itself), StableImport.skipped);
    expect(preferencesCopied, 0);
  });

  test('the stable lock is taken shared and given back', () async {
    final release = await lockStableHome(stable);

    expect(release, isNotNull);
    await release!();
    final missing = await lockStableHome(join(root.path, 'nowhere'));
    expect(missing, isNotNull);
  });

  test(
    'a stable app holding its lock defers the copy',
    () async {
      final holder = await Process.start('python3', [
        '-c',
        [
          'import fcntl, sys, time',
          'f = open(sys.argv[1], "w")',
          'fcntl.lockf(f, fcntl.LOCK_EX)',
          'print("locked", flush=True)',
          'time.sleep(30)',
        ].join('\n'),
        join(stable, 'FlClash.lock'),
      ]);
      addTearDown(holder.kill);
      await holder.stdout.first;

      expect(await lockStableHome(stable), isNull);
    },
    skip:
        Platform.isWindows ||
        Process.runSync('which', ['python3']).exitCode != 0,
  );

  test('runtime records stay with the stable app', () {
    expect(
      runtimePreferenceKeys,
      containsAll([
        systemDnsRecordKey,
        systemProxyAppliedKey,
        bootRecordKey,
        appliedConfigMd5Key,
      ]),
    );
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
