import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show ZLibDecoder;

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

enum BackupFailure { invalid, newerVersion }

final class BackupException implements Exception {
  final BackupFailure failure;

  const BackupException(this.failure);

  @override
  String toString() => 'BackupException(${failure.name})';
}

/// Archive entries mirror the data directory, so an entry name is also the
/// file's path relative to the home directory.
abstract final class BackupEntries {
  static String profile(Object id) => '$profilesDirectoryName/$id.yaml';

  static String script(Object id) => 'scripts/$id.js';

  static String provider(ClashProvider provider) =>
      '$providersDirectoryName/$rulesProviderDirectoryName/${provider.fileName}';

  /// A remote provider's cache belongs to the Core and downloads again.
  static List<String> of({
    required Iterable<int> profileIds,
    required Iterable<int> scriptIds,
    required Iterable<ClashProvider> providers,
  }) {
    return [
      ...profileIds.map(profile),
      ...scriptIds.map(script),
      ...providers.where((item) => !item.isRemote).map(provider),
    ];
  }

  static List<String> ofData(MigrationData data) {
    return of(
      profileIds: data.profiles.map((item) => item.id),
      scriptIds: data.scripts.map((item) => item.id),
      providers: data.clashProviders,
    );
  }

  static String resolve(String root, String entry) {
    return joinAll([root, ...posix.split(entry)]);
  }
}

typedef BackupArchiveRequest = ({
  String archivePath,
  Map<String, Object?> configMap,
  String databaseSnapshotPath,
  String homeDirPath,
  List<String> entries,
});

typedef RestoreArchiveRequest = ({String archivePath, String stagingDirPath});

Future<void> backupTask(BackupArchiveRequest request) {
  return compute(_backupTask, request);
}

Future<void> _backupTask(BackupArchiveRequest request) {
  return writeBackupArchive(
    archivePath: request.archivePath,
    configMap: request.configMap,
    databaseSnapshotPath: request.databaseSnapshotPath,
    homeDirPath: request.homeDirPath,
    entries: request.entries,
  );
}

Future<MigrationData> restoreTask(RestoreArchiveRequest request) {
  return compute(_restoreTask, request);
}

Future<MigrationData> _restoreTask(RestoreArchiveRequest request) {
  return readBackupArchive(
    archivePath: request.archivePath,
    stagingDirPath: request.stagingDirPath,
  );
}

@visibleForTesting
Future<void> writeBackupArchive({
  required String archivePath,
  required Map<String, Object?> configMap,
  required String databaseSnapshotPath,
  required String homeDirPath,
  required Iterable<String> entries,
}) async {
  final encoder = ZipFileEncoder()..create(archivePath);
  try {
    encoder.addArchiveFile(
      ArchiveFile.string(configJsonName, json.encode(configMap)),
    );
    await encoder.addFile(File(databaseSnapshotPath), backupDatabaseName);
    for (final entry in entries) {
      final file = File(BackupEntries.resolve(homeDirPath, entry));
      if (await file.exists()) {
        await encoder.addFile(file, entry);
      }
    }
  } finally {
    await encoder.close();
  }
}

