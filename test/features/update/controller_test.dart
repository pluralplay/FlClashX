import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/controller.dart';
import 'package:fl_clash/features/update/download.dart';
import 'package:fl_clash/features/update/platform.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = 'FlClashX-macos-arm64.dmg';
const _url = 'https://github.com/pluralplay/FlClashX/releases/download/v0.5.1';
final _payload = Uint8List.fromList(List.generate(4096, (i) => i % 256));

class _Adapter implements HttpClientAdapter {
  String checksum = sha256.convert(_payload).toString();
  Stream<Uint8List>? body;
  var downloads = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    if (url == '$_url/$_name.sha256') {
      return ResponseBody.fromString('$checksum  $_name\n', 200);
    }
    if (url == '$_url/$_name') {
      downloads++;
      final body = this.body;
      return body == null
          ? ResponseBody.fromBytes(_payload, 200)
          : ResponseBody(body, 200);
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _Platform implements UpdatePlatform {
  @override
  final target = const UpdateTarget(UpdateInstallKind.macos, ['arm64']);

  Exception? verifyError;
  final installs = <Object>[];
  var installCalls = 0;

  @override
  Future<void> verify(File file) async {
    if (verifyError case final error?) {
      throw error;
    }
  }

  @override
  Future<UpdateInstallResult> install(File file) async {
    installCalls++;
    final next = installs.removeAt(0);
    return switch (next) {
      final UpdateInstallResult result => result,
      final Exception error => throw error,
      _ => throw next as Error,
    };
  }
}

class _Downloader extends UpdateDownloader {
  _Downloader({required super.root, super.dio, this.keeping});

  final Future<void>? keeping;

  @override
  Future<File> keep(File partial, UpdateAsset asset, String slot) async {
    final kept = await super.keep(partial, asset, slot);
    await keeping;
    return kept;
  }
}

Map<String, dynamic> get _release => {
  'tag_name': 'v0.5.1',
  'prerelease': false,
  'assets': [
    {
      'name': _name,
      'size': _payload.length,
      'browser_download_url': '$_url/$_name',
    },
    {
      'name': '$_name.sha256',
      'size': 90,
      'browser_download_url': '$_url/$_name.sha256',
    },
  ],
};

void main() {
  late Directory root;
  late _Adapter adapter;
  late _Platform platform;
  late UpdateErrorKind? blocker;
  late List<UpdateState> states;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flclashx_update_controller');
    adapter = _Adapter();
    platform = _Platform();
    blocker = null;
    states = [];
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  UpdateController controller({
    Map<String, dynamic>? release,
    bool manifest = false,
    Future<String> Function(String path) hash = sha256OfFile,
    Future<void>? keeping,
  }) {
    final controller = UpdateController(
      release: release ?? _release,
      platform: platform,
      downloader: _Downloader(
        root: () async => root,
        dio: Dio()..httpClientAdapter = adapter,
        keeping: keeping,
      ),
      repository: 'pluralplay/FlClashX',
      pre: false,
      manifest: manifest,
      installBlocker: () => blocker,
      hash: hash,
    );
    controller.addListener(() => states.add(controller.value));
    return controller;
  }

  Future<List<File>> files() async {
    try {
      return [
        await for (final entity in root.list(recursive: true))
          if (entity is File) entity,
      ];
    } on PathNotFoundException {
      return [];
    }
  }

  Future<void> untilStreaming() async {
    while ((await files()).isEmpty) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
  }

  test('downloads, verifies and waits for Install', () async {
    final update = controller();
    await update.download();
    expect(update.value.phase, UpdatePhase.ready);
    expect(states.map((state) => state.phase).toSet(), {
      UpdatePhase.downloading,
      UpdatePhase.verifying,
      UpdatePhase.ready,
    });
    final downloading = states.lastWhere(
      (state) => state.phase == UpdatePhase.downloading,
    );
    expect(downloading.received, _payload.length);
    expect(downloading.total, _payload.length);
    expect((await files()).single.readAsBytesSync(), _payload);

    platform.installs.add(UpdateInstallResult.exiting);
    await update.install();
    expect(update.value.phase, UpdatePhase.done);
    expect(update.value.result, UpdateInstallResult.exiting);
    update.dispose();
    await pumpEventQueue();
    expect(await files(), hasLength(1));
  });

  test(
    'a manifest downloads with its inline hash, not a .sha256 file',
    () async {
      adapter.checksum = 'b' * 64; // a fetched .sha256 would fail the download
      final manifest = {
        'tag_name': 'v0.5.1',
        'version': 'v0.5.1',
        'assets': [
          {
            'name': _name,
            'url': '$_url/$_name',
            'sha256': sha256.convert(_payload).toString(),
          },
        ],
      };
      final update = controller(release: manifest, manifest: true);
      await update.download();
      expect(update.value.phase, UpdatePhase.ready);
      update.dispose();
    },
  );

  test('a checksum mismatch fails and deletes the download', () async {
    adapter.checksum = 'b' * 64;
    final update = controller();
    await update.download();
    expect(update.value.phase, UpdatePhase.failed);
    expect(update.value.error?.kind, UpdateErrorKind.checksumMismatch);
    expect(await files(), isEmpty);
    update.dispose();
  });

  test('an identity mismatch fails and deletes the download', () async {
    platform.verifyError = const UpdateException(
      UpdateErrorKind.identityMismatch,
    );
    final update = controller();
    await update.download();
    expect(update.value.error?.kind, UpdateErrorKind.identityMismatch);
    expect(await files(), isEmpty);
    update.dispose();
  });

  test('cancel goes back to idle and leaves no file', () async {
    final held = StreamController<Uint8List>();
    adapter.body = held.stream;
    final update = controller();
    final download = update.download();
    held.add(Uint8List(100));
    await untilStreaming();
    expect(update.value.phase, UpdatePhase.downloading);
    expect(await files(), hasLength(1));
    update.cancel();
    held.add(Uint8List(100));
    await download;
    await held.close();
    expect(update.value.phase, UpdatePhase.idle);
    expect(states.where((state) => state.phase == UpdatePhase.failed), isEmpty);
    expect(await files(), isEmpty);
    update.dispose();
  });

  test('closing the dialog mid-download cancels it and cleans up', () async {
    final held = StreamController<Uint8List>();
    adapter.body = held.stream;
    final update = controller();
    final download = update.download();
    held.add(Uint8List(100));
    await untilStreaming();
    update.dispose();
    held.add(Uint8List(100));
    await download;
    await held.close();
    expect(await files(), isEmpty);
  });

  test('a blocker keeps the download and explains itself', () async {
    final update = controller();
    await update.download();
    for (final kind in [UpdateErrorKind.busy, UpdateErrorKind.safeMode]) {
      blocker = kind;
      await update.install();
      expect(update.value.phase, UpdatePhase.ready);
      expect(update.value.error?.kind, kind);
    }
    expect(platform.installCalls, 0);
    expect(await files(), hasLength(1));
    update.dispose();
    await pumpEventQueue();
    expect(await files(), hasLength(1));
  });

  test('a dialog closed after the download installs it without downloading '
      'again', () async {
    final first = controller();
    await first.download();
    first.dispose();
    await pumpEventQueue();
    expect(adapter.downloads, 1);

    final again = controller();
    await again.download();
    expect(again.value.phase, UpdatePhase.ready);
    expect(adapter.downloads, 1);
    platform.installs.add(UpdateInstallResult.exiting);
    await again.install();
    expect(again.value.phase, UpdatePhase.done);
    again.dispose();
  });

  test(
    'a cached file that is cut short or changed is downloaded again',
    () async {
      final first = controller();
      await first.download();
      first.dispose();
      (await files()).single.writeAsBytesSync(_payload.sublist(0, 100));

      final again = controller();
      await again.download();
      expect(again.value.phase, UpdatePhase.ready);
      expect(adapter.downloads, 2);
      expect((await files()).single.readAsBytesSync(), _payload);
      again.dispose();
    },
  );

  test(
    'a cancel while the download moves into place leaves it for a retry',
    () async {
      final keeping = Completer<void>();
      final update = controller(keeping: keeping.future);
      final first = update.download();
      while ((await files()).isEmpty ||
          !(await files()).single.path.endsWith('/0.5.1/$_name')) {
        await pumpEventQueue();
      }
      update.cancel();
      keeping.complete();
      await first;
      expect(update.value.phase, UpdatePhase.idle);
      expect(await files(), hasLength(1));
      update.dispose();

      final again = controller();
      await again.download();
      expect(again.value.phase, UpdatePhase.ready);
      expect(adapter.downloads, 1);
      again.dispose();
    },
  );

  test(
    'a cancelled check of the cached file leaves the retry its file',
    () async {
      final first = controller();
      await first.download();
      first.dispose();

      final hashing = Completer<void>();
      var calls = 0;
      final update = controller(
        hash: (path) async {
          if (calls++ == 0) {
            await hashing.future;
            return 'c' * 64;
          }
          return sha256OfFile(path);
        },
      );
      final stale = update.download();
      while (calls == 0) {
        await pumpEventQueue();
      }
      update.cancel();
      await update.download();
      expect(update.value.phase, UpdatePhase.ready);
      hashing.complete();
      await stale;

      expect(update.value.phase, UpdatePhase.ready);
      expect((await files()).single.readAsBytesSync(), _payload);
      expect(adapter.downloads, 1);
      update.dispose();
    },
  );

  test('a download for another release is cleared by the next one', () async {
    final stale = File('${root.path}/0.5.0/$_name')
      ..createSync(recursive: true);
    final update = controller();
    await update.download();
    expect(stale.existsSync(), isFalse);
    expect((await files()).single.path, endsWith('/0.5.1/$_name'));
    update.dispose();
  });

  test('a download changed while it waited for Install is refused', () async {
    final update = controller();
    await update.download();
    (await files()).single.writeAsBytesSync([1, 2, 3]);
    platform.installs.add(UpdateInstallResult.exiting);

    await update.install();

    expect(update.value.phase, UpdatePhase.failed);
    expect(update.value.error?.kind, UpdateErrorKind.checksumMismatch);
    expect(platform.installCalls, 0);
    expect(await files(), isEmpty);
    update.dispose();
  });

  test('the package is checked against the app again before it runs', () async {
    final update = controller();
    await update.download();
    platform.verifyError = const UpdateException(
      UpdateErrorKind.identityMismatch,
    );
    platform.installs.add(UpdateInstallResult.exiting);

    await update.install();

    expect(update.value.error?.kind, UpdateErrorKind.identityMismatch);
    expect(platform.installCalls, 0);
    expect(await files(), isEmpty);
    update.dispose();
  });

  test('an install failure can be retried', () async {
    final update = controller();
    await update.download();
    platform.installs
      ..add(const UpdateException(UpdateErrorKind.installPermission))
      ..add(StateError('boom'))
      ..add(UpdateInstallResult.handedOff);
    await update.install();
    expect(update.value.error?.kind, UpdateErrorKind.installPermission);
    await update.install();
    expect(update.value.error?.kind, UpdateErrorKind.installFailed);
    await update.install();
    expect(update.value.phase, UpdatePhase.done);
    expect(update.value.result, UpdateInstallResult.handedOff);

    update.onInstallStatus('aborted', null);
    expect(update.value, const UpdateState(UpdatePhase.ready));
    update.onInstallStatus('failed', 'INSTALL_FAILED_INVALID_APK');
    expect(update.value.error?.kind, UpdateErrorKind.installFailed);
    expect(update.value.error?.detail, 'INSTALL_FAILED_INVALID_APK');
    update.dispose();
    update.onInstallStatus('failed', null);
  });

  test('a release without this build fails before any request', () async {
    final update = UpdateController(
      release: {'tag_name': 'v0.5.1', 'prerelease': false, 'assets': []},
      platform: platform,
      downloader: UpdateDownloader(
        root: () async => root,
        dio: Dio()..httpClientAdapter = adapter,
      ),
      repository: 'pluralplay/FlClashX',
      pre: false,
      installBlocker: () => null,
    );
    await update.download();
    expect(update.value.error?.kind, UpdateErrorKind.noAsset);
    update.dispose();
  });
}
