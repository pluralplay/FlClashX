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
        await _packageMacos(build);
      case 'windows':
        await _packageWindows(build, wanted);
      case 'linux':
        await _packageLinux(build, wanted);
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

Future<void> _packageMacos(_Build build) async {
  await build.mustRun('flutter', [
    'build',
    'macos',
    '--release',
    ...build.flutterBuildArgs(),
  ]);
  final app = p.join(
    build.rootDir,
    'build/macos/Build/Products/Release',
    '$_appName.app',
  );
  final staging = Directory(p.join(build.rootDir, 'build', 'dmg'));
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);
  // Without a signing identity create-dmg still writes the image, then exits
  // non-zero over the signature it could not add; the release job signs later.
  final code = await build.run('create-dmg', [
    '--overwrite',
    '--dmg-title',
    _appName,
    app,
    staging.path,
  ]);
  final created = staging
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.dmg'))
      .toList();
  if (created.isEmpty) {
    throw ProcessException('create-dmg', const [], 'no DMG was created', code);
  }
  if (code != 0) {
    stderr.writeln('create-dmg exited with $code; the DMG is unsigned.');
  }
  build.copy(
    created.first.path,
    build.dist(artifactName('macos', build.arch, '.dmg')),
  );
  staging.deleteSync(recursive: true);
}

Future<void> _packageWindows(_Build build, Set<String> targets) async {
  await build.mustRun('flutter', [
    'build',
    'windows',
    '--release',
    ...build.flutterBuildArgs(),
  ]);
  final winArch = build.arch == 'arm64' ? 'arm64' : 'x64';
  final bundle = p.join(
    build.rootDir,
    'build',
    'windows',
    winArch,
    'runner',
    'Release',
  );
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
  'zh':
      'Name: "chineseSimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"',
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
}) {
  final displayName = (config['display_name'] ?? _appName) as String;
  final privileges = (config['privileges_required'] ?? 'admin') as String;
  final locales = (config['locales'] as List?) ?? const [];
  final languages = [
    for (final locale in locales)
      if (locale is Map && _innoLanguages[locale['lang']] != null)
        _innoLanguages[locale['lang']]!,
  ];
  if (languages.isEmpty) languages.add(_innoLanguages['en']!);
  final iconFile = (config['setup_icon_file'] as String?) ?? '';
  final values = {
    'APP_ID': config['app_id'] as String,
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
    'EXECUTABLE_NAME': (config['executable_name'] ?? '$_appName.exe') as String,
    'LANGUAGES': languages.join('\n'),
    'RUN_FLAGS': privileges == 'admin' ? 'runascurrentuser' : '',
  };
  var rendered = template;
  values.forEach((key, value) {
    rendered = rendered.replaceAll('{{$key}}', value);
  });
  return rendered;
}

Future<void> _packageLinux(_Build build, Set<String> targets) async {
  final flutterArch = build.arch == 'arm64' ? 'arm64' : 'x64';
  await build.mustRun('flutter', [
    'build',
    'linux',
    '--release',
    '--target-platform=linux-$flutterArch',
    ...build.flutterBuildArgs(),
  ]);
  final bundle = p.join(
    build.rootDir,
    'build',
    'linux',
    flutterArch,
    'release',
    'bundle',
  );
  if (targets.contains('deb')) await _packageDeb(build, bundle);
  if (targets.contains('rpm')) await _packageRpm(build, bundle);
  if (targets.contains('appimage')) await _packageAppImage(build, bundle);
}

