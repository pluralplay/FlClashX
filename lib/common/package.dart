import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get displayVersion =>
      appVersionDefine.isNotEmpty ? appVersionDefine : version;

  /// `FlClashX/v<app> core/<mihomo> Platform/<os>`; the core token is left
  /// out until a version is known.
  String uaWith(String coreVersion) => [
    '$appName/v$displayVersion',
    if (coreVersion.isNotEmpty) 'core/$coreVersion',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

int compareVersions(String version1, String version2) {
  final (core1, pre1, build1) = _versionParts(version1);
  final (core2, pre2, build2) = _versionParts(version2);
  for (var index = 0; index < 3; index++) {
    final part1 = index < core1.length ? core1[index] : 0;
    final part2 = index < core2.length ? core2[index] : 0;
    if (part1 != part2) {
      return part1.compareTo(part2);
    }
  }
  final prerelease = _comparePrereleases(pre1, pre2);
  if (prerelease != 0) {
    return prerelease;
  }
  return build1.compareTo(build2);
}

(List<int>, String?, int) _versionParts(String version) {
  final [main, ...build] = version.split('+');
  final dash = main.indexOf('-');
  final core = dash == -1 ? main : main.substring(0, dash);
  return (
    core.split('.').map(int.parse).toList(),
    dash == -1 ? null : main.substring(dash + 1),
    build.isEmpty ? 0 : int.parse(build.first),
  );
}

/// SemVer precedence: `0.5.0-pre.9` comes before `0.5.0-pre.10` and both
/// before `0.5.0`.
int _comparePrereleases(String? pre1, String? pre2) {
  if (pre1 == pre2) {
    return 0;
  }
  if (pre1 == null || pre2 == null) {
    return pre1 == null ? 1 : -1;
  }
  final ids1 = pre1.split('.');
  final ids2 = pre2.split('.');
  for (var index = 0; index < ids1.length && index < ids2.length; index++) {
    final number1 = int.tryParse(ids1[index]);
    final number2 = int.tryParse(ids2[index]);
    final result = number1 != null && number2 != null
        ? number1.compareTo(number2)
        : ids1[index].compareTo(ids2[index]);
    if (result != 0) {
      return result;
    }
  }
  return ids1.length.compareTo(ids2.length);
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
