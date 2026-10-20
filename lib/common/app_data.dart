import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:path/path.dart';

Future<void> clearAppData() async {
  await preferences.clearPreferences();
  try {
    await database.close();
  } catch (error) {
    // Drift rethrows a failed open from close; that file still has to go.
    commonPrint.log(
      'close database failed: $error',
      logLevel: LogLevel.warning,
    );
  }
  await File(await appPath.databasePath).safeDelete(recursive: true);
  await Directory(await appPath.profilesPath).safeDelete(recursive: true);
}

/// [clearAppData] plus the rest of the app home, bar the lock this process holds.
Future<void> resetAppData() async {
  await clearAppData();
  await fileLogger.dispose();
  final home = Directory(await appPath.homeDirPath);
  final lockPath = await appPath.lockFilePath;
  if (!await home.exists()) {
    return;
  }
  await for (final entity in home.list(followLinks: false)) {
    if (entity.path == lockPath) {
      continue;
    }
    try {
      await entity.delete(recursive: true);
    } on FileSystemException catch (error) {
      commonPrint.log(
        'reset left ${basename(entity.path)}: ${error.message}',
        logLevel: LogLevel.warning,
      );
    }
  }
}
