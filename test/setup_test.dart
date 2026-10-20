import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });

    test('refuses to package while a native build hook is skipped', () {
      const pubspec = '''
hooks:
  user_defines:
    setup:
      build_assets: false
    rust_api:
      build_assets: true
''';

      expect(setup.packagesNotBuildingAssets(pubspec), ['setup']);
      expect(setup.packagesNotBuildingAssets('name: x\n'), isEmpty);
    });

    test('packages every Linux format on every architecture', () {
      expect(setup.createPackageTargets('linux', null), 'deb,appimage,rpm');
      expect(setup.createPackageTargets('linux', 'deb'), 'deb');
      expect(setup.createPackageTargets('macos', null), 'dmg');
    });

    test('names artifacts by platform and architecture', () {
      expect(
        setup.artifactName('windows', 'amd64', '-setup.exe'),
        'FlClashX-windows-amd64-setup.exe',
      );
      expect(
        setup.artifactName('android', 'arm64-v8a', '.apk'),
        'FlClashX-android-arm64-v8a.apk',
      );
    });

    test('a release tag is the app version, else the pubspec one', () {
      expect(
        setup.appVersionOf(
          pubspecVersion: '0.9.1',
          environment: {'GITHUB_REF_NAME': 'v0.9.2-pre.3'},
        ),
        '0.9.2-pre.3',
      );
      expect(
        setup.appVersionOf(
          pubspecVersion: '0.9.1',
          environment: {'GITHUB_REF_NAME': 'dev'},
        ),
        '0.9.1',
      );
      expect(setup.appVersionOf(pubspecVersion: '0.9.1'), '0.9.1');
    });

    test('the build carries both versions as defines', () {
      expect(
        setup.createBuildDefines(appVersion: '0.9.1', coreVersion: 'v1.19.32'),
        [
          '--dart-define=APP_VERSION=0.9.1',
          '--dart-define=CORE_VERSION=v1.19.32',
        ],
      );
      expect(setup.createBuildDefines(appVersion: '0.9.1', coreVersion: ''), [
        '--dart-define=APP_VERSION=0.9.1',
      ]);
    });

    test('renders the Inno Setup script from the packaging config', () {
      const template =
          'AppId={{APP_ID}}\nAppVersion={{APP_VERSION}}\n{{LANGUAGES}}\n'
          'Arch={{ARCH}}\nFlags: {{RUN_FLAGS}} nowait';
      final script = setup.renderInnoSetup(
        template,
        config: {
          'app_id': 'ABC',
          'display_name': 'FlClashX',
          'publisher': 'pluralplay',
          'locales': [
            {'lang': 'ru'},
            {'lang': 'en'},
          ],
          'privileges_required': 'admin',
          'setup_icon_file': r'windows\runner\resources\app_icon.ico',
        },
        version: '0.9.1',
        arch: 'amd64',
        sourceDir: r'C:\build',
        outputDir: r'C:\dist',
        outputBaseName: 'FlClashX-windows-amd64-setup',
        rootDir: r'C:\repo',
      );
      expect(script, contains('AppId=ABC'));
      expect(script, contains('AppVersion=0.9.1'));
      expect(script, contains('Name: "russian"'));
      expect(script, contains('Name: "english"'));
      expect(script, contains('Arch=x64compatible'));
      expect(script, contains('Flags: runascurrentuser nowait'));
      expect(script, isNot(contains('{{')));
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
      expect(setup.appImageEnvArch('arm64'), 'arm_aarch64');
      expect(setup.appImageEnvArch('amd64'), 'x86_64');
    });
  });
}
