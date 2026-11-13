import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _appName = 'FlClashX';
const _bundleId = 'com.follow.clashx';
const _distDir = 'dist';

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb,appimage,rpm',
  'macos': 'dmg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _androidAbi = {
  'arm': 'armeabi-v7a',
  'arm64': 'arm64-v8a',
  'amd64': 'x86_64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final skipped = packagesNotBuildingAssets(
    File(p.join(rootDir, 'pubspec.yaml')).readAsStringSync(),
  );
  if (skipped.isNotEmpty) {
    stderr.writeln(
      'pubspec.yaml sets hooks.user_defines.<package>.build_assets: false '
      'for ${skipped.join(', ')}; a package built this way would ship '
      'whatever is left in libclash/ and no Rust library. '
      'Restore "build_assets: true".',
    );
    exit(1);
  }
  final arch = results['arch'] as String? ?? _detectArch();
  final targets = createPackageTargets(platform, results['targets']);
  final androidArch = platform == 'android' ? results['arch'] as String? : null;
  final verbose = results['verbose'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['dev', 'pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,deb,rpm,appimage',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help:
          'Target architecture: one Android ABI (default: every ABI and a '
          'universal APK), or the desktop architecture (default: the host)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

/// The flutter_distributor-style build arguments, without their dashes.
List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  return flutterBuildArgs;
}

Map<String, String> createBuildEnvironment(String env) {
  return {'APP_ENV': env};
}

/// The versions a build carries into the app: the release tag it was made
/// from, with its `-pre.N`, and the mihomo release its core was linked with.
List<String> createBuildDefines({
  required String appVersion,
  required String coreVersion,
}) => [
  '--dart-define=APP_VERSION=$appVersion',
  if (coreVersion.isNotEmpty) '--dart-define=CORE_VERSION=$coreVersion',
];

/// The tag CI builds from when it is a release tag, else the pubspec version.
String appVersionOf({
  required String pubspecVersion,
  Map<String, String> environment = const {},
}) {
  final ref = environment['GITHUB_REF_NAME'] ?? '';
  if (RegExp(r'^v\d').hasMatch(ref)) {
    return ref.substring(1);
  }
  return pubspecVersion;
}

/// Packages whose build hook `pubspec.yaml` turns into a no-op.
List<String> packagesNotBuildingAssets(String pubspec) {
  final document = loadYaml(pubspec);
  if (document is! Map) return const [];
  final defines = (document['hooks'] as Map?)?['user_defines'];
  if (defines is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in defines.entries)
      if (value is Map && value['build_assets'] == false) key.toString(),
  ]..sort();
}

String createPackageTargets(String platform, String? customTargets) {
  return customTargets ?? _allTargets[platform]!;
}

/// What `macos/Runner/Configs/Channel.xcconfig` holds for [env]: a
/// pre-release gets its own bundle id and name, so it installs beside the
/// stable app; null for every other build, which goes without the file.
String? macosChannelConfig(String env) => env == 'pre'
    ? 'PRODUCT_BUNDLE_IDENTIFIER = com.follow.clashx.pre\n'
          'APP_DISPLAY_NAME = $_appName Pre\n'
    : null;

/// The `.app` name a DMG of [env] installs, kept apart from the stable one in
/// `/Applications`.
String macosBundleName(String env) =>
    env == 'pre' ? '$_appName Pre.app' : '$_appName.app';

/// The app and the Helper derive their system names from these executables'.
class DesktopIdentity {
  const DesktopIdentity({
    required this.pre,
    required this.executable,
    required this.helper,
    required this.displayName,
    required this.bundleId,
    required this.packageName,
    required this.installDir,
    required this.helperUnit,
    required this.windowsDataDir,
  });

  final bool pre;
  final String executable;
  final String helper;
  final String displayName;
  final String bundleId;
  final String packageName;
  final String installDir;
  final String helperUnit;
  final String windowsDataDir;
}

const stableDesktop = DesktopIdentity(
  pre: false,
  executable: _appName,
  helper: 'FlClashXHelperService',
  displayName: _appName,
  bundleId: _bundleId,
  packageName: 'flclashx',
  installDir: _appName,
  helperUnit: 'flclashx-helper',
  windowsDataDir: r'com.follow\clashx',
);

const preDesktop = DesktopIdentity(
  pre: true,
  executable: 'FlClashXPre',
  helper: 'FlClashXPreHelperService',
  displayName: '$_appName Pre',
  bundleId: '$_bundleId.pre',
  packageName: 'flclashx-pre',
  installDir: 'FlClashXPre',
  helperUnit: 'flclashx-pre-helper',
  windowsDataDir: r'com.follow\clashx.pre',
);

