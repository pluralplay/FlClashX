import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:path/path.dart' as p;

typedef UpdateProgress = void Function(int received, int? total);

const _checksumLimit = 4096;
const _maxRedirects = 5;

class UpdateDownloader {
  final Dio _dio;

  /// Each download gets its own directory under here, removed on failure.
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

  /// Leftovers of an earlier run: a finished download nobody installed, or a
  /// disk image Finder was handed.
  Future<void> purge() async {
    final directory = await root();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> fetchChecksum(
    UpdateAsset asset, {
    CancelToken? cancelToken,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await _receive(
      asset.checksumUrl,
      limit: _checksumLimit,
      cancelToken: cancelToken,
      onChunk: (chunk) async => bytes.add(chunk),
    );
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final hash = parseChecksum(text, asset.name);
    if (hash == null) {
      throw UpdateException(UpdateErrorKind.noChecksum, asset.name);
    }
    return hash;
  }

  Future<File> download(
    UpdateAsset asset, {
    CancelToken? cancelToken,
    UpdateProgress? onProgress,
  }) async {
    final directory = Directory(p.join((await root()).path, _randomName()));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, asset.name));
    RandomAccessFile? output;
    try {
      final opened = output = await file.open(mode: FileMode.writeOnly);
      final received = await _receive(
        asset.url,
        limit: asset.sizeLimit,
        cancelToken: cancelToken,
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
      rethrow;
    }
  }

  Future<int> _receive(
    Uri uri, {
    required int limit,
    required Future<Object?> Function(List<int> chunk) onChunk,
    CancelToken? cancelToken,
    UpdateProgress? onProgress,
    int? total,
  }) async {
    final body = await _open(uri, cancelToken);
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
  Future<ResponseBody> _open(Uri uri, CancelToken? cancelToken) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!isAllowedUpdateUri(current)) {
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
