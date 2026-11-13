import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/identity.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:path/path.dart' as p;

enum UpdateInstallResult { exiting, handedOff, openedImage }

typedef ExitApp = Future<void> Function();

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) => Process.run(executable, arguments, environment: environment);

abstract class UpdatePlatform {
  UpdateTarget get target;

  Future<void> verify(File file);

  Future<UpdateInstallResult> install(File file);
}

/// What the dialog offers when the platform could not be worked out: the
/// release page alone.
class ManualUpdatePlatform implements UpdatePlatform {
  @override
  final UpdateTarget target;

  const ManualUpdatePlatform([
    this.target = const UpdateTarget(UpdateInstallKind.unsupported, []),
  ]);

  @override
  Future<void> verify(File file) => throw UnsupportedError('manual update');

  @override
  Future<UpdateInstallResult> install(File file) =>
      throw UnsupportedError('manual update');
}

String? desktopArch(Abi abi) => switch (abi) {
  Abi.macosArm64 || Abi.windowsArm64 || Abi.linuxArm64 => 'arm64',
  Abi.macosX64 || Abi.windowsX64 || Abi.linuxX64 => 'amd64',
  _ => null,
};

Future<UpdatePlatform> resolveUpdatePlatform({required ExitApp exitApp}) async {
  final executable = Platform.resolvedExecutable;
  final arch = desktopArch(Abi.current());
  final archs = [?arch];
  if (Platform.isAndroid) {
    final app = App();
    return AndroidUpdatePlatform(
      app: app,
      target: UpdateTarget(
        UpdateInstallKind.android,
        androidUpdateArchs(await app.getSupportedAbis()),
      ),
    );
  }
  if (Platform.isMacOS) {
    return MacosUpdatePlatform(
      bundle: macosBundleOf(executable),
      archs: archs,
      run: runProcess,
      exitApp: exitApp,
    );
  }
  if (Platform.isWindows) {
    final installed = await File(
      p.join(p.dirname(executable), 'unins000.exe'),
    ).exists();
    return WindowsUpdatePlatform(
      executable: executable,
      target: UpdateTarget(
        installed ? UpdateInstallKind.windows : UpdateInstallKind.unsupported,
        archs,
      ),
      run: runProcess,
      exitApp: exitApp,
    );
  }
  final environment = Platform.environment;
  return LinuxUpdatePlatform(
    target: UpdateTarget(
      await detectLinuxInstall(
        executable: executable,
        environment: environment,
        run: runProcess,
      ),
      archs,
    ),
    appImage: environment['APPIMAGE'],
    run: runProcess,
    exitApp: exitApp,
  );
}

String macosBundleOf(String executable) =>
    p.dirname(p.dirname(p.dirname(executable)));

const _optDirs = ['/opt/FlClashX', '/opt/FlClashXPre'];

/// An AUR package unpacks the .deb under /usr/lib, where only pacman may
/// replace it.
Future<UpdateInstallKind> detectLinuxInstall({
  required String executable,
  required Map<String, String> environment,
  required ProcessRunner run,
}) async {
  if ((environment['APPIMAGE'] ?? '').isNotEmpty) {
    return UpdateInstallKind.appImage;
  }
  if (p.isWithin('/usr/lib', executable)) {
    return UpdateInstallKind.packageManager;
  }
  if (!_optDirs.any((dir) => p.isWithin(dir, executable))) {
    return UpdateInstallKind.unsupported;
  }
  if (await _succeeds(run, 'dpkg-query', ['-S', executable])) {
    return UpdateInstallKind.deb;
  }
  if (await _succeeds(run, 'rpm', ['-qf', executable])) {
    return UpdateInstallKind.rpm;
  }
  return UpdateInstallKind.unsupported;
}