const _preWindowsAppId = '3B6E2F0A-9C41-4D57-8A2E-7F1D5C0B9E63';

DesktopIdentity desktopIdentityOf(String env) =>
    env == 'pre' ? preDesktop : stableDesktop;

Map<String, String> desktopBuildEnvironment(String env) => {
  'FLCLASHX_CHANNEL': env,
};

List<String> channelScripts(List<String> scripts, DesktopIdentity identity) => [
  for (final line in scripts)
    line.replaceAll(stableDesktop.helperUnit, identity.helperUnit),
];

void renameForChannel(String dir, DesktopIdentity identity, {String ext = ''}) {
  if (!identity.pre) return;
  for (final (from, to) in [
    (stableDesktop.executable, identity.executable),
    (stableDesktop.helper, identity.helper),
  ]) {
    final file = File(p.join(dir, '$from$ext'));
    if (file.existsSync()) file.renameSync(p.join(dir, '$to$ext'));
  }
}

/// Without the channel reaching CMake a pre-release would share stable data.
void requireChannelMarker(String binary, List<int> marker) {
  final bytes = File(binary).readAsBytesSync();
  for (var i = 0; i + marker.length <= bytes.length; i++) {
    var found = true;
    for (var j = 0; j < marker.length; j++) {
      if (bytes[i + j] != marker[j]) {
        found = false;
        break;
      }
    }
    if (found) return;
  }
  throw ProcessException(binary, const [], 'built without its channel', 1);
}

List<int> utf16le(String value) => [
  for (final unit in value.codeUnits) ...[unit & 0xff, unit >> 8],
];

/// `FlClashX-<platform>-<arch>` plus the format's extension; the release
/// templates and the AUR package link these names.
String artifactName(String platform, String arch, String extension) =>
    '$_appName-$platform-$arch$extension';

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default) or android');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

class _Build {
  _Build({
    required this.rootDir,
    required this.platform,
    required this.arch,
    required this.verbose,
  });

  final String rootDir;
  final String platform;
  final String arch;
  final bool verbose;

  late final String version = _readPubspecVersion();
  late final String appVersion = appVersionOf(
    pubspecVersion: version,
    environment: Platform.environment,
  );
  late final String coreVersion = _readCoreVersion();
  late final String distPath = p.join(rootDir, _distDir);

  String _readPubspecVersion() {
    final pubspec = loadYaml(
      File(p.join(rootDir, 'pubspec.yaml')).readAsStringSync(),
    );
    final version = (pubspec as Map)['version'] as String;
    return version.split('+').first;
  }

  String _readCoreVersion() {
    final config = loadYaml(
      File(p.join(rootDir, 'build_config.yaml')).readAsStringSync(),
    );
    return ((config as Map?)?['core_version'] as String?) ?? '';
  }

  Map<dynamic, dynamic> packagingConfig(String format) {
    final file = File(
      p.join(rootDir, platform, 'packaging', format, 'make_config.yaml'),
    );
    return (loadYaml(file.readAsStringSync()) as Map?) ?? {};
  }

  List<String> flutterBuildArgs({String? androidArch}) => [
    for (final arg in createFlutterBuildArgs(
      platform: platform,
      verbose: verbose,
    ))
      '--$arg',
    if (androidArch != null)
      '--target-platform=${_androidFlutterTarget[androidArch]!}',
    ...createBuildDefines(appVersion: appVersion, coreVersion: coreVersion),
  ];

  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    stdout.writeln('exec: $executable ${arguments.join(' ')}');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory ?? rootDir,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: Platform.isWindows,
    );
    process.stdout.listen((data) {
      stdout.write(utf8.decode(data, allowMalformed: true));
    });
    process.stderr.listen((data) {
      stderr.write(utf8.decode(data, allowMalformed: true));
    });
    return process.exitCode;
  }

  Future<void> mustRun(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final code = await run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    if (code != 0) {
      throw ProcessException(executable, arguments, 'exit code $code', code);
    }
  }

  String dist(String name) {
    Directory(distPath).createSync(recursive: true);
    return p.join(distPath, name);
  }

  void copy(String from, String to) {
    File(to).parent.createSync(recursive: true);
    File(from).copySync(to);
    stdout.writeln('created: $to');
  }

  Future<void> copyTree(String from, String to) async {
    Directory(to).createSync(recursive: true);
    if (Platform.isWindows) {
      await mustRun('xcopy', [from, to, '/E', '/I', '/Y', '/Q']);
    } else {
      await mustRun('cp', ['-R', '$from/.', to]);
    }
  }
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
}) async {
  final file = File(p.join(rootDir, 'env.json'));
  await file.writeAsString(jsonEncode(createBuildEnvironment(env)));

  final depExit = await _ensureDependencies(platform);
  if (depExit != 0) return depExit;

  final build = _Build(
    rootDir: rootDir,
    platform: platform,
    arch: arch,
    verbose: verbose,
  );
  final wanted = targets.split(',').map((t) => t.trim()).toSet();
  try {
    switch (platform) {
      case 'android':
        await _packageAndroid(build, androidArch: androidArch);
      case 'macos':
        await _packageMacos(build, env: env);
      case 'windows':
        await _packageWindows(build, wanted, env: env);
      case 'linux':
        await _packageLinux(build, wanted, env: env);
    }
  } on ProcessException catch (error) {
    stderr.writeln('${error.executable} failed: ${error.message}');
    return error.errorCode == 0 ? 1 : error.errorCode;
  }
  return 0;
}

