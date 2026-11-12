import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/desktop_channel.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/common/print.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

const _database = 'database.sqlite';
const _databaseSidecars = ['-wal', '-journal'];
const _preferences = 'shared_preferences.json';
const _skipped = {'config.yaml', 'logs', '.DS_Store', _preferences};
const _staging = '.stable-import';
const _pendingMarker = '.stable-import-pending';
const _doneMarker = '.stable-import-done';
const _promotedManifest = '.stable-import-promoted';

/// What the stable process did to the system, which a copy must not undo.
const runtimePreferenceKeys = [
  systemDnsRecordKey,
  systemProxyAppliedKey,
  bootRecordKey,
  appliedConfigMd5Key,
];

enum StableImport { imported, skipped, deferred }

typedef StableRelease = Future<void> Function();

typedef StableSource = ({
  String stableHome,
  String home,
  Future<bool> Function() hasOwnPreferences,
  Future<void> Function() copyPreferences,
  Future<void> Function() dropPreferences,
  Future<StableRelease?> Function() lock,
});

/// Deferred also covers an import that failed after it began.
Future<StableImport> importStableDataForPre() async {
  StableSource? source;
  try {
    source = await _macosSource() ?? await _desktopSource();
    if (source == null) {
      return StableImport.skipped;
    }
    return await copyStableData(source);
  } catch (error) {
    commonPrint.log('stable data not copied: $error');
    final home = source?.home;
    return home != null && await File(join(home, _pendingMarker)).exists()
        ? StableImport.deferred
        : StableImport.skipped;
  }
}

Future<void> abandonStableImport() async {
  final source = await _macosSource() ?? await _desktopSource();
  if (source != null) {
    await abandonImport(source);
  }
}

/// A pending import implies the pre-release had no data of its own to keep.
@visibleForTesting
Future<void> abandonImport(StableSource source) async {
  final home = source.home;
  await Directory(home).create(recursive: true);
  final pending = File(join(home, _pendingMarker));
  final manifest = File(join(home, _promotedManifest));
  if (await pending.exists()) {
    final promoted = await manifest.exists()
        ? const LineSplitter().convert(await manifest.readAsString())
        : const <String>[];
    for (final name in {
      ...promoted,
      for (final suffix in ['', ..._databaseSidecars, '-shm'])
        '$_database$suffix',
    }) {
      await _remove(join(home, name));
    }
    await source.dropPreferences();
  }
  await File(join(home, _doneMarker)).writeAsString('');
  if (await pending.exists()) {
    await pending.delete();
  }
  final staging = Directory(join(home, _staging));
  if (await staging.exists()) {
    await staging.delete(recursive: true);
  }
  if (await manifest.exists()) {
    await manifest.delete();
  }
}

Future<void> settleStableImport({
  required Future<StableImport> Function() import,
  required Future<bool> Function() askRetry,
  required Future<void> Function() abandon,
}) async {
  var deferred = await import() == StableImport.deferred;
  while (deferred) {
    if (await askRetry()) {
      deferred = await import() == StableImport.deferred;
      continue;
    }
    try {
      await abandon();
      return;
    } catch (error) {
      // Asked again rather than imported: the user turned the import down.
      commonPrint.log('stable import not rolled back: $error');
    }
  }
}

Future<StableSource?> _macosSource() async {
  if (!Platform.isMacOS) {
    return null;
  }
  final home = await appPath.homeDirPath;
  final domain = basename(home);
  if (domain != '$packageName.pre') {
    return null;
  }
  final stableHome = join(dirname(home), packageName);
  return (
    stableHome: stableHome,
    home: home,
    hasOwnPreferences: () async =>
        await _defaults(['read', domain, 'flutter.$configKey']) == 0,
    copyPreferences: () => _copyDefaults(from: packageName, to: domain),
    dropPreferences: () => _dropDefaults(domain),
    lock: () => lockStableHome(stableHome),
  );
}

Future<StableSource?> _desktopSource() async {
  if (!isPreDesktopApp) {
    return null;
  }
  final home = await appPath.homeDirPath;
  final stableHome = stableHomeOf(home);
  if (stableHome == null) {
    return null;
  }
  return desktopSource(stableHome: stableHome, home: home);
}

@visibleForTesting
StableSource desktopSource({
  required String stableHome,
  required String home,
}) => (
  stableHome: stableHome,
  home: home,
  hasOwnPreferences: () => File(join(home, _preferences)).exists(),
  copyPreferences: () => copyPreferencesFile(
    from: join(stableHome, _preferences),
    to: join(home, _preferences),
  ),
  dropPreferences: () => _remove(join(home, _preferences)),
  lock: () => lockStableHome(stableHome),
);

@visibleForTesting
String? stableHomeOf(String home) {
  final name = basename(home);
  if (!name.endsWith('.pre')) {
    return null;
  }
  return join(dirname(home), name.substring(0, name.length - '.pre'.length));
}

