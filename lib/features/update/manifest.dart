import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/package.dart';

const _maxRedirects = 5;

final _stableTag = RegExp(r'^v\d+\.\d+\.\d+$');
final _preTag = RegExp(r'^v\d+\.\d+\.\d+-pre\.\d+$');

final class UpdateManifestException implements Exception {
  final String reason;

  const UpdateManifestException(this.reason);

  @override
  String toString() => 'update manifest rejected: $reason';
}

/// Null when the manifest offers nothing newer than [currentVersion].
Future<Map<String, dynamic>?> fetchManifestUpdate(
  Dio dio,
  Uri url, {
  required String currentVersion,
  required bool pre,
}) async {
  final manifest = checkUpdateManifest(
    await _fetchManifest(dio, url),
    pre: pre,
  );
  final version = manifest['version'] as String;
  if (compareVersions(version.substring(1), currentVersion) <= 0) {
    return null;
  }
  return {...manifest, 'tag_name': version, '_isManifest': true};
}

/// The version must be one of this channel's own tags: a pre-release installs
/// as a separate app, so neither channel may hand the other a build.
Map<String, dynamic> checkUpdateManifest(Object? json, {required bool pre}) {
  if (json is! Map<String, dynamic>) {
    throw const UpdateManifestException('not a JSON object');
  }
  final version = json['version'];
  if (version is! String ||
      !(_stableTag.hasMatch(version) || _preTag.hasMatch(version))) {
    throw UpdateManifestException('malformed version $version');
  }
  if (_preTag.hasMatch(version) != pre) {
    throw UpdateManifestException('$version is for the other channel');
  }
  return json;
}

Future<Object?> _fetchManifest(Dio dio, Uri url) async {
  var current = url;
  for (var hop = 0; hop <= _maxRedirects; hop++) {
    if (!current.isScheme('https')) {
      throw UpdateManifestException('not https: $current');
    }
    final response = await dio.getUri<String>(
      current,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == HttpStatus.ok) {
      try {
        return jsonDecode(response.data ?? '');
      } on FormatException {
        throw const UpdateManifestException('not JSON');
      }
    }
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (status < 300 || status >= 400 || location == null) {
      throw UpdateManifestException('HTTP $status');
    }
    current = current.resolve(location);
  }
  throw const UpdateManifestException('too many redirects');
}