Future<void> _packageAndroid(_Build build, {String? androidArch}) async {
  const outputs = 'build/app/outputs/flutter-apk';
  await build.mustRun('flutter', [
    'build',
    'apk',
    '--release',
    ...build.flutterBuildArgs(androidArch: androidArch),
  ]);
  for (final MapEntry(key: arch, value: abi) in _androidAbi.entries) {
    if (androidArch != null && androidArch != arch) continue;
    build.copy(
      p.join(build.rootDir, outputs, 'app-$abi-release.apk'),
      build.dist(artifactName('android', abi, '.apk')),
    );
  }
  if (androidArch != null) return;
  await build.mustRun('flutter', [
    'build',
    'apk',
    '--release',
    for (final arg in build.flutterBuildArgs())
      if (arg != '--split-per-abi') arg,
  ]);
  build.copy(
    p.join(build.rootDir, outputs, 'app-release.apk'),
    build.dist(artifactName('android', 'universal', '.apk')),
  );
}

Future<void> _packageMacos(_Build build, {required String env}) async {
  final channel = File(
    p.join(build.rootDir, 'macos', 'Runner', 'Configs', 'Channel.xcconfig'),
  );
  final channelConfig = macosChannelConfig(env);
  try {
    if (channelConfig == null) {
      if (channel.existsSync()) channel.deleteSync();
    } else {
      channel.writeAsStringSync(channelConfig);
    }
    await build.mustRun('flutter', [
      'build',
      'macos',
      '--release',
      ...build.flutterBuildArgs(),
    ]);
  } finally {
    if (channel.existsSync()) channel.deleteSync();
  }
  final products = p.join(build.rootDir, 'build/macos/Build/Products/Release');
  final built = p.join(products, '$_appName.app');
  final app = p.join(products, macosBundleName(env));
  if (app != built) {
    if (Directory(app).existsSync()) Directory(app).deleteSync(recursive: true);
    Directory(built).renameSync(app);
  }
  final identity = Platform.environment['APPLE_DEVELOPER_ID'] ?? '';
  if (identity.isNotEmpty) {
    await _signMacosApp(build, app, identity);
  }
  final staging = Directory(p.join(build.rootDir, 'build', 'dmg'));
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);
  // Without a signing identity create-dmg still writes the image, then exits
  // non-zero over the signature it could not add.
  final code = await build.run('create-dmg', [
    '--overwrite',
    if (identity.isNotEmpty) '--no-code-sign',
    '--dmg-title',
    p.basenameWithoutExtension(app),
    app,
    staging.path,
  ]);
  final created = staging
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.dmg'))
      .toList();
  if (created.isEmpty || (identity.isNotEmpty && code != 0)) {
    throw ProcessException('create-dmg', const [], 'no DMG was created', code);
  }
  if (identity.isNotEmpty) {
    await _codesign(build, identity, created.first.path);
  } else if (code != 0) {
    stderr.writeln('create-dmg exited with $code; the DMG is unsigned.');
  }
  build.copy(
    created.first.path,
    build.dist(artifactName('macos', build.arch, '.dmg')),
  );
  staging.deleteSync(recursive: true);
}