/// Writes nothing outside [stagingDirPath]; the files the result names are left
/// there at their [BackupEntries] paths.
@visibleForTesting
Future<MigrationData> readBackupArchive({
  required String archivePath,
  required String stagingDirPath,
}) async {
  await _extract(archivePath, stagingDirPath);
  final configFile = File(join(stagingDirPath, configJsonName));
  if (!await configFile.exists()) {
    throw const BackupException(BackupFailure.invalid);
  }
  final configMap = _decodeConfig(await configFile.readAsString());
  final version = configMap['version'] ?? 0;
  if (version is! int) {
    throw const BackupException(BackupFailure.invalid);
  }
  if (version > Migration.currentVersion) {
    throw const BackupException(BackupFailure.newerVersion);
  }
  if (version == 0) {
    return migrateLegacyConfig(
      configMap: configMap,
      sourcePath: stagingDirPath,
      targetPath: stagingDirPath,
    );
  }
  final databaseFile = File(join(stagingDirPath, backupDatabaseName));
  if (!await databaseFile.exists()) {
    return MigrationData(configMap: configMap, includesTables: false);
  }
  final schemaVersion = await _readSchemaVersion(databaseFile);
  final database = Database(
    driftDatabase(
      name: basenameWithoutExtension(backupDatabaseName),
      // Left unset, drift asks path_provider for a temp directory, and this
      // isolate has no platform channel to answer it.
      native: DriftNativeOptions(
        databaseDirectory: () async => Directory(stagingDirPath),
        tempDirectoryPath: () async => stagingDirPath,
      ),
    ),
  );
  try {
    if (schemaVersion > database.schemaVersion) {
      throw const BackupException(BackupFailure.newerVersion);
    }
    final results = await Future.wait([
      database.profilesDao.query().get(),
      database.scriptsDao.query().get(),
      (database.select(database.rules)..orderBy([
            (t) => OrderingTerm(expression: t.order, nulls: NullsOrder.last),
          ]))
          .map((item) => item.toRule())
          .get(),
      database
          .select(database.disabledRules)
          .map((item) => item.toDisabledRule())
          .get(),
      (database.select(database.proxyGroups)..orderBy([
            (t) => OrderingTerm(expression: t.order, nulls: NullsOrder.last),
          ]))
          .map((item) => item.toProxyGroup())
          .get(),
      database.clashProvidersDao.query().get(),
      database.customProxiesDao.query().get(),
      database.proxyDialers.readable((row) => row.toProxyDialer()).get(),
      database.iconSetsDao.query().get(),
    ]);
    return MigrationData(
      configMap: configMap,
      profiles: results[0].cast<Profile>(),
      scripts: results[1].cast<Script>(),
      rules: results[2].cast<Rule>(),
      disabledRules: results[3].cast<DisabledRule>(),
      proxyGroups: results[4].cast<ProxyGroup>(),
      clashProviders: results[5].cast<ClashProvider>(),
      customProxies: results[6].cast<CustomProxy>(),
      proxyDialers: results[7].cast<ProxyDialer>(),
      iconSets: results[8].cast<IconSet>(),
    );
  } finally {
    await database.close();
  }
}

/// Far above a profile set with its providers and icons, and far below a full
/// disk: a backup is untrusted, and it is unpacked before anything checks it.
@visibleForTesting
int maxBackupEntryBytes = 256 << 20;

@visibleForTesting
int maxBackupBytes = 1 << 30;

/// The size an archive declares can lie, so what it inflates to is counted.
final class _BoundedOutput extends OutputFileStream {
  _BoundedOutput(String path, this.limit)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int limit;

  void _grow(int count) {
    if (length + count > limit) {
      throw const BackupException(BackupFailure.invalid);
    }
  }

