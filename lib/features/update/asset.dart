import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const updateHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// The largest download the app accepts, whatever the release claims.
const updateSizeCeiling = 512 * 1024 * 1024;

/// How this copy of the app was installed, which decides what replaces it.
enum UpdateInstallKind {
  android,
  windows,
  macos,
  appImage,
  deb,
  rpm,
  packageManager,
  unsupported,
}

enum UpdateErrorKind {
  noAsset,
  noChecksum,
  untrustedHost,
  tooLarge,
  incomplete,
  network,
  checksumMismatch,
  identityMismatch,
  notNewer,
  busy,
  safeMode,
  installPermission,
  installFailed,
}

final class UpdateException implements Exception {
  final UpdateErrorKind kind;
  final String? detail;

  const UpdateException(this.kind, [this.detail]);

  @override
  String toString() => detail == null ? kind.name : '${kind.name}: $detail';
}

@immutable
class UpdateTarget {
  final UpdateInstallKind kind;

  /// Architectures in the order they are tried, as release assets name them.
  final List<String> archs;

  const UpdateTarget(this.kind, this.archs);

  bool get downloads => archs.isNotEmpty && assetName(archs.first) != null;

  String? assetName(String arch) => switch (kind) {
    UpdateInstallKind.android => 'FlClashX-android-$arch.apk',
    UpdateInstallKind.windows => 'FlClashX-windows-$arch-setup.exe',
    UpdateInstallKind.macos => 'FlClashX-macos-$arch.dmg',
    UpdateInstallKind.appImage => 'FlClashX-linux-$arch.AppImage',
    UpdateInstallKind.deb => 'FlClashX-linux-$arch.deb',
    UpdateInstallKind.rpm => 'FlClashX-linux-$arch.rpm',
    UpdateInstallKind.packageManager || UpdateInstallKind.unsupported => null,
  };
}

@immutable
class UpdateAsset {
  final String name;
  final Uri url;

  final Uri? checksumUrl;
  final String? checksum;
  final int? size;
  final Set<String> allowedHosts;

  const UpdateAsset({
    required this.name,
    required this.url,
    this.checksumUrl,
    this.checksum,
    this.size,
    this.allowedHosts = updateHosts,
  });

  int get sizeLimit => size ?? updateSizeCeiling;
}

bool isAllowedUpdateUri(Uri uri, {Set<String> hosts = updateHosts}) =>
    uri.scheme == 'https' &&
    hosts.contains(uri.host.toLowerCase()) &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443);

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// A provider manifest's binary may sit on any HTTPS host: its inline hash,
/// from the trusted manifest, vouches for it.
UpdateAsset manifestUpdateAsset(
  Map<String, dynamic> manifest,
  UpdateTarget target,
) {
  final listed = manifest['assets'];
  final assets = <String, Map>{
    if (listed is List)
      for (final asset in listed)
        if (asset is Map && asset['name'] is String)
          asset['name'] as String: asset,
  };
  for (final arch in target.archs) {
    final name = target.assetName(arch);
    final asset = name == null ? null : assets[name];
    if (name == null || asset == null) {
      continue;
    }
    final rawUrl = asset['url'];
    final uri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw UpdateException(UpdateErrorKind.untrustedHost, '$rawUrl');
    }
    final sha = asset['sha256'];
    if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
      throw UpdateException(UpdateErrorKind.noChecksum, name);
    }
    return UpdateAsset(
      name: name,
      url: uri,
      checksum: sha.toLowerCase(),
      allowedHosts: {uri.host.toLowerCase()},
    );
  }
  throw const UpdateException(UpdateErrorKind.noAsset);
}

/// Android ABIs as `Build.SUPPORTED_ABIS` lists them, mapped onto the split
/// APKs a release carries, with the universal one last.
List<String> androidUpdateArchs(List<String> supportedAbis) => [
  for (final abi in supportedAbis)
    if (const {'arm64-v8a', 'armeabi-v7a', 'x86_64'}.contains(abi)) abi,
  'universal',
];

final _tagPattern = RegExp(r'^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$');