String _desktopEntry(Map<dynamic, dynamic> config, {required String exec}) {
  List<String> list(String key) => [
    for (final item in (config[key] as List?) ?? const []) item.toString(),
  ];
  final name = (config['display_name'] ?? _appName) as String;
  return [
    '[Desktop Entry]',
    'Type=Application',
    'Name=$name',
    'GenericName=${config['generic_name'] ?? name}',
    'Comment=$name',
    'Exec=$exec %u',
    'Icon=$_appName',
    'Terminal=false',
    if (list('categories').isNotEmpty)
      'Categories=${list('categories').join(';')};',
    if (list('keywords').isNotEmpty) 'Keywords=${list('keywords').join(';')};',
    if (list('supported_mime_type').isNotEmpty)
      'MimeType=${list('supported_mime_type').join(';')};',
    'StartupNotify=${config['startup_notify'] ?? true}',
    if (config['startup_wm_class'] != null)
      'StartupWMClass=${config['startup_wm_class']}',
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
  Map<dynamic, dynamic> config, {
  required String exec,
}) async {
  await build.copyTree(bundle, p.join(root, 'opt', _appName));
  build.copy(
    p.join(build.rootDir, 'assets', 'images', 'icon.png'),
    p.join(root, 'usr/share/icons/hicolor/256x256/apps', '$_appName.png'),
  );
  final desktop = File(
    p.join(root, 'usr/share/applications', '$_bundleId.desktop'),
  );
  desktop.parent.createSync(recursive: true);
  desktop.writeAsStringSync(_desktopEntry(config, exec: exec));
  _normalizeModes(root);
}

/// dpkg-deb, rpmbuild and appimagetool record modes verbatim, and the Linux
/// Helper refuses an `/opt/FlClashX` that a umask of 002 left group-writable.
void _normalizeModes(String root) {
  Process.runSync('chmod', ['-R', 'u+rwX,go+rX,go-w', root]);
}

Future<void> _packageDeb(_Build build, String bundle) async {
  final config = build.packagingConfig('deb');
  final root = p.join(build.rootDir, 'build', 'deb_root');
  if (Directory(root).existsSync()) Directory(root).deleteSync(recursive: true);
  await _installTree(
    build,
    root,
    bundle,
    config,
    exec: '/opt/$_appName/$_appName',
  );
  final depends = [
    for (final item in (config['dependencies'] as List?) ?? const [])
      item.toString(),
  ];
  final maintainer = (config['maintainer'] as Map?) ?? const {};
  final control = File(p.join(root, 'DEBIAN', 'control'));
  control.parent.createSync(recursive: true);
  control.writeAsStringSync(
    [
      'Package: ${_appName.toLowerCase()}',
      'Version: ${build.version}',
      'Section: ${config['section'] ?? 'x11'}',
      'Priority: ${config['priority'] ?? 'optional'}',
      'Architecture: ${build.arch}',
      if (config['installed_size'] != null)
        'Installed-Size: ${config['installed_size']}',
      if (depends.isNotEmpty) 'Depends: ${depends.join(', ')}',
      'Maintainer: ${maintainer['name']} <${maintainer['email']}>',
      'Description: ${config['display_name'] ?? _appName}',
      '',
    ].join('\n'),
  );
  final postrm = _scripts(config, 'postuninstall_scripts');
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

Future<void> _packageRpm(_Build build, String bundle) async {
  final config = build.packagingConfig('rpm');
  final rpmArch = build.arch == 'arm64' ? 'aarch64' : 'x86_64';
  final top = p.join(build.rootDir, 'build', 'rpmbuild');
  if (Directory(top).existsSync()) Directory(top).deleteSync(recursive: true);
  final root = p.join(top, 'BUILD', 'root');
  await _installTree(
    build,
    root,
    bundle,
    config,
    exec: '/opt/$_appName/$_appName',
  );
  final requires = [
    for (final item in (config['requires'] as List?) ?? const [])
      item.toString(),
  ];
  final spec = File(p.join(top, '$_appName.spec'));
  spec.writeAsStringSync(
    [
      ..._scripts(config, 'spec_macros'),
      'Name: ${_appName.toLowerCase()}',
      'Version: ${build.version}',
      'Release: 1',
      'Summary: ${config['display_name'] ?? _appName}',
      'License: ${config['license'] ?? 'Other'}',
      'Group: ${config['group'] ?? 'Applications/Internet'}',
      'Packager: ${config['packager']} <${config['packagerEmail']}>',
      'AutoReqProv: no',
      for (final item in requires) 'Requires: $item',
      '',
      '%description',
      '${config['display_name'] ?? _appName} proxy client',
      '',
      '%install',
      'cp -r %{_builddir}/root/* %{buildroot}/',
      '',
      if (_scripts(config, 'postinstall_scripts').isNotEmpty) ...[
        '%post',
        ..._scripts(config, 'postinstall_scripts'),
        '',
      ],
      if (_scripts(config, 'postuninstall_scripts').isNotEmpty) ...[
        '%postun',
        ..._scripts(config, 'postuninstall_scripts'),
        '',
      ],
      '%files',
      '/opt/$_appName/*',
      '/usr/share/applications/$_bundleId.desktop',
      '/usr/share/icons/hicolor/256x256/apps/$_appName.png',
      '',
    ].join('\n'),
  );
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

Future<void> _packageAppImage(_Build build, String bundle) async {
  final config = build.packagingConfig('appimage');
  final appDir = p.join(build.rootDir, 'build', 'AppDir');
  if (Directory(appDir).existsSync()) {
    Directory(appDir).deleteSync(recursive: true);
  }
  final usr = p.join(appDir, 'usr');
  await build.copyTree(bundle, p.join(usr, 'bin'));
  final bundledLib = Directory(p.join(usr, 'bin', 'lib'));
  if (bundledLib.existsSync()) {
    bundledLib.renameSync(p.join(usr, 'lib'));
  }
  for (final extra in (config['include'] as List?) ?? const []) {
    final source = extra.toString();
    if (File(source).existsSync()) {
      build.copy(source, p.join(usr, 'lib', p.basename(source)));
    }
  }
  final icon = p.join(build.rootDir, 'assets', 'images', 'icon.png');
  build.copy(
    icon,
    p.join(usr, 'share/icons/hicolor/256x256/apps', '$_appName.png'),
  );
  build.copy(icon, p.join(appDir, '$_appName.png'));
  final desktop = _desktopEntry(config, exec: _appName);
  for (final path in [
    p.join(usr, 'share/applications', '$_bundleId.desktop'),
    p.join(appDir, '$_bundleId.desktop'),
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
      'exec "\${HERE}/usr/bin/$_appName" "\$@"',
      '',
    ].join('\n'),
  );
  Process.runSync('chmod', ['755', p.join(usr, 'bin', _appName)]);
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
