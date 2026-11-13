import 'dart:ffi';
import 'dart:io';

import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/identity.dart';
import 'package:fl_clash/features/update/platform.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _fails(UpdateErrorKind kind) =>
    throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', kind));

ProcessRunner _owners(Set<String> owning, List<String> calls) =>
    (executable, arguments, {environment}) async {
      calls.add(executable);
      if (executable == 'rpm' && !owning.contains('rpm')) {
        throw const ProcessException('rpm', [], 'not found');
      }
      return ProcessResult(0, owning.contains(executable) ? 0 : 1, '', '');
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectLinuxInstall', () {
    Future<UpdateInstallKind> detect(
      String executable, {
      Map<String, String> environment = const {},
      Set<String> owning = const {},
      List<String>? calls,
    }) => detectLinuxInstall(
      executable: executable,
      environment: environment,
      run: _owners(owning, calls ?? []),
    );

    test('an AppImage wins over everything else', () async {
      final calls = <String>[];
      expect(
        await detect(
          '/tmp/.mount_FlClaX/FlClashX',
          environment: {'APPIMAGE': '/home/u/FlClashX.AppImage'},
          calls: calls,
        ),
        UpdateInstallKind.appImage,
      );
      expect(calls, isEmpty);
    });

    test('a bundle under /usr/lib belongs to pacman', () async {
      expect(
        await detect('/usr/lib/flclashx/FlClashX'),
        UpdateInstallKind.packageManager,
      );
    });

    test('asks dpkg, then rpm, who owns /opt', () async {
      expect(
        await detect('/opt/FlClashX/FlClashX', owning: {'dpkg-query'}),
        UpdateInstallKind.deb,
      );
      expect(
        await detect('/opt/FlClashXPre/FlClashXPre', owning: {'rpm'}),
        UpdateInstallKind.rpm,
      );
      expect(
        await detect('/opt/FlClashX/FlClashX'),
        UpdateInstallKind.unsupported,
      );
    });

    test('a bundle run from anywhere else cannot update itself', () async {
      expect(
        await detect('/home/u/build/FlClashX', owning: {'dpkg-query'}),
        UpdateInstallKind.unsupported,
      );
      expect(
        await detect('/opt/FlClashXOther/FlClashX', owning: {'dpkg-query'}),
        UpdateInstallKind.unsupported,
      );
    });
  });

  test('desktop arch names follow the release assets', () {
    expect(desktopArch(Abi.macosArm64), 'arm64');
    expect(desktopArch(Abi.windowsX64), 'amd64');
    expect(desktopArch(Abi.linuxArm64), 'arm64');
    expect(desktopArch(Abi.androidArm64), isNull);
    expect(
      macosBundleOf('/Applications/FlClashX.app/Contents/MacOS/FlClashX'),
      '/Applications/FlClashX.app',
    );
  });

  test('a deb or rpm goes to the desktop package installer', () async {
    final calls = <List<String>>[];
    final platform = LinuxUpdatePlatform(
      target: const UpdateTarget(UpdateInstallKind.deb, ['amd64']),
      appImage: null,
      run: (executable, arguments, {environment}) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(0, 0, '', '');
      },
      exitApp: () => fail('a package install keeps the app running'),
    );
    final file = File('/cache/update/1/FlClashX-linux-amd64.deb');
    expect(await platform.install(file), UpdateInstallResult.handedOff);
    expect(calls, [
      ['xdg-open', file.path],
    ]);
  });

  group('macOS', () {
    late Directory root;
    late String bundle;
    late File image;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flclashx_update_macos');
      bundle = '${root.path}/Applications/FlClashX.app';
      await Directory(bundle).create(recursive: true);
      image = File('${root.path}/cache/1/FlClashX-macos-arm64.dmg');
      await image.create(recursive: true);
    });

    tearDown(() => root.delete(recursive: true));

    /// Plays hdiutil, ditto and the signature tools over the real folders;
    /// [signedPaths] names the bundles codesign vouches for.
    ProcessRunner tools({
      required List<List<String>> calls,
      bool detaches = true,
      bool Function(String path)? vouches,
    }) => (executable, arguments, {environment}) async {
      calls.add([executable, ...arguments]);
      switch (executable) {
        case '/usr/bin/hdiutil' when arguments.first == 'attach':
          final mount = arguments[arguments.indexOf('-mountpoint') + 1];
          await Directory('$mount/FlClashX.app').create(recursive: true);
          return ProcessResult(0, 0, '', '');
        case '/usr/bin/hdiutil':
          return ProcessResult(0, detaches ? 0 : 16, '', 'busy');
        case '/usr/bin/ditto':
          await Directory(arguments[1]).create(recursive: true);
          return ProcessResult(0, 0, '', '');
        case '/usr/bin/plutil':
          final path = arguments.last;
          final ok = vouches?.call(path) ?? true;
          return ProcessResult(0, 0, ok ? 'com.follow.clashx' : 'evil', '');
        default:
          return ProcessResult(0, 1, '', '');
      }
    };

    test('a disk image that will not detach fails the check', () async {
      final platform = MacosUpdatePlatform(
        bundle: bundle,
        archs: const ['arm64'],
        run: tools(calls: [], detaches: false),
        exitApp: () => fail('verifying never quits'),
      );
      await expectLater(
        platform.verify(image),
        _fails(UpdateErrorKind.installFailed),
      );
    });

    test(
      'the copy that would replace the app is checked before the swap',
      () async {
        final calls = <List<String>>[];
        final platform = MacosUpdatePlatform(
          bundle: bundle,
          archs: const ['arm64'],
          run: tools(
            calls: calls,
            vouches: (path) => !path.contains('.update-'),
          ),
          exitApp: () => fail('a rejected copy never quits'),
        );
        await platform.verify(image);

        await expectLater(
          platform.install(image),
          _fails(UpdateErrorKind.identityMismatch),
        );
        expect(Directory(bundle).existsSync(), isTrue);
        expect(
          Directory('${root.path}/Applications').listSync().map((e) => e.path),
          [bundle],
        );
      },
    );
  });

  group('Android', () {
    late App app;
    late List<MethodCall> calls;
    late Map<String, Object? Function(MethodCall)> answers;

    setUp(() {
      app = App();
      calls = [];
      answers = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(app.methodChannel, (call) async {
            calls.add(call);
            return answers[call.method]?.call(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(app.methodChannel, null);
    });

    AndroidUpdatePlatform platform() => AndroidUpdatePlatform(
      app: app,
      target: const UpdateTarget(UpdateInstallKind.android, ['universal']),
    );

    Map<String, Object> identity(String package, int code, String signer) => {
      'packageName': package,
      'versionCode': code,
      'signers': [signer],
    };

    test('verifies the APK against the running app', () async {
      answers['inspectSelf'] = (_) => identity('com.follow.clashx', 10, 'aa');
      answers['inspectPackage'] = (_) =>
          identity('com.follow.clashx', 11, 'aa');
      await platform().verify(File('/cache/update/1/a.apk'));
      expect(calls.last.arguments, {'path': '/cache/update/1/a.apk'});

      answers['inspectPackage'] = (_) =>
          identity('com.follow.clashx', 11, 'bb');
      await expectLater(
        platform().verify(File('/cache/update/1/a.apk')),
        _fails(UpdateErrorKind.identityMismatch),
      );

      answers['inspectPackage'] = (_) => null;
      await expectLater(
        platform().verify(File('/cache/update/1/a.apk')),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });

    test('maps the installer answers', () async {
      final file = File('/cache/update/1/a.apk');
      answers['installPackage'] = (_) => 'committed';
      expect(await platform().install(file), UpdateInstallResult.handedOff);
      answers['installPackage'] = (_) => 'permission';
      await expectLater(
        platform().install(file),
        _fails(UpdateErrorKind.installPermission),
      );
      answers['installPackage'] = (_) => 'busy';
      await expectLater(platform().install(file), _fails(UpdateErrorKind.busy));
    });

    test('reports installer verdicts that arrive later', () async {
      final verdicts = <(String, String?)>[];
      app.onPackageInstallStatus = (status, message) =>
          verdicts.add((status, message));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            app.methodChannel.name,
            app.methodChannel.codec.encodeMethodCall(
              const MethodCall('packageInstallStatus', {
                'status': 'failed',
                'message': 'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
              }),
            ),
            (_) {},
          );
      expect(verdicts, [('failed', 'INSTALL_FAILED_UPDATE_INCOMPATIBLE')]);
      app.onPackageInstallStatus = null;
    });
  });
}
