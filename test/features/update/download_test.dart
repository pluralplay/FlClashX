import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/download.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = 'FlClashX-macos-arm64.dmg';
const _base = 'https://github.com/pluralplay/FlClashX/releases/download/v0.5.1';
const _cdn = 'https://release-assets.githubusercontent.com/blob';

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> routes;
  final requested = <String>[];

  _FakeAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    return routes[url]?.call() ?? ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _redirect(String to) => ResponseBody.fromString(
  '',
  302,
  headers: {
    HttpHeaders.locationHeader: [to],
  },
);

ResponseBody _bytes(List<int> data, {int? length}) => ResponseBody.fromBytes(
  data,
  200,
  headers: {
    if (length != null) Headers.contentLengthHeader: ['$length'],
  },
);

UpdateAsset _asset({int? size}) => UpdateAsset(
  name: _name,
  url: Uri.parse('$_base/$_name'),
  checksumUrl: Uri.parse('$_base/$_name.sha256'),
  size: size,
);

Matcher _fails(UpdateErrorKind kind) =>
    throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', kind));

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('flclashx_update_test');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  UpdateDownloader downloader(_FakeAdapter adapter) => UpdateDownloader(
    root: () async => root,
    dio: Dio()..httpClientAdapter = adapter,
  );

  Future<List<FileSystemEntity>> leftovers() =>
      root.list(recursive: true).toList();

  test(
    'follows redirects inside the allowlist and keeps the asset name',
    () async {
      final payload = List<int>.generate(3000, (i) => i % 251);
      final adapter = _FakeAdapter({
        '$_base/$_name': () => _redirect('$_cdn?sig=1'),
        '$_cdn?sig=1': () => _bytes(payload),
      });
      final progress = <int>[];
      final file = await downloader(
        adapter,
      ).download(_asset(size: 3000), onProgress: (r, _) => progress.add(r));
      expect(await file.readAsBytes(), payload);
      expect(file.path, endsWith('/$_name'));
      expect(file.path, startsWith(root.path));
      expect(progress.last, 3000);
      expect(adapter.requested, ['$_base/$_name', '$_cdn?sig=1']);
    },
  );

  test('a manifest asset follows the release download to its CDN', () async {
    final payload = List<int>.generate(3000, (i) => i % 251);
    for (final url in ['$_base/$_name', 'https://mirror.example/$_name']) {
      final asset = manifestUpdateAsset({
        'assets': [
          {'name': _name, 'url': url, 'sha256': 'a' * 64},
        ],
      }, const UpdateTarget(UpdateInstallKind.macos, ['arm64']));
      final adapter = _FakeAdapter({
        url: () => _redirect('$_cdn?sig=1'),
        '$_cdn?sig=1': () => _bytes(payload),
      });
      final file = await downloader(adapter).download(asset);
      expect(await file.readAsBytes(), payload);
      expect(adapter.requested, [url, '$_cdn?sig=1']);
    }
  });

  test('refuses a redirect off the allowlist and leaves nothing', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _redirect('https://evil.example/x'),
    });
    await expectLater(
      downloader(adapter).download(_asset()),
      _fails(UpdateErrorKind.untrustedHost),
    );
    expect(adapter.requested, ['$_base/$_name']);
    expect(await leftovers(), isEmpty);
  });

  test('refuses a downgrade to plain HTTP on the same host', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _redirect('http://github.com/x'),
    });
    await expectLater(
      downloader(adapter).download(_asset()),
      _fails(UpdateErrorKind.untrustedHost),
    );
  });

  test('stops a redirect loop', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _redirect('$_base/$_name'),
    });
    await expectLater(
      downloader(adapter).download(_asset()),
      _fails(UpdateErrorKind.network),
    );
    expect(adapter.requested.length, 6);
  });

  test('refuses a body announced larger than the cap', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _bytes([1, 2, 3], length: 5000),
    });
    await expectLater(
      downloader(adapter).download(_asset(size: 100)),
      _fails(UpdateErrorKind.tooLarge),
    );
    expect(await leftovers(), isEmpty);
  });

  test('stops a body that grows past the cap', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _bytes(List.filled(150, 7)),
    });
    await expectLater(
      downloader(adapter).download(_asset(size: 100)),
      _fails(UpdateErrorKind.tooLarge),
    );
    expect(await leftovers(), isEmpty);
  });

  test('rejects a body shorter than the release says', () async {
    final adapter = _FakeAdapter({
      '$_base/$_name': () => _bytes(List.filled(90, 7)),
    });
    await expectLater(
      downloader(adapter).download(_asset(size: 100)),
      _fails(UpdateErrorKind.incomplete),
    );
    expect(await leftovers(), isEmpty);
  });

  test('a cancelled download removes its partial file', () async {
    final chunks = StreamController<Uint8List>();
    final adapter = _FakeAdapter({
      '$_base/$_name': () => ResponseBody(chunks.stream, 200),
    });
    final cancelToken = CancelToken();
    final download = downloader(adapter).download(
      _asset(size: 100),
      cancelToken: cancelToken,
      onProgress: (_, _) => cancelToken.cancel(),
    );
    final failed = expectLater(download, throwsA(isA<DioException>()));
    chunks.add(Uint8List(10));
    await pumpEventQueue();
    chunks.add(Uint8List(10));
    await failed;
    await chunks.close();
    expect(await leftovers(), isEmpty);
  });

  test('reads the checksum file and caps its size', () async {
    final hash = 'a' * 64;
    final adapter = _FakeAdapter({
      '$_base/$_name.sha256': () => _bytes(utf8.encode('$hash  ./$_name\n')),
    });
    expect(await downloader(adapter).fetchChecksum(_asset()), hash);

    final huge = _FakeAdapter({
      '$_base/$_name.sha256': () => _bytes(List.filled(5000, 0x61)),
    });
    await expectLater(
      downloader(huge).fetchChecksum(_asset()),
      _fails(UpdateErrorKind.tooLarge),
    );

    final missing = _FakeAdapter({
      '$_base/$_name.sha256': () => _bytes(utf8.encode('$hash  other.dmg')),
    });
    await expectLater(
      downloader(missing).fetchChecksum(_asset()),
      _fails(UpdateErrorKind.noChecksum),
    );
  });

  test('purge clears what earlier runs left', () async {
    await File('${root.path}/old/file').create(recursive: true);
    await downloader(_FakeAdapter({})).purge();
    expect(await root.exists(), isFalse);
  });

  test('sha256OfFile hashes off the UI isolate', () async {
    final file = File('${root.path}/payload');
    final payload = List<int>.generate(70000, (i) => i % 256);
    await file.writeAsBytes(payload);
    expect(await sha256OfFile(file.path), sha256.convert(payload).toString());
  });
}