List<String> macosSigningOrder(String app) {
  final contents = p.join(app, 'Contents');
  List<String> entries(String dir, bool Function(String path) take) {
    final directory = Directory(p.join(contents, dir));
    if (!directory.existsSync()) return [];
    return [
      for (final entry in directory.listSync())
        if (take(entry.path)) entry.path,
    ]..sort();
  }

  return [
    ...entries(
      'Frameworks',
      (path) => path.endsWith('.framework') || path.endsWith('.dylib'),
    ),
    ...entries(
      p.join('Library', 'LoginItems'),
      (path) => path.endsWith('.app'),
    ),
    ...entries('MacOS', (path) => p.basename(path) != _appName),
    app,
  ];
}

Future<void> _signMacosApp(_Build build, String app, String identity) async {
  final entitlements = {
    // Xcode's ad-hoc signature carries get-task-allow, which notarization rejects.
    app: 'Release.entitlements',
    // EasyTier's wazero makes the writable pages it compiled into executable.
    p.join(app, 'Contents', 'MacOS', 'FlClashCore'): 'Core.entitlements',
  };
  for (final code in macosSigningOrder(app)) {
    final file = entitlements[code];
    await _codesign(build, identity, code, [
      '--options=runtime',
      if (file != null) ...[
        '--entitlements',
        p.join(build.rootDir, 'macos', 'Runner', file),
      ] else
        '--preserve-metadata=entitlements',
    ]);
  }
  await build.mustRun('codesign', [
    '--verify',
    '--deep',
    '--strict',
    '--verbose=2',
    app,
  ]);
}

Future<void> _codesign(
  _Build build,
  String identity,
  String path, [
  List<String> options = const [],
]) async {
  final arguments = [
    '--force',
    '--timestamp',
    '--sign',
    identity,
    ...options,
    path,
  ];
  // Apple's timestamp service turns a request away now and then.
  for (var attempt = 1; ; attempt++) {
    final code = await build.run('codesign', arguments);
    if (code == 0) return;
    if (attempt == 3) {
      throw ProcessException('codesign', arguments, 'exit code $code', code);
    }
    await Future<void>.delayed(Duration(seconds: 5 * attempt));
  }
}

Future<void> _packageWindows(
  _Build build,
  Set<String> targets, {
  required String env,
}) async {
  final identity = desktopIdentityOf(env);
  await build.mustRun('flutter', [
    'build',
    'windows',
    '--release',
    ...build.flutterBuildArgs(),
  ], environment: desktopBuildEnvironment(env));
  final winArch = build.arch == 'arm64' ? 'arm64' : 'x64';
  final built = p.join(
    build.rootDir,
    'build',
    'windows',
    winArch,
    'runner',
    'Release',
  );
  var bundle = built;
  if (identity.pre) {
    requireChannelMarker(p.join(built, '$_appName.exe'), utf16le('clashx.pre'));
    bundle = p.join(build.rootDir, 'build', 'windows', winArch, 'pre_bundle');
    if (Directory(bundle).existsSync()) {
      Directory(bundle).deleteSync(recursive: true);
    }
    await build.copyTree(built, bundle);
    renameForChannel(bundle, identity, ext: '.exe');
  }
  if (targets.contains('zip')) {
    final zip = build.dist(artifactName('windows', build.arch, '.zip'));
    if (File(zip).existsSync()) File(zip).deleteSync();
    await build.mustRun('powershell', [
      '-NoProfile',
      '-Command',
      'Compress-Archive -Path "$bundle\\*" -DestinationPath "$zip" -Force',
    ]);
    stdout.writeln('created: $zip');
  }
  if (targets.contains('exe')) {
    final config = build.packagingConfig('exe');
    final script = renderInnoSetup(
      File(
        p.join(build.rootDir, 'windows', 'packaging', 'exe', 'inno_setup.iss'),
      ).readAsStringSync(),
      config: config,
      version: build.version,
      arch: build.arch,
      sourceDir: bundle,
      outputDir: build.distPath,
      outputBaseName: artifactName('windows', build.arch, '-setup'),
      rootDir: build.rootDir,
      identity: identity,
    );
    final scriptFile = File(p.join(build.rootDir, 'build', 'setup.iss'));
    scriptFile.parent.createSync(recursive: true);
    scriptFile.writeAsStringSync(script);
    await build.mustRun(_innoSetupCompiler(), [scriptFile.path]);
    stdout.writeln(
      'created: ${build.dist(artifactName('windows', build.arch, '-setup.exe'))}',
    );
  }
}

String _innoSetupCompiler() {
  const installed = r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe';
  return File(installed).existsSync() ? installed : 'ISCC';
}