/// The tag decides the channel when the release itself does not say: only a
/// pre-release tag carries a suffix.
bool releaseMatchesChannel(Map<String, dynamic> release, {required bool pre}) {
  final tag = release['tag_name'];
  if (tag is! String || !_tagPattern.hasMatch(tag)) {
    return false;
  }
  final flagged = release['prerelease'];
  final isPre = flagged is bool ? flagged : tag.contains('-');
  return isPre == pre && tag.contains('-') == pre;
}

Uri releasePageOf(Map<String, dynamic> release, {required String repository}) {
  final page = Uri.tryParse('${release['html_url']}');
  if (page != null && isAllowedUpdateUri(page) && page.host == 'github.com') {
    return page;
  }
  final tag = release['tag_name'];
  return Uri.parse(
    tag is String && _tagPattern.hasMatch(tag)
        ? 'https://github.com/$repository/releases/tag/$tag'
        : 'https://github.com/$repository/releases',
  );
}

UpdateAsset selectUpdateAsset(
  Map<String, dynamic> release,
  UpdateTarget target, {
  required String repository,
  required bool pre,
}) {
  if (!releaseMatchesChannel(release, pre: pre)) {
    throw const UpdateException(UpdateErrorKind.noAsset, 'channel');
  }
  final tag = release['tag_name'] as String;
  final listed = release['assets'];
  if (listed is! List) {
    return _assetFromTag(target, repository: repository, tag: tag);
  }
  final assets = <String, Map>{
    for (final asset in listed)
      if (asset is Map && asset['name'] is String)
        asset['name'] as String: asset,
  };
  for (final arch in target.archs) {
    final name = target.assetName(arch);
    final asset = assets[name];
    if (name == null || asset == null) {
      continue;
    }
    final checksum = assets['$name.sha256'];
    if (checksum == null) {
      throw UpdateException(UpdateErrorKind.noChecksum, name);
    }
    final size = asset['size'];
    if (size is int && size > updateSizeCeiling) {
      throw UpdateException(UpdateErrorKind.tooLarge, name);
    }
    return UpdateAsset(
      name: name,
      url: _assetUri(asset, name),
      checksumUrl: _assetUri(checksum, '$name.sha256'),
      size: size is int && size > 0 ? size : null,
    );
  }
  throw const UpdateException(UpdateErrorKind.noAsset);
}

UpdateAsset _assetFromTag(
  UpdateTarget target, {
  required String repository,
  required String tag,
}) {
  final name = target.assetName(target.archs.firstOrNull ?? '');
  if (name == null) {
    throw const UpdateException(UpdateErrorKind.noAsset);
  }
  final base = 'https://github.com/$repository/releases/download/$tag';
  return UpdateAsset(
    name: name,
    url: Uri.parse('$base/$name'),
    checksumUrl: Uri.parse('$base/$name.sha256'),
  );
}

Uri _assetUri(Map asset, String name) {
  final raw = asset['browser_download_url'];
  final uri = raw is String ? Uri.tryParse(raw) : null;
  if (uri == null ||
      !isAllowedUpdateUri(uri) ||
      uri.pathSegments.lastOrNull != name) {
    throw UpdateException(UpdateErrorKind.untrustedHost, '$raw');
  }
  return uri;
}

final _gnuLine = RegExp(r'^([0-9a-fA-F]{64})(?:\s+\*?(.+))?$');
final _bsdLine = RegExp(r'^SHA256 \((.+)\) = ([0-9a-fA-F]{64})$');

/// Reads `sha256sum` and BSD `shasum` output. A line naming another file is
/// skipped; a lone hash counts only when nothing names [assetName].
String? parseChecksum(String text, String assetName) {
  String? bare;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.replaceFirst('﻿', '').trim();
    final String hash;
    final String? name;
    if (_gnuLine.firstMatch(line) case final match?) {
      hash = match.group(1)!;
      name = match.group(2)?.trim();
    } else if (_bsdLine.firstMatch(line) case final match?) {
      hash = match.group(2)!;
      name = match.group(1);
    } else {
      continue;
    }
    if (name == null) {
      bare ??= hash.toLowerCase();
    } else if (p.posix.basename(name.replaceAll(r'\', '/')) == assetName) {
      return hash.toLowerCase();
    }
  }
  return bare;
}
