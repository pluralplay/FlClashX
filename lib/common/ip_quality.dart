import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

typedef IpQualityFailure = ({
  IpQualitySource source,
  IpQualitySourceStatus status,
});

class IpQualityLookupException implements Exception {
  const IpQualityLookupException(this.failures);

  final List<IpQualityFailure> failures;
}

class _SourceFailure implements Exception {
  const _SourceFailure(this.status);

  final IpQualitySourceStatus status;
}

typedef _Answer = ({IpQuality quality, bool inferred});

/// Kept as waves so a second source can be hedged in again without
/// touching the lookup; ipinfo.io answers alone today.
const _waves = [
  [IpQualitySource.ipInfo],
];

Future<IpQuality> lookupIpQuality(
  Dio dio,
  String ip, {
  required CancelToken cancelToken,
  Duration timeout = const Duration(seconds: 8),
  Duration hedge = const Duration(seconds: 1),
}) {
  return _Lookup(dio, ip, cancelToken, timeout, hedge).run();
}

class _Lookup {
  _Lookup(this.dio, this.ip, this.cancelToken, this.timeout, this.hedge);

  final Dio dio;
  final String ip;
  final CancelToken cancelToken;
  final Duration timeout;
  final Duration hedge;

  final _completer = Completer<IpQuality>();
  final _failures = <IpQualityFailure>[];
  IpQuality? _fallback;
  int _wave = 0;
  int _inFlight = 0;
  Timer? _timer;

  Future<IpQuality> run() {
    _launch();
    return _completer.future;
  }

  void _launch() {
    _timer?.cancel();
    if (_completer.isCompleted) {
      return;
    }
    if (_wave == _waves.length) {
      _settle();
      return;
    }
    final sources = _waves[_wave++];
    _inFlight += sources.length;
    for (final source in sources) {
      unawaited(
        _query(
          dio,
          source,
          ip,
          cancelToken,
          timeout,
        ).then(_onAnswer, onError: (Object error) => _onError(source, error)),
      );
    }
    if (_wave < _waves.length) {
      _timer = Timer(hedge, _launch);
    }
  }

  void _onAnswer(_Answer answer) {
    _inFlight--;
    if (_completer.isCompleted) {
      return;
    }
    if (answer.inferred) {
      _fallback ??= answer.quality;
      _advance();
      return;
    }
    _timer?.cancel();
    _completer.complete(answer.quality);
    cancelToken.cancel();
  }

  void _onError(IpQualitySource source, Object error) {
    _inFlight--;
    if (_completer.isCompleted) {
      return;
    }
    _failures.add((source: source, status: _statusOf(error)));
    _advance();
  }

  void _advance() {
    if (_inFlight == 0) {
      _launch();
    }
  }

  void _settle() {
    if (_inFlight > 0) {
      return;
    }
    final fallback = _fallback;
    if (fallback != null) {
      _completer.complete(fallback);
      return;
    }
    _failures.sort((a, b) => a.source.index.compareTo(b.source.index));
    _completer.completeError(IpQualityLookupException(_failures));
  }
}

Future<_Answer> _query(
  Dio dio,
  IpQualitySource source,
  String ip,
  CancelToken cancelToken,
  Duration timeout,
) async {
  final response = await dio
      .get<String>(
        _urlOf(source, ip),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      )
      .timeout(timeout);
  if (response.statusCode == HttpStatus.tooManyRequests) {
    throw const _SourceFailure(IpQualitySourceStatus.rateLimited);
  }
  if (response.statusCode != HttpStatus.ok) {
    throw const _SourceFailure(IpQualitySourceStatus.failed);
  }
  final json = jsonDecode(response.data ?? '') as Map<String, dynamic>;
  final answer = _parse(source, ip, json);
  if (answer == null) {
    throw const _SourceFailure(IpQualitySourceStatus.noType);
  }
  return answer;
}

IpQualitySourceStatus _statusOf(Object error) {
  return switch (error) {
    _SourceFailure(:final status) => status,
    TimeoutException() => IpQualitySourceStatus.timeout,
    DioException(
      type: DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout,
    ) =>
      IpQualitySourceStatus.timeout,
    _ => IpQualitySourceStatus.failed,
  };
}

String _urlOf(IpQualitySource source, String ip) {
  return switch (source) {
    IpQualitySource.ipInfo => 'https://ipinfo.io/$ip/json',
  };
}

