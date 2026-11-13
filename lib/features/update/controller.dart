import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/download.dart';
import 'package:fl_clash/features/update/platform.dart';
import 'package:flutter/foundation.dart';

const _progressStep = 128 * 1024;

enum UpdatePhase {
  idle,
  downloading,
  verifying,
  ready,
  installing,
  done,
  failed,
}

@immutable
class UpdateState {
  final UpdatePhase phase;
  final int received;
  final int? total;
  final UpdateException? error;
  final UpdateInstallResult? result;

  const UpdateState(
    this.phase, {
    this.received = 0,
    this.total,
    this.error,
    this.result,
  });

  bool get isWorking => switch (phase) {
    UpdatePhase.downloading ||
    UpdatePhase.verifying ||
    UpdatePhase.installing => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is UpdateState &&
      other.phase == phase &&
      other.received == received &&
      other.total == total &&
      other.error?.kind == error?.kind &&
      other.error?.detail == error?.detail &&
      other.result == result;

  @override
  int get hashCode =>
      Object.hash(phase, received, total, error?.kind, error?.detail, result);
}

/// Downloads, verifies and installs one release. Each run is tagged, so a
/// cancelled or superseded run that finishes late never writes its outcome,
/// and every file a run leaves without reaching [UpdatePhase.ready] is
/// removed in its `finally`.
class UpdateController extends ValueNotifier<UpdateState> {
  final Map<String, dynamic> release;
  final UpdatePlatform platform;
  final UpdateDownloader downloader;
  final String repository;
  final bool pre;

  /// Why installing has to wait right now, or null when it may go ahead.
  final UpdateErrorKind? Function() installBlocker;
  final Future<String> Function(String path) hash;

  UpdateController({
    required this.release,
    required this.platform,
    required this.downloader,
    required this.repository,
    required this.pre,
    required this.installBlocker,
    this.hash = sha256OfFile,
  }) : super(const UpdateState(UpdatePhase.idle));

  int _run = 0;
  CancelToken? _cancelToken;
  File? _file;
  String? _expected;
  bool _disposed = false;

  bool get canDownload => platform.target.downloads;

  Future<void> download() async {
    if (value.isWorking || _disposed) {
      return;
    }
    final run = ++_run;
    final cancelToken = _cancelToken = CancelToken();
    value = const UpdateState(UpdatePhase.downloading);
    File? file;
    var reported = 0;
    try {
      await _discard();
      final asset = selectUpdateAsset(
        release,
        platform.target,
        repository: repository,
        pre: pre,
      );
      await downloader.purge();
      final expected = await downloader.fetchChecksum(
        asset,
        cancelToken: cancelToken,
      );
      file = await downloader.download(
        asset,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (run != _run ||
              (received - reported < _progressStep && received != total)) {
            return;
          }
          reported = received;
          value = UpdateState(
            UpdatePhase.downloading,
            received: received,
            total: total,
          );
        },
      );
      _ensureCurrent(run);
      value = const UpdateState(UpdatePhase.verifying);
      if (await hash(file.path) != expected) {
        throw UpdateException(UpdateErrorKind.checksumMismatch, asset.name);
      }
      _ensureCurrent(run);
      await platform.verify(file);
      _ensureCurrent(run);
      _file = file;
      _expected = expected;
      file = null;
      value = const UpdateState(UpdatePhase.ready);
    } on UpdateException catch (error) {
      if (run == _run) {
        value = UpdateState(UpdatePhase.failed, error: error);
      }
    } catch (error) {
      if (run == _run && !cancelToken.isCancelled) {
        final kind = value.phase == UpdatePhase.verifying
            ? UpdateErrorKind.identityMismatch
            : UpdateErrorKind.network;
        value = UpdateState(
          UpdatePhase.failed,
          error: UpdateException(kind, '$error'),
        );
      }
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
      if (file != null) {
        await _deleteDownload(file);
      }
    }
  }

  void cancel() {
    _run++;
    _cancelToken?.cancel();
    _cancelToken = null;
    if (!_disposed) {
      value = const UpdateState(UpdatePhase.idle);
    }
  }

  Future<void> install() async {
    final file = _file;
    if (file == null || value.phase != UpdatePhase.ready || _disposed) {
      return;
    }
    final blocker = installBlocker();
    if (blocker != null) {
      value = UpdateState(UpdatePhase.ready, error: UpdateException(blocker));
      return;
    }
    final run = ++_run;
    value = const UpdateState(UpdatePhase.installing);
    try {
      await _verifyAgain(file);
      _ensureCurrent(run);
      final result = await platform.install(file);
      if (run == _run && !_disposed) {
        value = UpdateState(UpdatePhase.done, result: result);
      }
    } on UpdateException catch (error) {
      if (error.kind == UpdateErrorKind.checksumMismatch ||
          error.kind == UpdateErrorKind.identityMismatch) {
        await _discard();
        if (run == _run && !_disposed) {
          value = UpdateState(UpdatePhase.failed, error: error);
        }
        return;
      }
      _readyAgain(run, error);
    } catch (error) {
      _readyAgain(
        run,
        UpdateException(UpdateErrorKind.installFailed, '$error'),
      );
    }
  }

  /// The Android installer answers after [install] returned; a user who backs
  /// out of its prompt is not shown an error.
  void onInstallStatus(String status, String? message) {
    if (_disposed || _file == null) {
      return;
    }
    _run++;
    value = status == 'aborted'
        ? const UpdateState(UpdatePhase.ready)
        : UpdateState(
            UpdatePhase.ready,
            error: UpdateException(UpdateErrorKind.installFailed, message),
          );
  }

  /// Re-checks the download, user-writable while the dialog waited.
  Future<void> _verifyAgain(File file) async {
    final name = file.uri.pathSegments.last;
    if (await FileSystemEntity.isLink(file.path) ||
        await hash(file.path) != _expected) {
      throw UpdateException(UpdateErrorKind.checksumMismatch, name);
    }
    try {
      await platform.verify(file);
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException(UpdateErrorKind.identityMismatch, '$error');
    }
  }

  void _readyAgain(int run, UpdateException error) {
    if (run == _run && !_disposed) {
      value = UpdateState(UpdatePhase.ready, error: error);
    }
  }

  void _ensureCurrent(int run) {
    if (run != _run) {
      throw const _Superseded();
    }
  }

  Future<void> _discard() async {
    final file = _file;
    _file = null;
    _expected = null;
    if (file != null) {
      await _deleteDownload(file);
    }
  }

  /// A file someone else now opens — a setup, a package, a disk image in
  /// Finder — has to outlive the dialog; the next download purges it.
  @override
  void dispose() {
    _disposed = true;
    _run++;
    _cancelToken?.cancel();
    if (value.phase != UpdatePhase.done) {
      unawaited(_discard());
    }
    super.dispose();
  }
}

final class _Superseded implements Exception {
  const _Superseded();
}

Future<void> _deleteDownload(File file) async {
  try {
    await file.parent.delete(recursive: true);
  } on FileSystemException {
    return;
  }
}