@visibleForTesting
Future<void> copyPreferencesFile({
  required String from,
  required String to,
}) async {
  final stable = File(from);
  if (!await stable.exists()) {
    return;
  }
  final preferences = Map<String, Object?>.from(
    json.decode(await stable.readAsString()) as Map,
  );
  for (final key in runtimePreferenceKeys) {
    preferences.remove('flutter.$key');
  }
  await File(to).writeAsString(json.encode(preferences));
}

/// A shared hold on the instance lock keeps the stable app from writing.
Future<StableRelease?> lockStableHome(String stableHome) async {
  final lockFile = File(join(stableHome, 'FlClash.lock'));
  if (!await lockFile.exists()) {
    return () async {};
  }
  final access = await lockFile.open();
  try {
    await access.lock(FileLock.shared);
  } catch (_) {
    await access.close();
    return null;
  }
  return access.close;
}

/// Only a completed import is final: one cut short is redone next launch.
@visibleForTesting
Future<StableImport> copyStableData(StableSource source) async {
  final StableSource(:stableHome, :home) = source;
  if (equals(stableHome, home) ||
      await File(join(home, _doneMarker)).exists()) {
    return StableImport.skipped;
  }
  final pending = File(join(home, _pendingMarker));
  if (!await pending.exists() &&
      (await File(join(home, _database)).exists() ||
          await source.hasOwnPreferences())) {
    return StableImport.skipped;
  }
  if (!await File(join(stableHome, _database)).exists()) {
    return await pending.exists()
        ? StableImport.deferred
        : StableImport.skipped;
  }
  await Directory(home).create(recursive: true);
  await pending.writeAsString('');
  final release = await source.lock();
  if (release == null) {
    return StableImport.deferred;
  }
  final staging = Directory(join(home, _staging));
  try {
    await source.copyPreferences();
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await _stage(stableHome, staging.path);
  } finally {
    await release();
  }
  await _moveIn(staging.path, home);
  await File(join(home, _doneMarker)).writeAsString('');
  await pending.delete();
  await staging.delete(recursive: true);
  await File(join(home, _promotedManifest)).delete();
  return StableImport.imported;
}

Future<void> _stage(String stableHome, String staging) async {
  await Directory(staging).create(recursive: true);
  await for (final entity in Directory(stableHome).list(followLinks: false)) {
    final name = basename(entity.path);
    if (_skipped.contains(name) ||
        name.endsWith('.lock') ||
        name.startsWith(_database) ||
        name.startsWith('.stable-import')) {
      continue;
    }
    await _copy(entity, join(staging, name));
  }
  for (final suffix in ['', ..._databaseSidecars]) {
    final file = File(join(stableHome, '$_database$suffix'));
    if (await file.exists()) {
      await file.copy(join(staging, '$_database$suffix'));
    }
  }
}

Future<void> _moveIn(String staging, String home) async {
  final names = await Directory(
    staging,
  ).list(followLinks: false).map((entity) => basename(entity.path)).toList();
  await File(join(home, _promotedManifest)).writeAsString(names.join('\n'));
  await for (final entity in Directory(staging).list(followLinks: false)) {
    final name = basename(entity.path);
    if (!name.startsWith(_database)) {
      await _replace(entity, join(home, name));
    }
  }
  for (final suffix in ['-wal', '-journal', '-shm']) {
    final own = File(join(home, '$_database$suffix'));
    if (await own.exists()) {
      await own.delete();
    }
  }
  for (final suffix in [..._databaseSidecars, '']) {
    final staged = File(join(staging, '$_database$suffix'));
    if (await staged.exists()) {
      await _replace(staged, join(home, '$_database$suffix'));
    }
  }
}

Future<void> _replace(FileSystemEntity entity, String target) async {
  await _remove(target);
  await entity.rename(target);
}

Future<void> _remove(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (type != FileSystemEntityType.notFound) {
    await File(path).delete();
  }
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
    await _mustDefaults(['export', from, plist]);
    for (final key in runtimePreferenceKeys) {
      await _run('/usr/bin/plutil', ['-remove', 'flutter.$key', plist]);
    }
    await _mustDefaults(['import', to, plist]);
  } finally {
    await temp.delete(recursive: true);
  }
}

Future<void> _dropDefaults(String domain) async {
  if (await _defaults(['read', domain]) == 0) {
    await _mustDefaults(['delete', domain]);
  }
}

Future<void> _mustDefaults(List<String> arguments) async {
  final code = await _defaults(arguments);
  if (code != 0) {
    throw ProcessException('defaults', arguments, 'exit code $code', code);
  }
}

Future<int> _defaults(List<String> arguments) =>
    _run('/usr/bin/defaults', arguments);

Future<int> _run(String executable, List<String> arguments) async {
  try {
    return (await Process.run(executable, arguments)).exitCode;
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
