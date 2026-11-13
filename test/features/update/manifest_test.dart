import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/update/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://mirror.example/manifest.json';

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

Map<String, dynamic> _manifest(String version) => {
  'version': version,
  'assets': [
    {
      'name': 'FlClashX-macos-arm64.dmg',
      'url': 'https://mirror.example/$version/FlClashX-macos-arm64.dmg',
      'sha256': 'a' * 64,
    },
  ],
};

ResponseBody _json(Object body) =>
    ResponseBody.fromString(jsonEncode(body), 200);

Matcher _rejected(String reason) => throwsA(
  isA<UpdateManifestException>().having(
    (e) => e.reason,
    'reason',
    contains(reason),
  ),
);

void main() {
  Future<Map<String, dynamic>?> fetch(
    Map<String, ResponseBody Function()> routes, {
    String current = '0.5.0',
    bool pre = false,
  }) => fetchManifestUpdate(
    Dio()..httpClientAdapter = _FakeAdapter(routes),
    Uri.parse(_url),
    currentVersion: current,
    pre: pre,
  );

  test('a newer manifest is offered as a release', () async {
    final res = await fetch({_url: () => _json(_manifest('v0.5.2'))});
    expect(res?['tag_name'], 'v0.5.2');
    expect(res?['_isManifest'], true);
    expect(res?['assets'], isNotEmpty);
  });

  test('a manifest no newer than the build offers nothing', () async {
    expect(
      await fetch({_url: () => _json(_manifest('v0.5.2'))}, current: '0.5.2'),
      isNull,
    );
  });

  test('follows https redirects by hand', () async {
    const moved = 'https://cdn.example/manifest.json';
    final res = await fetch({
      _url: () => _redirect(moved),
      moved: () => _json(_manifest('v0.5.2')),
    });
    expect(res?['tag_name'], 'v0.5.2');
  });

  test('a redirect to http is refused', () async {
    await expectLater(
      fetch({
        _url: () => _redirect('http://mirror.example/manifest.json'),
        'http://mirror.example/manifest.json': () => _json(_manifest('v0.5.2')),
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
      fetch({_url: () => _json(_manifest('v0.5.3-pre.1'))}),
      _rejected('other channel'),
    );
  });

  test('a pre-release build refuses a stable manifest', () async {
    await expectLater(
      fetch(
        {_url: () => _json(_manifest('v0.5.3'))},
        current: '0.5.2-pre.1',
        pre: true,
      ),
      _rejected('other channel'),
    );
  });

  test('a pre-release build takes a newer pre-release manifest', () async {
    final res = await fetch(
      {_url: () => _json(_manifest('v0.5.2-pre.2'))},
      current: '0.5.2-pre.1',
      pre: true,
    );
    expect(res?['tag_name'], 'v0.5.2-pre.2');
  });

  test('a version outside the app tags is refused', () async {
    for (final version in ['0.5.2', 'v0.5.2-beta', 'core-v1.19.30', 'v0.5']) {
      await expectLater(
        fetch({_url: () => _json(_manifest(version))}),
        _rejected('malformed version'),
      );
    }
  });
}
