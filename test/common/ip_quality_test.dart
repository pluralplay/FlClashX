import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/ip_quality.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _ip = '203.0.113.9';
const _host = 'ipinfo.io';

typedef _Reply = ({int status, Object? body, Duration delay});

_Reply _ok(Object body, [Duration delay = Duration.zero]) =>
    (status: 200, body: body, delay: delay);

_Reply _status(int status) =>
    (status: status, body: null, delay: Duration.zero);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.replies);

  final Map<String, _Reply> replies;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requested.add(options.uri);
    final reply = replies[options.uri.host] ?? _status(503);
    final completer = Completer<ResponseBody>();
    final timer = Timer(reply.delay, () {
      completer.complete(
        ResponseBody.fromString(
          reply.body == null ? '' : jsonEncode(reply.body),
          reply.status,
        ),
      );
    });
    cancelFuture?.then((_) {
      if (completer.isCompleted) {
        return;
      }
      timer.cancel();
      completer.completeError(
        DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        ),
      );
    });
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}

({_Adapter adapter, Future<IpQuality> result}) _lookup(
  Map<String, _Reply> replies, {
  Duration timeout = const Duration(seconds: 8),
}) {
  final adapter = _Adapter(replies);
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(dio.close);
  return (
    adapter: adapter,
    result: lookupIpQuality(
      dio,
      _ip,
      cancelToken: CancelToken(),
      timeout: timeout,
    ),
  );
}

Future<void> _expectFailure(
  Map<String, _Reply> replies,
  IpQualitySourceStatus status, {
  Duration timeout = const Duration(seconds: 8),
}) {
  return expectLater(
    _lookup(replies, timeout: timeout).result,
    throwsA(
      isA<IpQualityLookupException>().having(
        (error) => error.failures,
        'failures',
        [(source: IpQualitySource.ipInfo, status: status)],
      ),
    ),
  );
}

void main() {
  test('asks ipinfo.io about the target address, and nothing else', () async {
    final lookup = _lookup({});
    await expectLater(lookup.result, throwsA(isA<IpQualityLookupException>()));
    expect(lookup.adapter.requested.map((uri) => uri.toString()), [
      'https://ipinfo.io/$_ip/json',
    ]);
  });

  test(
    'reads the network off the free plan and takes it as residential',
    () async {
      final lookup = _lookup({
        _host: _ok({
          'ip': _ip,
          'hostname': 'cpe.example.net',
          'country': 'GB',
          'org': 'AS64500 Example Broadband',
        }),
      });

      expect(
        await lookup.result,
        const IpQuality(
          ip: _ip,
          source: IpQualitySource.ipInfo,
          type: IpType.residential,
          organization: 'Example Broadband',
          asn: 64500,
        ),
      );
    },
  );

  test('prefers the token plan details and flags over the names', () async {
    final lookup = _lookup({
      _host: _ok({
        'ip': _ip,
        'org': 'AS64501 Example Cloud',
        'asn': {'asn': 'AS64501', 'name': 'Example Cloud', 'type': 'hosting'},
        'company': {'name': 'Example Cloud Ltd', 'type': 'hosting'},
        'privacy': {
          'vpn': true,
          'proxy': false,
          'tor': false,
          'relay': false,
          'hosting': true,
        },
      }),
    });

    expect(
      await lookup.result,
      const IpQuality(
        ip: _ip,
        source: IpQualitySource.ipInfo,
        type: IpType.hosting,
        organization: 'Example Cloud Ltd',
        asn: 64501,
        isVpn: true,
      ),
    );
  });

  test('counts a private relay as a VPN', () async {
    final lookup = _lookup({
      _host: _ok({
        'ip': _ip,
        'org': 'AS64500 Example Broadband',
        'company': {'name': 'Example Broadband', 'type': 'isp'},
        'privacy': {'relay': true},
      }),
    });

    final quality = await lookup.result;
    expect(quality.type, IpType.residential);
    expect(quality.isVpn, isTrue);
  });

  group('without plan details, the names tell', () {
    test('a hosting provider', () async {
      final lookup = _lookup({
        _host: _ok({'ip': _ip, 'org': 'AS64502 Hetzner Online GmbH'}),
      });
      expect((await lookup.result).type, IpType.hosting);
    });

    test('a cloud host by its reverse name', () async {
      final lookup = _lookup({
        _host: _ok({
          'ip': _ip,
          'hostname': 'ec2-203-0-113-9.compute-1.amazonaws.com',
          'org': 'AS64504 Example Leasing',
        }),
      });
      expect((await lookup.result).type, IpType.hosting);
    });

    test('a mobile carrier', () async {
      final lookup = _lookup({
        _host: _ok({'ip': _ip, 'org': 'AS64503 MTS PJSC'}),
      });
      expect((await lookup.result).type, IpType.mobile);
    });
  });

  test('reports a bogon address as a failure', () {
    return _expectFailure({
      _host: _ok({'ip': _ip, 'bogon': true}),
    }, IpQualitySourceStatus.failed);
  });

  test('reports an answer about another address', () {
    return _expectFailure({
      _host: _ok({'ip': '198.51.100.1', 'org': 'AS64500 Example'}),
    }, IpQualitySourceStatus.ipMismatch);
  });

  test('reports the free quota running out', () {
    return _expectFailure({
      _host: _status(429),
    }, IpQualitySourceStatus.rateLimited);
  });

  test('reports a slow answer as a timeout', () {
    return _expectFailure(
      {
        _host: _ok({
          'ip': _ip,
          'org': 'AS64500 Example',
        }, const Duration(milliseconds: 300)),
      },
      IpQualitySourceStatus.timeout,
      timeout: const Duration(milliseconds: 100),
    );
  });
}