const _innoLanguages = {
  'en': 'Name: "english"; MessagesFile: "compiler:Default.isl"',
  'ru': 'Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"',
  // Inno Setup 6 does not ship ChineseSimplified.isl, so the translation is
  // kept next to the template and referenced by its absolute path.
  'zh': 'Name: "chineseSimplified"; MessagesFile: "{{CHINESE_ISL}}"',
  'ja': 'Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"',
  'ko': 'Name: "korean"; MessagesFile: "compiler:Languages\\Korean.isl"',
  'fr': 'Name: "french"; MessagesFile: "compiler:Languages\\French.isl"',
  'es': 'Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"',
};

/// Fills the Inno Setup script from `windows/packaging/exe/make_config.yaml`.
String renderInnoSetup(
  String template, {
  required Map<dynamic, dynamic> config,
  required String version,
  required String arch,
  required String sourceDir,
  required String outputDir,
  required String outputBaseName,
  required String rootDir,
  DesktopIdentity identity = stableDesktop,
}) {
  final displayName = identity.pre
      ? identity.displayName
      : (config['display_name'] ?? _appName) as String;
  final privileges = (config['privileges_required'] ?? 'admin') as String;
  final locales = (config['locales'] as List?) ?? const [];
  final chineseIsl = p.join(
    rootDir,
    'windows',
    'packaging',
    'exe',
    'ChineseSimplified.isl',
  );
  final languages = [
    for (final locale in locales)
      if (locale is Map && _innoLanguages[locale['lang']] != null)
        _innoLanguages[locale['lang']]!.replaceAll(
          '{{CHINESE_ISL}}',
          chineseIsl,
        ),
  ];
  if (languages.isEmpty) languages.add(_innoLanguages['en']!);
  final iconFile = (config['setup_icon_file'] as String?) ?? '';
  final values = {
    'APP_ID': identity.pre ? _preWindowsAppId : config['app_id'] as String,
    'APP_VERSION': version,
    'DISPLAY_NAME': displayName,
    'PUBLISHER_NAME': (config['publisher'] ?? '') as String,
    'PUBLISHER_URL': (config['publisher_url'] ?? '') as String,
    'INSTALL_DIR_NAME': '{autopf}\\$displayName',
    'OUTPUT_DIR': outputDir,
    'OUTPUT_BASE_FILENAME': outputBaseName,
    'SETUP_ICON_FILE': p.isAbsolute(iconFile)
        ? iconFile
        : p.join(rootDir, iconFile),
    'PRIVILEGES_REQUIRED': privileges,
    'ARCH': arch == 'arm64' ? 'arm64' : 'x64compatible',
    'SOURCE_DIR': sourceDir,
    'EXECUTABLE_NAME': identity.pre
        ? '${identity.executable}.exe'
        : (config['executable_name'] ?? '$_appName.exe') as String,
    'HELPER_SERVICE': identity.helper,
    'USER_DATA_DIR': identity.windowsDataDir,
    'ADOPT_LEGACY': identity.pre ? 'False' : 'True',
    'LANGUAGES': languages.join('\n'),
    'RUN_FLAGS': privileges == 'admin' ? 'runascurrentuser' : '',
    'CLEAR_PROXY_SCRIPT': p.join(
      rootDir,
      'windows',
      'packaging',
      'exe',
      'clear_stale_proxy.ps1',
    ),
  };
  var rendered = template;
  values.forEach((key, value) {
    rendered = rendered.replaceAll('{{$key}}', value);
  });
  return rendered;
}

Future<void> _packageLinux(
  _Build build,
  Set<String> targets, {
  required String env,
}) async {
  final identity = desktopIdentityOf(env);
  final flutterArch = build.arch == 'arm64' ? 'arm64' : 'x64';
  await build.mustRun('flutter', [
    'build',
    'linux',
    '--release',
    '--target-platform=linux-$flutterArch',
    ...build.flutterBuildArgs(),
  ], environment: desktopBuildEnvironment(env));
  final bundle = p.join(
    build.rootDir,
    'build',
    'linux',
    flutterArch,
    'release',
    'bundle',
  );
  if (identity.pre) {
    requireChannelMarker(
      p.join(bundle, _appName),
      utf8.encode(identity.bundleId),
    );
  }
  if (targets.contains('deb')) await _packageDeb(build, bundle, identity);
  if (targets.contains('rpm')) await _packageRpm(build, bundle, identity);
  if (targets.contains('appimage')) {
    await _packageAppImage(build, bundle, identity);
  }
}