Future<bool> _succeeds(
  ProcessRunner run,
  String executable,
  List<String> arguments,
) async {
  try {
    return (await run(executable, arguments)).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<void> _mustRun(
  ProcessRunner run,
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final ProcessResult result;
  try {
    result = await run(executable, arguments, environment: environment);
  } on ProcessException catch (error) {
    throw UpdateException(UpdateErrorKind.installFailed, error.message);
  }
  if (result.exitCode != 0) {
    throw UpdateException(
      UpdateErrorKind.installFailed,
      '${p.basename(executable)}: ${'${result.stderr}'.trim()}',
    );
  }
}

/// Starts [target] once this process has exited, so a single-instance lock
/// held by it cannot turn the new copy away. Paths reach the shell as
/// arguments, never as script text.
Future<void> _relaunchAfterExit(String command, List<String> arguments) {
  return Process.start('/bin/sh', [
    '-c',
    'while kill -0 "\$1" 2>/dev/null; do sleep 0.2; done; $command',
    'sh',
    '$pid',
    ...arguments,
  ], mode: ProcessStartMode.detached);
}

String _randomSuffix() => Random.secure().nextInt(1 << 32).toRadixString(36);

class AndroidUpdatePlatform implements UpdatePlatform {
  final App app;

  @override
  final UpdateTarget target;

  AndroidUpdatePlatform({required this.app, required this.target});

  @override
  Future<void> verify(File file) async {
    final installed = await app.inspectSelf();
    final candidate = await app.inspectPackage(file.path);
    if (installed == null || candidate == null) {
      throw const UpdateException(UpdateErrorKind.identityMismatch, 'apk');
    }
    checkAndroidUpdate(
      installed: AndroidPackageIdentity.fromMap(installed),
      candidate: AndroidPackageIdentity.fromMap(candidate),
    );
  }

  @override
  Future<UpdateInstallResult> install(File file) async {
    final status = await app.installPackage(file.path);
    return switch (status) {
      'committed' => UpdateInstallResult.handedOff,
      'permission' => throw const UpdateException(
        UpdateErrorKind.installPermission,
      ),
      'busy' => throw const UpdateException(UpdateErrorKind.busy),
      _ => throw UpdateException(UpdateErrorKind.installFailed, status),
    };
  }
}

class WindowsUpdatePlatform implements UpdatePlatform {
  final String executable;
  final ProcessRunner run;
  final ExitApp exitApp;

  @override
  final UpdateTarget target;

  WindowsUpdatePlatform({
    required this.executable,
    required this.target,
    required this.run,
    required this.exitApp,
  });

  static const _setupVariable = 'FLCLASHX_UPDATE_SETUP';

  @override
  Future<void> verify(File file) =>
      verifyWindowsUpdate(running: executable, candidate: file.path, run: run);

  /// The setup asks for elevation, which CreateProcess refuses outright;
  /// Start-Process goes through ShellExecute and raises the UAC prompt, and
  /// fails when the user declines it, before the app has quit.
  @override
  Future<UpdateInstallResult> install(File file) async {
    await _mustRun(
      run,
      windowsPowerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Start-Process -FilePath \$env:$_setupVariable',
      ],
      environment: {_setupVariable: file.path},
    );
    await exitApp();
    return UpdateInstallResult.exiting;
  }
}

class MacosUpdatePlatform implements UpdatePlatform {
  final String bundle;
  final ProcessRunner run;
  final ExitApp exitApp;

  @override
  final UpdateTarget target;

  MacosUpdatePlatform({
    required this.bundle,
    required List<String> archs,
    required this.run,
    required this.exitApp,
  }) : target = UpdateTarget(UpdateInstallKind.macos, archs);

  String _stagedOf(File image) =>
      p.join(image.parent.path, 'staged', p.basename(bundle));

  /// Checks a copy of the app taken off the read-only image, which is what
  /// [install] moves into place.
  @override
  Future<void> verify(File file) async {
    final mount = Directory(p.join(file.parent.path, 'mount'));
    await mount.create();
    await _mustRun(run, '/usr/bin/hdiutil', [
      'attach',
      '-readonly',
      '-nobrowse',
      '-noautoopen',
      '-mountpoint',
      mount.path,
      file.path,
    ]);
    final staged = _stagedOf(file);
    await _removeQuietly(p.dirname(staged));
    try {
      final apps = await mount
          .list(followLinks: false)
          .where(
            (entity) => entity is Directory && entity.path.endsWith('.app'),
          )
          .toList();
      if (apps.length != 1) {
        throw UpdateException(
          UpdateErrorKind.identityMismatch,
          '${apps.length} apps',
        );
      }
      await Directory(p.dirname(staged)).create(recursive: true);
      await _mustRun(run, '/usr/bin/ditto', [apps.single.path, staged]);
    } finally {
      await _detach(mount.path);
    }
    await verifyMacosUpdate(running: bundle, candidate: staged, run: run);
  }

  /// A mount left behind would also keep the next download from purging the
  /// cache it sits in.
  Future<void> _detach(String mount) async {
    for (final arguments in [
      ['detach', mount],
      ['detach', mount, '-force'],
    ]) {
      if ((await run('/usr/bin/hdiutil', arguments)).exitCode == 0) {
        return;
      }
    }
    throw const UpdateException(UpdateErrorKind.installFailed, 'detach');
  }

  /// Swaps the bundle while the app runs from the old one, which macOS
  /// allows, and opens the new one once this process is gone. Where the
  /// bundle cannot be replaced, the image goes to Finder instead.
  @override
  Future<UpdateInstallResult> install(File file) async {
    final parent = p.dirname(bundle);
    final name = p.basename(bundle);
    final suffix = _randomSuffix();
    final beside = p.join(parent, '.$name.update-$suffix');
    final old = p.join(parent, '.$name.old-$suffix');
    try {
      await _mustRun(run, '/usr/bin/ditto', [_stagedOf(file), beside]);
    } catch (_) {
      await _removeQuietly(beside);
      await _mustRun(run, '/usr/bin/open', [file.path]);
      return UpdateInstallResult.openedImage;
    }
    try {
      await verifyMacosUpdate(running: bundle, candidate: beside, run: run);
    } catch (_) {
      await _removeQuietly(beside);
      rethrow;
    }
    try {
      await Directory(bundle).rename(old);
    } catch (_) {
      await _removeQuietly(beside);
      await _mustRun(run, '/usr/bin/open', [file.path]);
      return UpdateInstallResult.openedImage;
    }
    try {
      await Directory(beside).rename(bundle);
    } catch (error) {
      try {
        await Directory(old).rename(bundle);
      } catch (_) {
        throw UpdateException(UpdateErrorKind.installFailed, 'restore $old');
      }
      await _removeQuietly(beside);
      throw UpdateException(UpdateErrorKind.installFailed, '$error');
    }
    await _relaunchAfterExit('/usr/bin/open "\$2" && rm -rf "\$3"', [
      bundle,
      old,
    ]);
    await exitApp();
    return UpdateInstallResult.exiting;
  }
}

class LinuxUpdatePlatform implements UpdatePlatform {
  final String? appImage;
  final ProcessRunner run;
  final ExitApp exitApp;

  @override
  final UpdateTarget target;

  LinuxUpdatePlatform({
    required this.target,
    required this.appImage,
    required this.run,
    required this.exitApp,
  });

  /// Linux builds carry no signature to compare; the host allowlist and the
  /// release checksum are what vouch for them.
  @override
  Future<void> verify(File file) async {}

  @override
  Future<UpdateInstallResult> install(File file) async {
    final appImage = this.appImage;
    if (target.kind != UpdateInstallKind.appImage || appImage == null) {
      await _mustRun(run, 'xdg-open', [file.path]);
      return UpdateInstallResult.handedOff;
    }
    final staged = p.join(
      p.dirname(appImage),
      '.${p.basename(appImage)}.update-${_randomSuffix()}',
    );
    try {
      await file.copy(staged);
      await _mustRun(run, 'chmod', ['755', staged]);
      await File(staged).rename(appImage);
    } on FileSystemException catch (error) {
      await _removeQuietly(staged);
      throw UpdateException(UpdateErrorKind.installFailed, error.message);
    } catch (_) {
      await _removeQuietly(staged);
      rethrow;
    }
    await _relaunchAfterExit(r'exec "$2"', [appImage]);
    await exitApp();
    return UpdateInstallResult.exiting;
  }
}

Future<void> _removeQuietly(String path) async {
  try {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  } on FileSystemException {
    return;
  }
}
