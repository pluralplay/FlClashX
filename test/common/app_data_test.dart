import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fl_clash/common/app_data.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

import '../helpers/app_paths.dart';
import '../helpers/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUpAll(() async {
    home = Directory.systemTemp.createTempSync('flclash-app-data-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('clears what a startup failure left behind without the Core', () async {
    await mockPreferences();
    await preferences.setVersion(7);
    final databaseFile = File(await appPath.databasePath)
      ..writeAsStringSync('not a database');
    final profilesDir = Directory(join(await appPath.profilesPath, '1'))
      ..createSync(recursive: true);
    final broken = db.Database(
      LazyDatabase(() async => throw const FileSystemException('corrupt')),
    );
    final previous = db.database;
    db.database = broken;
    addTearDown(() => db.database = previous);
    await expectLater(broken.profilesDao.query().get(), throwsA(anything));

    await clearAppData();

    expect(await preferences.getVersion(), 0);
    expect(
      databaseFile.existsSync(),
      isFalse,
      reason:
          'a database that failed to open rethrows from close, and it is '
          'the file most likely to be why startup failed',
    );
    expect(profilesDir.parent.existsSync(), isFalse);
  });

  test(
    'a reset empties the home directory but keeps the instance lock',
    () async {
      await mockPreferences();
      final homePath = await appPath.homeDirPath;
      final lock = File(await appPath.lockFilePath)..writeAsStringSync('pid');
      final config = File(join(homePath, 'config.yaml'))
        ..writeAsStringSync('a');
      final logs = Directory(join(homePath, 'logs'))
        ..createSync(recursive: true);
      File(join(logs.path, 'FlClashX_2026-10-20.log')).writeAsStringSync('log');
      final previous = db.database;
      db.database = db.Database(
        LazyDatabase(() async => throw const FileSystemException('corrupt')),
      );
      addTearDown(() => db.database = previous);

      await resetAppData();

      expect(lock.existsSync(), isTrue);
      expect(config.existsSync(), isFalse);
      expect(logs.existsSync(), isFalse);
    },
  );
}