String desktopEntry(
  Map<dynamic, dynamic> config, {
  required String exec,
  DesktopIdentity identity = stableDesktop,
}) {
  List<String> list(String key) => [
    for (final item in (config[key] as List?) ?? const []) item.toString(),
  ];
  final name = identity.pre
      ? identity.displayName
      : (config['display_name'] ?? _appName) as String;
  return [
    '[Desktop Entry]',
    'Type=Application',
    'Name=$name',
    'GenericName=${config['generic_name'] ?? name}',
    'Comment=$name',
    'Exec=$exec %u',
    'Icon=${identity.executable}',
    'Terminal=false',
    if (list('categories').isNotEmpty)
      'Categories=${list('categories').join(';')};',
    if (list('keywords').isNotEmpty) 'Keywords=${list('keywords').join(';')};',
    if (list('supported_mime_type').isNotEmpty)
      'MimeType=${list('supported_mime_type').join(';')};',
    'StartupNotify=${config['startup_notify'] ?? true}',
    if (config['startup_wm_class'] != null)
      'StartupWMClass=${identity.pre ? identity.bundleId : config['startup_wm_class']}',
    '',
  ].join('\n');
}

List<String> _scripts(Map<dynamic, dynamic> config, String key) => [
  for (final line in (config[key] as List?) ?? const []) line.toString(),
];

void _writeExecutable(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['755', path]);
  }
}

Future<void> _installTree(
  _Build build,
  String root,
  String bundle,
  Map<dynamic, dynamic> config,
  DesktopIdentity identity,
) async {
  final opt = p.join(root, 'opt', identity.installDir);
  await build.copyTree(bundle, opt);
  renameForChannel(opt, identity);
  build.copy(
    p.join(build.rootDir, 'assets', 'images', 'icon.png'),
    p.join(
      root,
      'usr/share/icons/hicolor/256x256/apps',
      '${identity.executable}.png',
    ),
  );
  final desktop = File(
    p.join(root, 'usr/share/applications', '${identity.bundleId}.desktop'),
  );
  desktop.parent.createSync(recursive: true);
  desktop.writeAsStringSync(
    desktopEntry(config, exec: linuxExecOf(identity), identity: identity),
  );
  _normalizeModes(root);
}

String linuxExecOf(DesktopIdentity identity) =>
    '/opt/${identity.installDir}/${identity.executable}';

/// dpkg-deb, rpmbuild and appimagetool record modes verbatim, and the Linux
/// Helper refuses an `/opt/FlClashX` that a umask of 002 left group-writable.
void _normalizeModes(String root) {
  Process.runSync('chmod', ['-R', 'u+rwX,go+rX,go-w', root]);
}

String debControlOf(
  Map<dynamic, dynamic> config,
  DesktopIdentity identity, {
  required String version,
  required String arch,
}) {
  final depends = [
    for (final item in (config['dependencies'] as List?) ?? const [])
      item.toString(),
  ];
  final maintainer = (config['maintainer'] as Map?) ?? const {};
  return [
    'Package: ${identity.packageName}',
    'Version: $version',
    'Section: ${config['section'] ?? 'x11'}',
    'Priority: ${config['priority'] ?? 'optional'}',
    'Architecture: $arch',
    if (config['installed_size'] != null)
      'Installed-Size: ${config['installed_size']}',
    if (depends.isNotEmpty) 'Depends: ${depends.join(', ')}',
    'Maintainer: ${maintainer['name']} <${maintainer['email']}>',
    'Description: ${identity.pre ? identity.displayName : config['display_name'] ?? _appName}',
    '',
  ].join('\n');
}

Future<void> _packageDeb(
  _Build build,
  String bundle,
  DesktopIdentity identity,
) async {
  final config = build.packagingConfig('deb');
  final root = p.join(build.rootDir, 'build', 'deb_root');
  if (Directory(root).existsSync()) Directory(root).deleteSync(recursive: true);
  await _installTree(build, root, bundle, config, identity);
  final control = File(p.join(root, 'DEBIAN', 'control'));
  control.parent.createSync(recursive: true);
  control.writeAsStringSync(
    debControlOf(config, identity, version: build.version, arch: build.arch),
  );
  final postrm = channelScripts(
    _scripts(config, 'postuninstall_scripts'),
    identity,
  );
  if (postrm.isNotEmpty) {
    _writeExecutable(
      p.join(root, 'DEBIAN', 'postrm'),
      ['#!/bin/sh', 'set -e', ...postrm, ''].join('\n'),
    );
  }
  await build.mustRun('dpkg-deb', [
    '--build',
    '--root-owner-group',
    root,
    build.dist(artifactName('linux', build.arch, '.deb')),
  ]);
  Directory(root).deleteSync(recursive: true);
}

