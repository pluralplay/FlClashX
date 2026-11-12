import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/path.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';

typedef LegacyConfig = ({
  Map<String, Object?> config,
  Map<String, Object?>? clashConfig,
});

/// FlClashX 0.4 on macOS ran as `com.follow.clash`, the bundle id upstream
/// FlClash still uses; 0.5 is `com.follow.clashx` and starts on empty data.
const _legacyMacosDomain = 'com.follow.clash';

Future<LegacyConfig?> importMacosLegacyConfig() async {
  if (!Platform.isMacOS) {
    return null;
  }
  final home = await appPath.homeDirPath;
  return importLegacyConfig(
    readKey: (key) => _readDefault(_legacyMacosDomain, 'flutter.$key'),
    legacyHome: join(dirname(home), _legacyMacosDomain),
    home: home,
  );
}

@visibleForTesting
Future<LegacyConfig?> importLegacyConfig({
  required Future<String?> Function(String key) readKey,
  required String legacyHome,
  required String home,
}) async {
  if (equals(legacyHome, home)) {
    return null;
  }
  final config = _decode(await readKey(configKey));
  if (config == null || !isFlClashX04Config(config)) {
    return null;
  }
  await _copyProfiles(
    Directory(join(legacyHome, profilesDirectoryName)),
    join(home, profilesDirectoryName),
  );
  return (config: config, clashConfig: _decode(await readKey(clashConfigKey)));
}

/// Upstream FlClash saved the same `proxiesStyle`; only the fork's own
/// override switches, serialized in every 0.4.x, tell its config apart.
@visibleForTesting
bool isFlClashX04Config(Map<String, Object?> config) {
  final appSetting = config['appSetting'];
  return config['proxiesStyle'] != null &&
      appSetting is Map &&
      appSetting.containsKey('overrideProviderSettings');
}

Map<String, Object?>? _decode(String? raw) {
  if (raw == null) {
    return null;
  }
  try {
    final decoded = json.decode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Future<void> _copyProfiles(Directory source, String targetPath) async {
  if (!await source.exists()) {
    return;
  }
  await for (final entity in source.list(followLinks: false)) {
    if (entity is! File || extension(entity.path) != '.yaml') {
      continue;
    }
    final target = File(join(targetPath, basename(entity.path)));
    if (await target.exists()) {
      continue;
    }
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

Future<String?> _readDefault(String domain, String key) async {
  try {
    final result = await Process.run('/usr/bin/defaults', [
      'read',
      domain,
      key,
    ]);
    return result.exitCode == 0 ? result.stdout as String : null;
  } catch (_) {
    return null;
  }
}