  @override
  void writeByte(int value) {
    _grow(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _grow(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }
}

/// archive inflates a whole entry in memory before it writes any of it, so a
/// deflated entry is fed through zlib a slice at a time and the output bound
/// sees each piece as it comes.
void _unpack(ZipFile file, OutputStream output) {
  final compressed = file.getStream(decompress: false);
  if (file.compressionMethod == CompressionType.none) {
    output.writeStream(compressed);
    return;
  }
  if (file.compressionMethod != CompressionType.deflate) {
    throw const BackupException(BackupFailure.invalid);
  }
  final inflater = io.ZLibDecoder(
    raw: true,
  ).startChunkedConversion(_OutputSink(output));
  while (!compressed.isEOS) {
    final slice = compressed.length < _inflateSlice
        ? compressed.length
        : _inflateSlice;
    inflater.add(compressed.readBytes(slice).toUint8List());
  }
  inflater.close();
}

const _inflateSlice = 64 << 10;

final class _OutputSink implements Sink<List<int>> {
  _OutputSink(this.output);

  final OutputStream output;

  @override
  void add(List<int> data) => output.writeBytes(data);

  @override
  void close() {}
}

Future<int> _crc32Of(String path) async {
  var crc = 0;
  await for (final chunk in File(path).openRead()) {
    crc = getCrc32(chunk, crc);
  }
  return crc;
}

/// archive checks no entry's CRC, and a damaged profile would otherwise
/// replace the good one on restore.
Future<void> _extract(String archivePath, String stagingDirPath) async {
  await Directory(stagingDirPath).create(recursive: true);
  final input = InputFileStream(archivePath);
  try {
    // ZipDecoder inflates a Unix link's whole target to read it, before any
    // bound, so the directory is read here and links, which a backup never
    // holds, are passed over.
    final directory = ZipDirectory();
    try {
      directory.read(input);
    } on Exception {
      throw const BackupException(BackupFailure.invalid);
    }
    var remaining = maxBackupBytes;
    final seen = <String>{};
    for (final header in directory.fileHeaders) {
      final file = header.file;
      final name = file?.filename ?? '';
      if (file == null ||
          name.endsWith('/') ||
          name.endsWith('\\') ||
          _isUnixLink(header) ||
          !seen.add(name)) {
        continue;
      }
      final outPath = _stagedEntryPath(stagingDirPath, name);
      if (outPath == null) {
        continue;
      }
      final limit = remaining < maxBackupEntryBytes
          ? remaining
          : maxBackupEntryBytes;
      final size = file.uncompressedSize;
      if (size > limit) {
        throw const BackupException(BackupFailure.invalid);
      }
      await Directory(dirname(outPath)).create(recursive: true);
      final output = _BoundedOutput(outPath, limit);
      try {
        _unpack(file, output);
      } on BackupException {
        rethrow;
      } on Exception {
        throw const BackupException(BackupFailure.invalid);
      } finally {
        await output.close();
      }
      remaining -= output.length;
      if (output.length != size || await _crc32Of(outPath) != file.crc32) {
        throw const BackupException(BackupFailure.invalid);
      }
    }
  } finally {
    await input.close();
  }
}

bool _isUnixLink(ZipFileHeader header) =>
    header.versionMadeBy >> 8 == 3 &&
    (header.externalFileAttributes >> 16) & 0xf000 == 0xa000;

/// `posix.normalize` collapses `a/../b`, but a name that starts with `../`
/// normalizes to itself and an absolute one stays absolute, so either would
/// write wherever the archive asks. A backup file is untrusted input.
String? _stagedEntryPath(String stagingDirPath, String name) {
  final normalized = posix.normalize(name.replaceAll('\\', '/'));
  if (normalized.isEmpty ||
      posix.isAbsolute(normalized) ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    return null;
  }
  final outPath = normalize(BackupEntries.resolve(stagingDirPath, normalized));
  if (!isWithin(stagingDirPath, outPath)) {
    return null;
  }
  return outPath;
}

Map<String, Object?> _decodeConfig(String source) {
  final Object? decoded;
  try {
    decoded = json.decode(source);
  } on FormatException {
    throw const BackupException(BackupFailure.invalid);
  }
  if (decoded is! Map<String, Object?>) {
    throw const BackupException(BackupFailure.invalid);
  }
  return decoded;
}

/// Opening the database through drift would already run its migrations, so the
/// version is read from the file header: SQLite keeps `user_version` as a
/// big-endian integer at byte 60.
Future<int> _readSchemaVersion(File databaseFile) async {
  final handle = await databaseFile.open();
  try {
    final header = await handle.read(64);
    if (header.length < 64) {
      throw const BackupException(BackupFailure.invalid);
    }
    return ByteData.sublistView(header).getInt32(60);
  } finally {
    await handle.close();
  }
}
