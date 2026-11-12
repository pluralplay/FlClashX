import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

/// flutter_test answers every request with a 400 unless a zone asks for a
/// real client.
class _RealHttpOverrides extends HttpOverrides {}

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.byHost);

  final Map<String, ResponseBody Function()> byHost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return byHost[options.uri.host]!();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('update channel', () {
    test('picks the highest pre-release and passes stable and drafts by', () {
      final newest = newestPrerelease([
        {'tag_name': 'v0.5.1', 'prerelease': false},
        {'tag_name': 'v0.5.1-pre.10', 'prerelease': true},
        {'tag_name': 'v0.5.1-pre.9', 'prerelease': true},
        {'tag_name': 'v0.5.1-pre.11', 'prerelease': true, 'draft': true},
        'not a release',
      ]);

      expect(newest?['tag_name'], 'v0.5.1-pre.10');
    });

    ResponseBody json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

    void installed(String env, String version) {
      globalState.appEnv = env;
      globalState.packageInfo = PackageInfo(
        appName: 'FlClashX',
        packageName: 'com.follow.clashx',
        version: version,
        buildNumber: '1',
      );
    }

    test('a pre-release build is offered only a newer pre-release', () async {
      installed('pre', '0.5.1-pre.9');
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => json([
            {'tag_name': 'v0.5.1', 'prerelease': false},
            {'tag_name': 'v0.5.1-pre.10', 'prerelease': true},
          ]),
        });

      expect((await request.checkForUpdate())?['tag_name'], 'v0.5.1-pre.10');
    });

    test('a stable build keeps to the latest release', () async {
      installed('stable', '0.5.0');
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => json({'tag_name': 'v0.5.1'}),
        });

      expect((await request.checkForUpdate())?['tag_name'], 'v0.5.1');
    });

    test('finds none among stable releases only', () {
      expect(
        newestPrerelease([
          {'tag_name': 'v0.5.0', 'prerelease': false},
        ]),
        isNull,
      );
    });
  });

  group('latestRelease', () {
    Request requestAnswering(Map<String, ResponseBody Function()> byHost) {
      return Request()..dio.httpClientAdapter = _HostAdapter(byHost);
    }

    test('reads the release from the API', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString(
          '{"tag_name":"v1.2.3","body":"notes"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      });

      expect(await request.latestRelease(), {
        'tag_name': 'v1.2.3',
        'body': 'notes',
      });
    });

    test(
      'falls back to the release page when the API is rate limited',
      () async {
        final request = requestAnswering({
          'api.github.com': () => ResponseBody.fromString('{}', 403),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases/tag/v1.2.4',
              ],
            },
          ),
        });

        expect(await request.latestRelease(), {'tag_name': 'v1.2.4'});
      },
    );

    test('fails instead of answering when neither endpoint does', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString('{}', 403),
        'github.com': () => ResponseBody.fromString('', 503),
      });

      await expectLater(request.latestRelease(), throwsA(isA<DioException>()));
    });
  });

  group('hostFailureOf', () {
    final options = RequestOptions(path: 'https://x');
    DioException response(int status) => DioException.badResponse(
      statusCode: status,
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: status),
    );
    DioException socket(SocketException cause) => DioException.connectionError(
      requestOptions: options,
      reason: cause.message,
      error: cause,
    );

    test('calls a gone host or resource hard', () {
      expect(hostFailureOf(response(404)), HostFailure.hard);
      expect(hostFailureOf(response(410)), HostFailure.hard);
      expect(
        hostFailureOf(
          socket(
            const SocketException(
              "Failed host lookup: 'x'",
              osError: OSError('nodename nor servname', 8),
            ),
          ),
        ),
        HostFailure.hard,
      );
      expect(
        hostFailureOf(
          socket(
            const SocketException(
              'Connection refused',
              osError: OSError('refused', 61),
            ),
          ),
        ),
        HostFailure.hard,
      );
      expect(
        hostFailureOf(DioException.badCertificate(requestOptions: options)),
        HostFailure.hard,
      );
      expect(
        hostFailureOf(const MessageException('invalid config')),
        HostFailure.hard,
      );
    });

    test('calls an outage soft', () {
      expect(hostFailureOf(response(503)), HostFailure.soft);
      expect(hostFailureOf(response(429)), HostFailure.soft);
      expect(
        hostFailureOf(
          DioException.receiveTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: options,
          ),
        ),
        HostFailure.soft,
      );
      expect(
        hostFailureOf(
          socket(
            const SocketException(
              'Connection reset by peer',
              osError: OSError('reset', 54),
            ),
          ),
        ),
        HostFailure.soft,
      );
      expect(hostFailureOf(StateError('odd')), HostFailure.soft);
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });

    test('gives up once the output passes the limit', () {
      final body = Uint8List.fromList(gzip.encode(Uint8List(4096)));

      expect(decompressUnlabeled(body, limit: 4096), hasLength(4096));
      expect(decompressUnlabeled(body, limit: 4095), isNull);
    });
  });

  group('decompressDownload', () {
    test('inflates a compressed body and passes a plain one through', () async {
      final yaml = Uint8List.fromList(utf8.encode('proxies: []\n'));

      expect(await decompressDownload(yaml), same(yaml));
      expect(
        await decompressDownload(Uint8List.fromList(gzip.encode(yaml))),
        yaml,
      );
    });
  });

  group('a download', () {
    late HttpServer server;

    setUpAll(() async {
      await AppLocalizations.load(const Locale('en'));
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'com.follow.clashx',
        version: '0.5.0',
        buildNumber: '1',
      );
    });

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() => server.close(force: true));

    Future<Response<Uint8List>> fetch() {
      late Future<Response<Uint8List>> pending;
      HttpOverrides.runWithHttpOverrides(() {
        pending = Request().getFileResponseForUrl(
          'http://127.0.0.1:${server.port}/sub',
        );
      }, _RealHttpOverrides());
      return pending;
    }

    test('that answers with part of the file is refused', () async {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-11/2000')
          ..write('proxies: []\n');
        unawaited(request.response.close());
      });

      await expectLater(
        fetch(),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            HttpStatus.partialContent,
          ),
        ),
      );
    });

    test('larger than the cap is refused before it is read', () async {
      server.listen((request) {
        request.response
          ..contentLength = maxDownloadBytes + 1
          ..add(Uint8List(256 << 10));
        // Held open: the client is to hang up on the declared length alone.
        unawaited(request.response.flush().catchError((_) {}));
      });

      await expectLater(
        fetch(),
        throwsA(
          isA<MessageException>().having(
            (e) => e.message,
            'message',
            currentAppLocalizations.downloadTooLarge,
          ),
        ),
      );
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });
}
