import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('a pre build of macOS takes its own bundle id and name', () {
      final config = setup.macosChannelConfig('pre')!;

      expect(
        config,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.follow.clashx.pre'),
      );
      expect(config, contains('APP_DISPLAY_NAME = FlClashX Pre'));
      expect(setup.macosBundleName('pre'), 'FlClashX Pre.app');
    });

    test('stable and dev builds of macOS keep the stable identity', () {
      for (final env in ['stable', 'dev']) {
        expect(setup.macosChannelConfig(env), isNull);
        expect(setup.macosBundleName(env), 'FlClashX.app');
      }
    });

    test('the xcconfig the pre build writes is optional and ignored', () {
      final appInfo = File(
        p.join('macos', 'Runner', 'Configs', 'AppInfo.xcconfig'),
      ).readAsStringSync();
      final gitignore = File('.gitignore').readAsStringSync();

      expect(appInfo, contains('#include? "Channel.xcconfig"'));
      expect(gitignore, contains('/macos/Runner/Configs/Channel.xcconfig'));
    });

    test('a macOS release build fails when its defines and bundle id part', () {
      final project = File(
        p.join('macos', 'Runner.xcodeproj', 'project.pbxproj'),
      ).readAsStringSync();
      final check = project.indexOf(
        'F5C0FFEE2F10000100000002 /* Check Channel */,',
      );
      final sources = project.indexOf(
        '33CC10E92044A3C60003C045 /* Sources */,',
      );

      expect(check, isNonNegative);
      expect(check, lessThan(sources));
      expect(project, contains(r'expected=com.follow.clashx.pre'));
      expect(
        project,
        contains(r'[ \"$CONFIGURATION\" = \"Debug\" ] && exit 0'),
      );
    });

    test('Android reads the channel as Dart does', () {
      final gradle = File(
        p.join('android', 'app', 'build.gradle.kts'),
      ).readAsStringSync();

      expect(gradle, contains('.associate {'));
      expect(gradle, contains('(dartDefines["APP_ENV"] ?: "pre") == "pre"'));
      expect(gradle, contains('applicationIdSuffix = ".pre"'));
    });

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

    test('signs the code inside the macOS app before the app', () {
      final root = Directory.systemTemp.createTempSync('setup_sign');
      addTearDown(() => root.deleteSync(recursive: true));
      final app = p.join(root.path, 'FlClashX.app');
      String at(String path) => p.joinAll([app, ...path.split('/')]);
      for (final dir in [
        'Contents/Frameworks/FlutterMacOS.framework',
        'Contents/Frameworks/App.framework',
        'Contents/Library/LoginItems/Helper.app',
        'Contents/Resources/plugin.bundle',
      ]) {
        Directory(at(dir)).createSync(recursive: true);
      }
      for (final file in [
        'Contents/MacOS/FlClashX',
        'Contents/MacOS/FlClashCore',
        'Contents/Frameworks/Info.plist',
      ]) {
        File(at(file)).createSync(recursive: true);
      }

      expect(setup.macosSigningOrder(app), [
        at('Contents/Frameworks/App.framework'),
        at('Contents/Frameworks/FlutterMacOS.framework'),
        at('Contents/Library/LoginItems/Helper.app'),
        at('Contents/MacOS/FlClashCore'),
        app,
      ]);
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
            {'lang': 'zh'},
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
      expect(script, contains('Name: "chineseSimplified"'));
      expect(
        script,
        contains(
          p.join(
            r'C:\repo',
            'windows',
            'packaging',
            'exe',
            'ChineseSimplified.isl',
          ),
        ),
      );
      expect(script, contains('Arch=x64compatible'));
      expect(script, contains('Flags: runascurrentuser nowait'));
      expect(script, isNot(contains('{{')));
    });

    test('the Windows installer offers Chinese after Russian', () {
      final langs = RegExp(r'- lang: (\w+)')
          .allMatches(
            File('windows/packaging/exe/make_config.yaml').readAsStringSync(),
          )
          .map((match) => match[1])
          .toList();

      expect(langs.first, 'ru');
      expect(langs, contains('zh'));
      expect(
        File(
          'windows/packaging/exe/ChineseSimplified.isl',
        ).readAsBytesSync().take(3),
        [0xEF, 0xBB, 0xBF],
      );
    });

    test('every installer language has every custom message', () {
      final script = File(
        'windows/packaging/exe/inno_setup.iss',
      ).readAsStringSync();
      Set<String> namesOf(String language) => RegExp(
        '^$language\\.(\\w+)=',
        multiLine: true,
      ).allMatches(script).map((match) => match[1]!).toSet();

      final english = namesOf('english');
      expect(english, isNotEmpty);
      expect(namesOf('russian'), english);
      expect(namesOf('chineseSimplified'), english);
    });

    test('the installer clears a stale proxy once it has killed the app', () {
      final script = File(
        'windows/packaging/exe/inno_setup.iss',
      ).readAsStringSync();

      expect(
        script,
        contains("ExecAsOriginalUser(AppPath, '--clear-stale-proxy'"),
      );
      expect(
        script,
        matches(RegExp(r'ssPostInstall then\s+begin[^;]+;\s+ClearStaleProxy;')),
      );
      expect(
        script,
        matches(
          RegExp(r'usUninstall:\s+begin\s+ShutDownApp;\s+ClearStaleProxy;'),
        ),
      );
      expect(
        script,
        matches(
          RegExp(r'ShutDownApp;\s+ClearStaleProxyBeforeInstall;\s+Result'),
        ),
        reason: 'an aborted install must not leave the proxy on a dead port',
      );
      expect(
        script,
        contains('Source: "{{CLEAR_PROXY_SCRIPT}}"; Flags: dontcopy'),
      );
      expect(
        script,
        contains("ExtractTemporaryFile('clear_stale_proxy.ps1');"),
      );
      expect(
        File('windows/packaging/exe/clear_stale_proxy.ps1').readAsStringSync(),
        contains(r"'^127\.0\.0\.1:(\d{1,5})$'"),
      );
    });

    test('the installer takes over a 0.4 FlClashX registration in place', () {
      final script = File(
        'windows/packaging/exe/inno_setup.iss',
      ).readAsStringSync();

      expect(
        script,
        contains(r'Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1'),
      );
      expect(script, contains("(Pos('FlClashX', Name) = 1)"));
      expect(script, contains('WizardForm.DirEdit.Text := LegacyDir;'));
      expect(
        script,
        matches(RegExp(r'ClearStaleProxy;\s+RetireLegacyInstall;')),
      );
      expect(script, isNot(contains('Exec(Uninstaller')));
    });

    group('a Windows or Linux pre-release', () {
      final template = File(
        'windows/packaging/exe/inno_setup.iss',
      ).readAsStringSync();
      final config = {
        'app_id': 'D915C0D1-2F5B-4676-97D5-6D55F3EF45A4',
        'display_name': 'FlClashX',
        'executable_name': 'FlClashX.exe',
      };

      String render(setup.DesktopIdentity identity) => setup.renderInnoSetup(
        template,
        config: config,
        version: '0.5.1',
        arch: 'amd64',
        sourceDir: r'C:\build',
        outputDir: r'C:\dist',
        outputBaseName: 'FlClashX-windows-amd64-setup',
        rootDir: r'C:\repo',
        identity: identity,
      );

      test('installs under its own id, name, Helper and data', () {
        final pre = render(setup.preDesktop);
        expect(pre, isNot(contains('D915C0D1-2F5B-4676-97D5-6D55F3EF45A4')));
        expect(pre, contains(r'DefaultDirName={autopf}\FlClashX Pre'));
        expect(pre, contains("HelperService = 'FlClashXPreHelperService';"));
        expect(pre, contains('AdoptLegacy = False;'));
        expect(pre, contains("KillProcess('FlClashXPre.exe');"));
        expect(pre, contains(r'{userappdata}\com.follow\clashx.pre'));
        expect(
          RegExp(r'\{\{([A-Z_]+)\}\}').allMatches(pre).map((m) => m[1]),
          everyElement('NAME'),
        );
      });

      test('leaves the stable installer as it was', () {
        final stable = render(setup.stableDesktop);
        expect(stable, contains('AppId=D915C0D1-2F5B-4676-97D5-6D55F3EF45A4'));
        expect(stable, contains(r'DefaultDirName={autopf}\FlClashX'));
        expect(stable, contains("HelperService = 'FlClashXHelperService';"));
        expect(stable, contains('AdoptLegacy = True;'));
        expect(stable, contains("KillProcess('FlClashX.exe');"));
        expect(stable, contains(r"{userappdata}\com.follow\clashx')"));
      });

      test('stops only the Core started from its own install', () {
        expect(template, isNot(contains("KillProcess('FlClashCore.exe')")));
        expect(template, matches(RegExp(r'KillCore;\s+Sleep\(1000\);')));
        expect(template, contains(r'$_.Path.StartsWith('));
      });

      test('packages for Linux under its own names', () {
        final linuxConfig = {
          'display_name': 'FlClashX',
          'startup_wm_class': 'com.follow.clashx',
          'maintainer': {'name': 'pluralplay', 'email': 'x@example.com'},
          'postuninstall_scripts': [
            'rm -f /etc/systemd/system/flclashx-helper.service',
          ],
        };
        final control = setup.debControlOf(
          linuxConfig,
          setup.preDesktop,
          version: '0.5.1',
          arch: 'amd64',
        );
        expect(control, contains('Package: flclashx-pre'));
        expect(control, contains('Description: FlClashX Pre'));
        final spec = setup.rpmSpecOf(
          linuxConfig,
          setup.preDesktop,
          version: '0.5.1',
        );
        expect(spec, contains('Name: flclashx-pre'));
        expect(spec, contains('/opt/FlClashXPre/*'));
        expect(
          spec,
          contains('/usr/share/applications/com.follow.clashx.pre.desktop'),
        );
        expect(spec, contains('apps/FlClashXPre.png'));
        expect(spec, contains('flclashx-pre-helper.service'));
        expect(spec, isNot(contains('/flclashx-helper.service')));
        final entry = setup.desktopEntry(
          linuxConfig,
          exec: setup.linuxExecOf(setup.preDesktop),
          identity: setup.preDesktop,
        );
        expect(entry, contains('Name=FlClashX Pre'));
        expect(entry, contains('Exec=/opt/FlClashXPre/FlClashXPre %u'));
        expect(entry, contains('Icon=FlClashXPre'));
        expect(entry, contains('StartupWMClass=com.follow.clashx.pre'));
        expect(
          setup.debControlOf(
            linuxConfig,
            setup.stableDesktop,
            version: '0.5.1',
            arch: 'amd64',
          ),
          contains('Package: flclashx\n'),
        );
        expect(
          setup.desktopEntry(linuxConfig, exec: '/opt/FlClashX/FlClashX'),
          allOf(
            contains('Icon=FlClashX\n'),
            contains('StartupWMClass=com.follow.clashx\n'),
          ),
        );
      });

      test('renames the app and Helper in the staged bundle only for pre', () {
        final dir = Directory.systemTemp.createTempSync('channel_bundle');
        addTearDown(() => dir.deleteSync(recursive: true));
        for (final name in ['FlClashX.exe', 'FlClashXHelperService.exe']) {
          File('${dir.path}/$name').writeAsStringSync('x');
        }
        setup.renameForChannel(dir.path, setup.stableDesktop, ext: '.exe');
        expect(File('${dir.path}/FlClashX.exe').existsSync(), isTrue);
        setup.renameForChannel(dir.path, setup.preDesktop, ext: '.exe');
        expect(File('${dir.path}/FlClashXPre.exe').existsSync(), isTrue);
        expect(
          File('${dir.path}/FlClashXPreHelperService.exe').existsSync(),
          isTrue,
        );
        expect(File('${dir.path}/FlClashX.exe').existsSync(), isFalse);
      });

      test('refuses a pre build the channel never reached', () {
        final dir = Directory.systemTemp.createTempSync('channel_marker');
        addTearDown(() => dir.deleteSync(recursive: true));
        final binary = File('${dir.path}/FlClashX.exe')
          ..writeAsBytesSync([0, ...setup.utf16le('clashx.pre'), 0]);
        setup.requireChannelMarker(binary.path, setup.utf16le('clashx.pre'));
        binary.writeAsBytesSync(setup.utf16le('clashx'));
        expect(
          () => setup.requireChannelMarker(
            binary.path,
            setup.utf16le('clashx.pre'),
          ),
          throwsA(isA<ProcessException>()),
        );
        expect(setup.desktopBuildEnvironment('pre'), {
          'FLCLASHX_CHANNEL': 'pre',
        });
        expect(setup.desktopIdentityOf('stable'), same(setup.stableDesktop));
        expect(setup.desktopIdentityOf('dev'), same(setup.stableDesktop));
      });
    });

    test('bundles the AppIndicator libraries the tray links', () {
      const ldd = '''
\tlinux-vdso.so.1 (0x00007ffd)
\tlibflutter_linux_gtk.so => /opt/bundle/lib/libflutter_linux_gtk.so (0x7f)
\tlibayatana-appindicator3.so.1 => /lib/x86_64-linux-gnu/libayatana-appindicator3.so.1 (0x7f)
\tlibgtk-3.so.0 => /lib/x86_64-linux-gnu/libgtk-3.so.0 (0x7f)
\tlibayatana-indicator3.so.7 => /lib/x86_64-linux-gnu/libayatana-indicator3.so.7 (0x7f)
\tlibayatana-ido3-0.4.so.0 => /lib/x86_64-linux-gnu/libayatana-ido3-0.4.so.0 (0x7f)
\tlibdbusmenu-gtk3.so.4 => /lib/x86_64-linux-gnu/libdbusmenu-gtk3.so.4 (0x7f)
\tlibdbusmenu-glib.so.4 => /lib/x86_64-linux-gnu/libdbusmenu-glib.so.4 (0x7f)
''';

      expect(setup.appIndicatorLibraries(ldd), [
        '/lib/x86_64-linux-gnu/libayatana-appindicator3.so.1',
        '/lib/x86_64-linux-gnu/libayatana-indicator3.so.7',
        '/lib/x86_64-linux-gnu/libayatana-ido3-0.4.so.0',
        '/lib/x86_64-linux-gnu/libdbusmenu-gtk3.so.4',
        '/lib/x86_64-linux-gnu/libdbusmenu-glib.so.4',
      ]);
    });

    test('downloads the appimagetool build matching the host', () {
      expect(setup.appImageToolArch('arm64'), 'aarch64');
      expect(setup.appImageToolArch('amd64'), 'x86_64');
      expect(setup.appImageEnvArch('arm64'), 'arm_aarch64');
      expect(setup.appImageEnvArch('amd64'), 'x86_64');
    });
  });
}
