import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

const _primary = 'https://old.example.com/sub/abc?x=1';
const _moved = 'https://new.example.com/sub/abc?x=1';

Response<Uint8List> _answer(
  String host, {
  Map<String, String> headers = const {},
}) => Response(
  requestOptions: RequestOptions(path: host),
  statusCode: 200,
  data: Uint8List.fromList(utf8.encode('proxies: [] # $host')),
  headers: Headers.fromMap({
    for (final MapEntry(:key, :value) in headers.entries) key: [value],
  }),
);

DioException _status(String url, int status) => DioException.badResponse(
  statusCode: status,
  requestOptions: RequestOptions(path: url),
  response: Response(
    requestOptions: RequestOptions(path: url),
    statusCode: status,
  ),
);

/// Answers each URL from [byUrl], recording the order and timeouts asked.
class _Fetcher {
  _Fetcher(this.byUrl);

  final Map<String, Object> byUrl;
  final calls = <(String, Duration)>[];
  final sentHeaders = <Map<String, String>>[];

  Future<Response<Uint8List>> call(
    String url, {
    Duration timeout = downloadTimeoutDuration,
    Map<String, String> headers = const {},
  }) async {
    calls.add((url, timeout));
    sentHeaders.add(headers);
    return switch (byUrl[url]) {
      final Response<Uint8List> answer => answer,
      final Exception error => throw error,
      _ => throw StateError('unexpected $url'),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('profile_update_test');
    await useAppPaths(tempDir);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Profile profile({String hosts = 'new.example.com'}) => Profile.normal(
    label: 'p',
    url: _primary,
  ).copyWith(providerHeaders: {'flclashx-newdomain': hosts});

  Future<String> valid(String path, String key) async => '';

  Future<String> saved(Profile profile) async =>
      (await profile.file).readAsString();

  test('a working host is the only one asked', () async {
    final fetch = _Fetcher({_primary: _answer('old')});

    final updated = await profile().update(validate: valid, fetch: fetch.call);

    expect(fetch.calls, [(_primary, downloadTimeoutDuration)]);
    expect(updated.url, _primary);
    expect(await saved(updated), 'proxies: [] # old');
  });

  test(
    'a new profile is named by profile-title before the file name',
    () async {
      final fetch = _Fetcher({
        _primary: _answer(
          'old',
          headers: {
            'profile-title': 'base64:${base64.encode(utf8.encode('Мой VPN'))}',
            'content-disposition': 'attachment; filename="sub.yaml"',
          },
        ),
      });

      final named = await profile().update(validate: valid, fetch: fetch.call);
      expect(named.label, 'p');

      final fresh = await profile()
          .copyWith(label: '')
          .update(validate: valid, fetch: fetch.call);
      expect(fresh.label, 'Мой VPN');
    },
  );

  test('an outage is served by the fallback and the link stays', () async {
    final fetch = _Fetcher({
      _primary: _status(_primary, 503),
      _moved: _answer('new'),
    });

    final updated = await profile().update(validate: valid, fetch: fetch.call);

    expect(fetch.calls, [
      (_primary, downloadTimeoutDuration),
      (_moved, fallbackTimeoutDuration),
    ]);
    expect(updated.url, _primary);
    expect(await saved(updated), 'proxies: [] # new');
  });

  test(
    'a gone host moves the profile onto the fallback that answered',
    () async {
      final fetch = _Fetcher({
        _primary: _status(_primary, 404),
        'https://dead.example.com/sub/abc?x=1': _status('dead', 404),
        _moved: _answer(
          'new',
          headers: {'flclashx-newdomain': 'old.example.com'},
        ),
      });

      final updated = await profile(
        hosts: 'dead.example.com, new.example.com',
      ).update(validate: valid, fetch: fetch.call);

      expect(updated.url, _moved);
      expect(updated.providerHeaders, {
        'flclashx-newdomain': 'old.example.com',
      });
      expect(await saved(updated), 'proxies: [] # new');
    },
  );

  test('a host serving something else counts as gone', () async {
    final fetch = _Fetcher({
      _primary: _answer('parked'),
      _moved: _answer('new'),
    });
    Future<String> validate(String path, String key) async =>
        (await File(path).readAsString()).contains('parked') ? 'invalid' : '';

    final updated = await profile().update(
      validate: validate,
      fetch: fetch.call,
    );

    expect(updated.url, _moved);
    expect(await saved(updated), 'proxies: [] # new');
  });

  test('the first error is reported when no fallback answers either', () async {
    final fetch = _Fetcher({
      _primary: _status(_primary, 503),
      _moved: _status(_moved, 404),
    });

    await expectLater(
      profile().update(validate: valid, fetch: fetch.call),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          503,
        ),
      ),
    );
    expect(fetch.calls, hasLength(2));
  });

  test('without fallback hosts the error passes straight through', () async {
    final fetch = _Fetcher({_primary: _status(_primary, 404)});

    await expectLater(
      profile(hosts: '').update(validate: valid, fetch: fetch.call),
      throwsA(isA<DioException>()),
    );
    expect(fetch.calls, hasLength(1));
  });

  test('the panel sets the auto-update interval in hours', () async {
    final fetch = _Fetcher({
      _primary: _answer('old', headers: {'profile-update-interval': '6'}),
    });

    final updated = await profile().update(validate: valid, fetch: fetch.call);

    expect(updated.autoUpdateDuration, const Duration(hours: 6));
  });

  test('without the interval header the profile keeps its own', () async {
    final fetch = _Fetcher({_primary: _answer('old')});
    final before = profile().copyWith(
      autoUpdateDuration: const Duration(minutes: 90),
    );

    final updated = await before.update(validate: valid, fetch: fetch.call);

    expect(updated.autoUpdateDuration, const Duration(minutes: 90));
  });

  group('device headers', () {
    const device = {'x-hwid': 'ABCDEF0123456789', 'x-device-os': 'macOS'};
    Future<Map<String, String>> identity() async => device;

    test('go with the first request and with each fallback', () async {
      final fetch = _Fetcher({
        _primary: _status(_primary, 503),
        _moved: _answer('new'),
      });

      await profile().update(
        validate: valid,
        fetch: fetch.call,
        deviceHeaders: identity,
      );

      expect(fetch.sentHeaders, [device, device]);
    });

    test('stay home when the profile has them off', () async {
      final fetch = _Fetcher({_primary: _answer('old')});
      var asked = false;

      await profile()
          .copyWith(sendDeviceHeaders: false)
          .update(
            validate: valid,
            fetch: fetch.call,
            deviceHeaders: () async {
              asked = true;
              return device;
            },
          );

      expect(fetch.sentHeaders, [isEmpty]);
      expect(asked, isFalse);
    });
  });
}