String rpmSpecOf(
  Map<dynamic, dynamic> config,
  DesktopIdentity identity, {
  required String version,
}) {
  final requires = [
    for (final item in (config['requires'] as List?) ?? const [])
      item.toString(),
  ];
  final name = identity.pre
      ? identity.displayName
      : (config['display_name'] ?? _appName) as String;
  final postun = channelScripts(
    _scripts(config, 'postuninstall_scripts'),
    identity,
  );
  return [
    ..._scripts(config, 'spec_macros'),
    'Name: ${identity.packageName}',
    'Version: $version',
    'Release: 1',
    'Summary: $name',
    'License: ${config['license'] ?? 'Other'}',
    'Group: ${config['group'] ?? 'Applications/Internet'}',
    'Packager: ${config['packager']} <${config['packagerEmail']}>',
    'AutoReqProv: no',
    for (final item in requires) 'Requires: $item',
    '',
    '%description',
    '$name proxy client',
    '',
    '%install',
    'cp -r %{_builddir}/root/* %{buildroot}/',
    '',
    if (_scripts(config, 'postinstall_scripts').isNotEmpty) ...[
      '%post',
      ..._scripts(config, 'postinstall_scripts'),
      '',
    ],
    if (postun.isNotEmpty) ...['%postun', ...postun, ''],
    '%files',
    '/opt/${identity.installDir}/*',
    '/usr/share/applications/${identity.bundleId}.desktop',
    '/usr/share/icons/hicolor/256x256/apps/${identity.executable}.png',
    '',
  ].join('\n');
}

