import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/common/print.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

const _database = 'database.sqlite';

const _skipped = {'config.yaml', 'logs', '.DS_Store'};

/// A macOS pre-release starts from a read-only copy of the stable app's data.
Future<void> importStableDataForPre() async {
  if (!Platform.isMacOS) {
    return;
  }
  final home = await appPath.homeDirPath;
  final domain = basename(home);
  if (domain != '$packageName.pre') {
    return;
  }
  try {
    await copyStableData(
      stableHome: join(dirname(home), packageName),
      home: home,
      hasOwnConfig: () async =>
          await _defaults(['read', domain, 'flutter.$configKey']) == 0,
      copyDefaults: () => _copyDefaults(from: packageName, to: domain),
    );
  } catch (error) {
    commonPrint.log('stable data not copied: $error');
  }
}

/// The database goes last, so a copy cut short is redone on the next launch.
@visibleForTesting
Future<bool> copyStableData({
  required String stableHome,
  required String home,
  required Future<bool> Function() hasOwnConfig,
  required Future<void> Function() copyDefaults,
}) async {
  if (equals(stableHome, home) ||
      await File(join(home, _database)).exists() ||
      await hasOwnConfig()) {
    return false;
  }
  final stableDatabase = File(join(stableHome, _database));
  if (!await stableDatabase.exists()) {
    return false;
  }
  await copyDefaults();
  await for (final entity in Directory(stableHome).list(followLinks: false)) {
    final name = basename(entity.path);
    if (_skipped.contains(name) ||
        name.endsWith('.lock') ||
        name.startsWith(_database)) {
      continue;
    }
    await _copy(entity, join(home, name));
  }
  final wal = File('${stableDatabase.path}-wal');
  if (await wal.exists()) {
    await wal.copy(join(home, '$_database-wal'));
  }
  await stableDatabase.copy(join(home, _database));
  return true;
}

Future<void> _copy(FileSystemEntity entity, String target) async {
  if (entity is File) {
    await Directory(dirname(target)).create(recursive: true);
    await entity.copy(target);
  } else if (entity is Directory) {
    await for (final child in entity.list(followLinks: false)) {
      await _copy(child, join(target, basename(child.path)));
    }
  }
}

Future<void> _copyDefaults({required String from, required String to}) async {
  final temp = await Directory.systemTemp.createTemp('flclashx_defaults');
  try {
    final plist = join(temp.path, 'defaults.plist');
    if (await _defaults(['export', from, plist]) == 0) {
      await _defaults(['import', to, plist]);
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<int> _defaults(List<String> arguments) async {
  try {
    return (await Process.run('/usr/bin/defaults', arguments)).exitCode;
  } catch (_) {
    return -1;
  }
}

/// Android keeps the stable app's data out of a pre-release's reach.
bool preChannelTipDue({
  required bool isAndroid,
  required String packageName,
  required bool hasProfiles,
  required bool shown,
}) => isAndroid && packageName.endsWith('.pre') && !hasProfiles && !shown;
