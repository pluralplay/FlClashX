import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/package.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:path/path.dart' as p;

typedef UpdateProgress = void Function(int received, int? total);

const _checksumLimit = 4096;
const _maxRedirects = 5;
const _partialPrefix = '.partial-';

final _versionSlot = RegExp(
  r'^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$',
);

String updateSlotOf(String tag) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return _versionSlot.hasMatch(version) ? version : _randomName();
}

/// Keeps only releases newer than [currentVersion], minus their partial
/// downloads. A file still open, a running setup, waits for the next start.
Future<void> removeStaleUpdates(
  Directory root, {
  required String currentVersion,
}) async {
  try {
    if (!await _isRealDirectory(root.path)) {
      return;
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || !_isNewer(entity, currentVersion)) {
        await _deleteQuietly(entity);
        continue;
      }
      await for (final inner in entity.list(followLinks: false)) {
        if (p.basename(inner.path).startsWith(_partialPrefix)) {
          await _deleteQuietly(inner);
        }
      }
    }
  } on FileSystemException {
    return;
  }
}

bool _isNewer(Directory slot, String currentVersion) {
  final version = p.basename(slot.path);
  if (!_versionSlot.hasMatch(version)) {
    return false;
  }
  try {
    return compareVersions(version, currentVersion) > 0;
  } on FormatException {
    return false;
  }
}

/// A link is removed, never listed: listing it would walk, and the cleanup
/// delete, whatever it points at.
Future<bool> _isRealDirectory(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    await Link(path).delete();
  }
  return type == FileSystemEntityType.directory;
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: true);
  } on FileSystemException {
    return;
  }
}

class UpdateDownloader {
  final Dio _dio;

  /// Resolved only once a download starts, so showing the dialog never
  /// waits on the cache directory.
  final Future<Directory> Function() root;

  UpdateDownloader({required this.root, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  Future<void> purge({String? keep}) async {
    final directory = await root();
    if (!await _isRealDirectory(directory.path)) {
      return;
    }
    if (keep == null) {
      await directory.delete(recursive: true);
      return;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (p.basename(entity.path) != keep) {
        await _deleteQuietly(entity);
      }
    }
  }

  Future<Directory> _slot(String slot) async {
    final directory = await root();
    await _isRealDirectory(directory.path);
    final path = p.join(directory.path, slot);
    await _isRealDirectory(path);
    return Directory(path);
  }

  Future<File> fileOf(UpdateAsset asset, String slot) async =>
      File(p.join((await _slot(slot)).path, asset.name));

  Future<File> keep(File partial, UpdateAsset asset, String slot) async {
    final target = await fileOf(asset, slot);
    final existing = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    switch (existing) {
      case FileSystemEntityType.notFound:
        break;
      case FileSystemEntityType.directory:
        await Directory(target.path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(target.path).delete();
      default:
        await File(target.path).delete();
    }
    final kept = await partial.rename(target.path);
    await _deleteQuietly(partial.parent);
    return kept;
  }

  Future<String> fetchChecksum(
    UpdateAsset asset, {
    CancelToken? cancelToken,
  }) async {
    if (asset.checksum case final inline?) {
      return inline;
    }
    final bytes = BytesBuilder(copy: false);
    await _receive(
      asset.checksumUrl!,
      limit: _checksumLimit,
      cancelToken: cancelToken,
      hosts: asset.allowedHosts,
      onChunk: (chunk) async => bytes.add(chunk),
    );
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final hash = parseChecksum(text, asset.name);
    if (hash == null) {
      throw UpdateException(UpdateErrorKind.noChecksum, asset.name);
    }
    return hash;
  }

  /// [keep] moves the partial file where a later dialog would reuse it.
  Future<File> download(
    UpdateAsset asset, {
    String? slot,
    CancelToken? cancelToken,
    UpdateProgress? onProgress,
  }) async {
    final parent = await _slot(slot ?? _randomName());
    final directory = Directory(
      p.join(parent.path, '$_partialPrefix${_randomName()}'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, asset.name));
    RandomAccessFile? output;
    try {
      final opened = output = await file.open(mode: FileMode.writeOnly);
      final received = await _receive(
        asset.url,
        limit: asset.sizeLimit,
        cancelToken: cancelToken,
        hosts: asset.allowedHosts,
        onChunk: opened.writeFrom,
        onProgress: onProgress,
        total: asset.size,
      );
      output = null;
      await opened.close();
      if (asset.size != null && received != asset.size) {
        throw UpdateException(
          UpdateErrorKind.incomplete,
          '$received of ${asset.size}',
        );
      }
      return file;
    } catch (_) {
      await output?.close().catchError((_) => output!);
      await directory.delete(recursive: true).catchError((_) => directory);
      await parent.delete().catchError((_) => parent);
      rethrow;
    }
  }

  Future<int> _receive(
    Uri uri, {
    required int limit,
    required Future<Object?> Function(List<int> chunk) onChunk,
    Set<String> hosts = updateHosts,
    CancelToken? cancelToken,
    UpdateProgress? onProgress,
    int? total,
  }) async {
    final body = await _open(uri, cancelToken, hosts);
    final length = int.tryParse(
      body.headers[Headers.contentLengthHeader]?.firstOrNull ?? '',
    );
    if (length != null && length > limit) {
      await _discard(body);
      throw UpdateException(UpdateErrorKind.tooLarge, '$length');
    }
    var received = 0;
    try {
      await for (final chunk in body.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(),
            reason: cancelToken?.cancelError?.error,
          );
        }
        received += chunk.length;
        if (received > limit) {
          throw UpdateException(UpdateErrorKind.tooLarge, '$received');
        }
        await onChunk(chunk);
        onProgress?.call(received, total ?? length);
      }
    } on UpdateException {
      rethrow;
    } on Exception catch (error) {
      if (_cancelled(error, cancelToken)) {
        rethrow;
      }
      throw UpdateException(UpdateErrorKind.network, '$error');
    }
    return received;
  }

  /// Redirects are followed by hand so every hop is checked against the
  /// allowlist, not only the first.
  Future<ResponseBody> _open(
    Uri uri,
    CancelToken? cancelToken,
    Set<String> hosts,
  ) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!isAllowedUpdateUri(current, hosts: hosts)) {
        throw UpdateException(UpdateErrorKind.untrustedHost, '$current');
      }
      final Response<ResponseBody> response;
      try {
        response = await _dio.getUri<ResponseBody>(
          current,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
      } on Exception catch (error) {
        if (_cancelled(error, cancelToken)) {
          rethrow;
        }
        throw UpdateException(UpdateErrorKind.network, '$error');
      }
      final body = response.data!;
      final status = response.statusCode ?? 0;
      if (status == 200) {
        return body;
      }
      await _discard(body);
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (status < 300 || status >= 400 || location == null) {
        throw UpdateException(UpdateErrorKind.network, 'HTTP $status');
      }
      current = current.resolve(location);
    }
    throw const UpdateException(UpdateErrorKind.network, 'too many redirects');
  }

  /// An abort reaches a body already streaming as whatever the socket throws.
  bool _cancelled(Exception error, CancelToken? cancelToken) =>
      (error is DioException && CancelToken.isCancel(error)) ||
      (cancelToken?.isCancelled ?? false);

  Future<void> _discard(ResponseBody body) async {
    await body.stream.listen(null).cancel();
  }
}

String _randomName() {
  final random = Random.secure();
  return List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Hashing a 150 MB package takes long enough to stall frames, so it runs on
/// an isolate of its own.
Future<String> sha256OfFile(String path) => Isolate.run(() async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
});
