import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/manifest.dart';
import 'package:fl_clash/features/update/manifest_signature.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://mirror.example/manifest.json';
final _seed = List<int>.generate(32, (i) => i * 7 + 1);
final _otherSeed = List<int>.generate(32, (i) => 255 - i);

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> routes;

  _FakeAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      routes[options.uri.toString()]?.call() ??
      ResponseBody.fromString('', 404);

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

ResponseBody _json(Object body) =>
    ResponseBody.fromString(jsonEncode(body), 200);

Map<String, dynamic> _manifest(
  String version, {
  List<String> names = const ['FlClashX-macos-arm64.dmg'],
}) => {
  'version': version,
  'assets': [
    for (final name in names)
      {
        'name': name,
        'url': 'https://mirror.example/$version/$name',
        'sha256': 'a' * 64,
      },
  ],
};

Future<Map<String, dynamic>> _signed(
  Map<String, dynamic> manifest, {
  List<int>? seed,
}) async {
  final message = updateManifestMessage(manifest['version'] as String, [
    for (final asset in manifest['assets'] as List)
      (name: asset['name'] as String, sha256: asset['sha256'] as String),
  ]);
  final signed = await signUpdateManifest(message, seed ?? _seed);
  return {...manifest, 'signature': signed.signature};
}

Matcher _rejected(String reason) => throwsA(
  isA<UpdateManifestException>().having(
    (e) => e.reason,
    'reason',
    contains(reason),
  ),
);

void main() {
  late List<String> keys;

  setUpAll(() async {
    keys = [(await signUpdateManifest(const [], _seed)).publicKey];
  });

  Future<Map<String, dynamic>?> fetch(
    Map<String, ResponseBody Function()> routes, {
    String current = '0.5.0',
    bool pre = false,
  }) => fetchManifestUpdate(
    Dio()..httpClientAdapter = _FakeAdapter(routes),
    Uri.parse(_url),
    currentVersion: current,
    pre: pre,
    keys: keys,
  );

  Future<Map<String, dynamic>?> serve(
    Map<String, dynamic> body, {
    String current = '0.5.0',
    bool pre = false,
  }) => fetch({_url: () => _json(body)}, current: current, pre: pre);

  test('a newer signed manifest is offered as a release', () async {
    final res = await serve(await _signed(_manifest('v0.5.2')));
    expect(res?['tag_name'], 'v0.5.2');
    expect(res?['_isManifest'], true);
    expect(res?['assets'], isNotEmpty);
  });

  test('a manifest no newer than the build offers nothing', () async {
    expect(
      await serve(await _signed(_manifest('v0.5.2')), current: '0.5.2'),
      isNull,
    );
  });

  test('follows https redirects by hand', () async {
    const moved = 'https://cdn.example/manifest.json';
    final body = await _signed(_manifest('v0.5.2'));
    final res = await fetch({
      _url: () => _redirect(moved),
      moved: () => _json(body),
    });
    expect(res?['tag_name'], 'v0.5.2');
  });

  test('a redirect to http is refused', () async {
    final body = await _signed(_manifest('v0.5.2'));
    await expectLater(
      fetch({
        _url: () => _redirect('http://mirror.example/manifest.json'),
        'http://mirror.example/manifest.json': () => _json(body),
      }),
      _rejected('not https'),
    );
  });

  test('gives up after five redirects', () async {
    await expectLater(
      fetch({_url: () => _redirect(_url)}),
      _rejected('too many redirects'),
    );
  });

  test('a stable build refuses a pre-release manifest', () async {
    await expectLater(
      serve(await _signed(_manifest('v0.5.3-pre.1'))),
      _rejected('other channel'),
    );
  });

  test('a pre-release build refuses a stable manifest', () async {
    await expectLater(
      serve(
        await _signed(_manifest('v0.5.3')),
        current: '0.5.2-pre.1',
        pre: true,
      ),
      _rejected('other channel'),
    );
  });

  test('a pre-release build takes a newer pre-release manifest', () async {
    final res = await serve(
      await _signed(_manifest('v0.5.2-pre.2')),
      current: '0.5.2-pre.1',
      pre: true,
    );
    expect(res?['tag_name'], 'v0.5.2-pre.2');
  });

  test('a version outside the app tags is refused', () async {
    for (final version in ['0.5.2', 'v0.5.2-beta', 'core-v1.19.30', 'v0.5']) {
      await expectLater(
        serve({..._manifest(version), 'signature': ''}),
        _rejected('malformed version'),
      );
    }
  });

  group('the signature', () {
    test('a manifest without one is refused', () async {
      await expectLater(serve(_manifest('v0.5.2')), _rejected('signature'));
    });

    test('one that is not base64 or not 64 bytes is refused', () async {
      for (final signature in [
        'not base64!',
        base64.encode([1, 2, 3]),
      ]) {
        await expectLater(
          serve({..._manifest('v0.5.2'), 'signature': signature}),
          _rejected('signature'),
        );
      }
    });

    test('one by a key outside the list is refused', () async {
      await expectLater(
        serve(await _signed(_manifest('v0.5.2'), seed: _otherSeed)),
        _rejected('signature'),
      );
    });

    test('any key of the list is accepted', () async {
      final pinned = keys;
      addTearDown(() => keys = pinned);
      keys = [
        (await signUpdateManifest(const [], _otherSeed)).publicKey,
        ...keys,
      ];
      expect(await serve(await _signed(_manifest('v0.5.2'))), isNotNull);
    });

    test('it covers the version and every hash, not the urls', () async {
      final body = await _signed(_manifest('v0.5.2'));
      final asset = (body['assets'] as List).single as Map;
      expect(
        await serve({
          ...body,
          'assets': [
            {...asset, 'url': 'https://other.example/x.dmg'},
          ],
        }),
        isNotNull,
      );
      await expectLater(
        serve({...body, 'version': 'v0.5.3'}),
        _rejected('signature'),
      );
      await expectLater(
        serve({
          ...body,
          'assets': [
            {...asset, 'sha256': 'b' * 64},
          ],
        }),
        _rejected('signature'),
      );
      await expectLater(
        serve({...body, 'assets': const []}),
        _rejected('signature'),
      );
    });

    test('fields it does not cover are dropped', () async {
      final res = await serve({
        ...await _signed(_manifest('v0.5.2')),
        'body': 'unsigned notes',
        'html_url': 'https://github.com/other/repo',
      });
      expect(
        res?.keys,
        unorderedEquals(['version', 'assets', 'tag_name', '_isManifest']),
      );
    });

    test('duplicate asset names are refused', () async {
      const name = 'FlClashX-macos-arm64.dmg';
      await expectLater(
        serve({
          ..._manifest('v0.5.2', names: [name, name]),
          'signature': (await _signed(_manifest('v0.5.2')))['signature'],
        }),
        _rejected('duplicate asset'),
      );
    });

    test('a malformed hash is refused', () async {
      final manifest = _manifest('v0.5.2');
      final asset = (manifest['assets'] as List).single as Map;
      for (final sha in ['a' * 63, 'g' * 64, 42]) {
        await expectLater(
          serve({
            ...manifest,
            'assets': [
              {...asset, 'sha256': sha},
            ],
            'signature': '',
          }),
          _rejected('malformed'),
        );
      }
    });
  });

  test('the pinned keys are raw 32-byte keys', () {
    expect(updateManifestKeys, isNotEmpty);
    for (final key in updateManifestKeys) {
      expect(base64.decode(key), hasLength(32));
    }
  });
}