_Answer? _parse(IpQualitySource source, String ip, Map<String, dynamic> json) {
  return switch (source) {
    IpQualitySource.ipInfo => _fromIpInfo(ip, json),
  };
}

/// The free plan answers with `org` as "AS64500 Name" and nothing about the
/// network's kind; a token adds `asn`, `company` and `privacy`, which win
/// when present. Without them the kind is read off the names, and silence
/// counts as residential.
_Answer? _fromIpInfo(String ip, Map<String, dynamic> json) {
  if (_flag(json['bogon'])) {
    throw const _SourceFailure(IpQualitySourceStatus.failed);
  }
  if (json['ip'] != ip) {
    throw const _SourceFailure(IpQualitySourceStatus.ipMismatch);
  }
  final privacy = _object(json['privacy']);
  final company = _object(json['company']);
  final asn = _object(json['asn']);
  final org = _text(json['org']);
  final organization =
      _text(company['name']) ??
      _text(asn['name']) ??
      org?.replaceFirst(RegExp(r'^AS\d+\s+'), '');
  final declared =
      _pickType(
        hosting: _flag(privacy['hosting']),
        declared: _declaredType(company['type']) ?? _declaredType(asn['type']),
      ) ??
      _typeFromNames(organization, _text(json['hostname']));
  return _quality(
    ip,
    IpQualitySource.ipInfo,
    declared ?? IpType.residential,
    inferred: declared == null,
    organization: organization,
    asn: _asn(asn['asn']) ?? _asn(org),
    isProxy: _flag(privacy['proxy']),
    isVpn: _flag(privacy['vpn']) || _flag(privacy['relay']),
    isTor: _flag(privacy['tor']),
  );
}

final _hostingNames = RegExp(
  r'host|cloud|server|data ?cent|vps|colo|cdn|amazon|aws|azure|microsoft|google'
  r'|digitalocean|linode|akamai|vultr|hetzner|ovh|contabo|scaleway|selectel'
  r'|timeweb|leaseweb|oracle|alibaba|tencent|netcup|ionos|hostinger|cloudflare',
  caseSensitive: false,
);

final _mobileNames = RegExp(
  r'mobile|cellular|wireless|\bmts\b|megafon|beeline|tele2|vodafone|t-mobile'
  r'|telefonica|yota|kyivstar|lifecell|\blte\b|\b[345]g\b',
  caseSensitive: false,
);

IpType? _typeFromNames(String? organization, String? hostname) {
  final names = [?organization, ?hostname].join(' ');
  if (names.isEmpty) {
    return null;
  }
  if (_hostingNames.hasMatch(names)) {
    return IpType.hosting;
  }
  if (_mobileNames.hasMatch(names)) {
    return IpType.mobile;
  }
  return null;
}

/// An inferred type is the source's silence about hosting and mobile taken
/// as residential; it only stands in when no source states a type.
_Answer? _quality(
  String ip,
  IpQualitySource source,
  IpType? type, {
  bool inferred = false,
  String? organization,
  int? asn,
  bool isProxy = false,
  bool isVpn = false,
  bool isTor = false,
  bool isAbuser = false,
}) {
  if (type == null) {
    return null;
  }
  final quality = IpQuality(
    ip: ip,
    source: source,
    type: type,
    organization: organization,
    asn: asn,
    isProxy: isProxy,
    isVpn: isVpn,
    isTor: isTor,
    isAbuser: isAbuser,
  );
  return (quality: quality, inferred: inferred);
}

IpType? _pickType({
  required bool hosting,
  bool mobile = false,
  IpType? declared,
}) {
  if (hosting || declared == IpType.hosting) {
    return IpType.hosting;
  }
  if (mobile) {
    return IpType.mobile;
  }
  return declared;
}

IpType? _declaredType(Object? value) {
  return switch (value) {
    'isp' => IpType.residential,
    'business' || 'education' || 'government' || 'banking' => IpType.business,
    'hosting' => IpType.hosting,
    _ => null,
  };
}

Map<String, dynamic> _object(Object? value) {
  return value is Map<String, dynamic> ? value : const {};
}

bool _flag(Object? value) => value == true;

String? _text(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int? _asn(Object? value) {
  final asn = switch (value) {
    final int number => number,
    final String text => int.tryParse(
      RegExp(r'\d+').firstMatch(text)?[0] ?? '',
    ),
    _ => null,
  };
  return asn == 0 ? null : asn;
}