Future<void> _packageRpm(
  _Build build,
  String bundle,
  DesktopIdentity identity,
) async {
  final config = build.packagingConfig('rpm');
  final rpmArch = build.arch == 'arm64' ? 'aarch64' : 'x86_64';
  final top = p.join(build.rootDir, 'build', 'rpmbuild');
  if (Directory(top).existsSync()) Directory(top).deleteSync(recursive: true);
  final root = p.join(top, 'BUILD', 'root');
  await _installTree(build, root, bundle, config, identity);
  final spec = File(p.join(top, '${identity.executable}.spec'));
  spec.writeAsStringSync(rpmSpecOf(config, identity, version: build.version));
  await build.mustRun('rpmbuild', [
    '-bb',
    spec.path,
    '--define',
    '_topdir $top',
    '--define',
    '_builddir ${p.join(top, 'BUILD')}',
    '--target',
    rpmArch,
  ]);
  final built = Directory(
    p.join(top, 'RPMS', rpmArch),
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.rpm'));
  if (built.isEmpty) {
    throw const ProcessException('rpmbuild', [], 'no RPM was created', 1);
  }
  build.copy(
    built.first.path,
    build.dist(artifactName('linux', build.arch, '.rpm')),
  );
  Directory(top).deleteSync(recursive: true);
}

Future<void> _packageAppImage(
  _Build build,
  String bundle,
  DesktopIdentity identity,
) async {
  final config = build.packagingConfig('appimage');
  final appDir = p.join(build.rootDir, 'build', 'AppDir');
  if (Directory(appDir).existsSync()) {
    Directory(appDir).deleteSync(recursive: true);
  }
  final usr = p.join(appDir, 'usr');
  // Flutter loads its AOT code from lib/libapp.so beside the executable, so
  // the bundle keeps the layout Flutter built.
  await build.copyTree(bundle, p.join(usr, 'bin'));
  renameForChannel(p.join(usr, 'bin'), identity);
  for (final extra in (config['include'] as List?) ?? const []) {
    final source = extra.toString();
    if (File(source).existsSync()) {
      build.copy(source, p.join(usr, 'lib', p.basename(source)));
    }
  }
  final trayPlugin = p.join(bundle, 'lib', 'libtray_plugin.so');
  final ldd = Process.runSync('ldd', [trayPlugin]);
  final indicatorLibraries = appIndicatorLibraries(ldd.stdout.toString());
  if (indicatorLibraries.isEmpty) {
    throw ProcessException(
      'ldd',
      [trayPlugin],
      'the tray plugin links no AppIndicator library to bundle',
      1,
    );
  }
  for (final library in indicatorLibraries) {
    build.copy(library, p.join(usr, 'lib', p.basename(library)));
  }
  final icon = p.join(build.rootDir, 'assets', 'images', 'icon.png');
  final iconName = '${identity.executable}.png';
  build.copy(icon, p.join(usr, 'share/icons/hicolor/256x256/apps', iconName));
  build.copy(icon, p.join(appDir, iconName));
  final desktop = desktopEntry(
    config,
    exec: identity.executable,
    identity: identity,
  );
  for (final path in [
    p.join(usr, 'share/applications', '${identity.bundleId}.desktop'),
    p.join(appDir, '${identity.bundleId}.desktop'),
  ]) {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(desktop);
  }
  _writeExecutable(
    p.join(appDir, 'AppRun'),
    [
      '#!/bin/bash',
      r'SELF=$(readlink -f "$0")',
      r'HERE=${SELF%/*}',
      r'export PATH="${HERE}/usr/bin:${PATH}"',
      r'export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"',
      'exec "\${HERE}/usr/bin/${identity.executable}" "\$@"',
      '',
    ].join('\n'),
  );
  Process.runSync('chmod', ['755', p.join(usr, 'bin', identity.executable)]);
  _normalizeModes(appDir);
  await build.mustRun(
    'appimagetool',
    [appDir, build.dist(artifactName('linux', build.arch, '.AppImage'))],
    environment: {'ARCH': appImageEnvArch(build.arch)},
  );
  Directory(appDir).deleteSync(recursive: true);
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64' || machine == 'arm64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(
    which,
    args,
    runInShell: !Platform.isWindows,
  );
  return result.exitCode == 0;
}

Future<int> _ensureDependencies(String platform) async {
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies();
    case 'linux':
      return _ensureLinuxDependencies();
    default:
      return 0;
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('create-dmg')) {
    stdout.writeln('create-dmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing create-dmg...');
  // create-dmg's native helpers build on install, which npm blocks by default.
  final result = await Process.run('npm', [
    'install',
    '-g',
    '--allow-scripts=fs-xattr,macos-alias',
    'create-dmg',
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<int> _ensureLinuxDependencies() async {
  const pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libsecret-1-dev'],
    ['locate'],
    ['rpm', 'patchelf'],
    ['libfuse2'],
  ];

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  const appimagetool = '/usr/local/bin/appimagetool';
  if (File(appimagetool).existsSync()) {
    stdout.writeln('appimagetool already installed, skipping.');
    return 0;
  }
  stdout.writeln('Downloading appimagetool...');
  final downloadName =
      'appimagetool-${appImageToolArch(_detectArch())}.AppImage';
  final dlResult = await Process.run('sudo', [
    'wget',
    '-O',
    appimagetool,
    'https://github.com/AppImage/AppImageKit/releases/download/continuous/$downloadName',
  ]);
  if (dlResult.exitCode != 0) {
    stderr.write(dlResult.stderr);
    return dlResult.exitCode;
  }
  await Process.run('sudo', ['chmod', '+x', appimagetool]);
  return 0;
}

/// The tray links AppIndicator, which most desktops without one installed
/// cannot load; the AppImage carries it and the libraries it pulls in.
List<String> appIndicatorLibraries(String lddOutput) {
  final library = RegExp(
    r'^\s*(lib(?:ayatana-)?(?:appindicator|indicator|ido|dbusmenu)\S*)\s+=>\s+(\S+)',
    multiLine: true,
  );
  return [for (final match in library.allMatches(lddOutput)) match.group(2)!];
}

String appImageToolArch(String arch) {
  return arch == 'arm64' ? 'aarch64' : 'x86_64';
}

/// The continuous appimagetool spells arm64 `arm_aarch64` in `ARCH`; given
/// `aarch64` it guesses from the libraries instead and refuses a mixed AppDir.
String appImageEnvArch(String arch) {
  return arch == 'arm64' ? 'arm_aarch64' : 'x86_64';
}

/// Ubuntu 24.04 ships libfuse2 under its time64 name, which `dpkg -s libfuse2` cannot see.
const _debianPackageAliases = <String, List<String>>{
  'libfuse2': ['libfuse2t64'],
};

Future<bool> _isDebianPackageInstalled(String pkg) async {
  for (final name in [pkg, ...?_debianPackageAliases[pkg]]) {
    final result = await Process.run('dpkg', ['-s', name]);
    if (result.exitCode == 0 &&
        (result.stdout as String).contains('Status: install ok installed')) {
      return true;
    }
  }
  return false;
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
