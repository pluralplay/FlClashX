import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/package.dart';
import 'package:fl_clash/features/update/manifest_signature.dart';

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
  List<String> keys = updateManifestKeys,
}) async {
  final manifest = await verifyUpdateManifest(
    await _fetchManifest(dio, url),
    pre: pre,
    keys: keys,
  );
  final version = manifest['version'] as String;
  if (compareVersions(version.substring(1), currentVersion) <= 0) {
    return null;
  }
  return {...manifest, 'tag_name': version, '_isManifest': true};
}

/// The version must be one of this channel's own tags: a pre-release installs
/// as a separate app, so neither channel may hand the other a build. Only
/// the signed fields and the asset URLs are passed on.
Future<Map<String, dynamic>> verifyUpdateManifest(
  Object? json, {
  required bool pre,
  List<String> keys = updateManifestKeys,
}) async {
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
  final assets = json['assets'];
  if (assets is! List) {
    throw const UpdateManifestException('no asset list');
  }
  final List<int> message;
  try {
    message = updateManifestMessage(version, [
      for (final asset in assets)
        if (asset case {
          'name': final String name,
          'sha256': final String sha256,
        })
          (name: name, sha256: sha256)
        else
          throw const FormatException('malformed asset'),
    ]);
  } on FormatException catch (error) {
    throw UpdateManifestException('${error.message} ${error.source ?? ''}');
  }
  final signature = json['signature'];
  if (signature is! String ||
      !await verifyUpdateManifestSignature(message, signature, keys: keys)) {
    throw const UpdateManifestException('bad signature');
  }
  return {
    'version': version,
    'assets': [
      for (final asset in assets.cast<Map>())
        {'name': asset['name'], 'url': asset['url'], 'sha256': asset['sha256']},
    ],
  };
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
