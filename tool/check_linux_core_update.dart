// Standalone Linux filesystem regression checks:
//   dart tool/check_linux_core_update.dart
// Run once as a normal user and once as root in a disposable environment to
// cover both permission-denied and setuid preservation. Only temp files change.
import 'dart:io';

// Keep this runnable with a bare Dart SDK, without resolving Flutter packages.
// ignore: avoid_relative_lib_imports
import '../lib/common/linux_core_update.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<String> digest(File file) async {
  final result = await Process.run('sha256sum', [file.path]);
  check(result.exitCode == 0, 'sha256sum failed');
  return (result.stdout as String).split(' ').first;
}

Future<String> metadata(String path) async {
  final result = await Process.run('stat', ['-c', '%u:%g:%a', path]);
  check(result.exitCode == 0, 'stat failed');
  return (result.stdout as String).trim();
}

Future<void> main() async {
  if (!Platform.isLinux) throw UnsupportedError('Linux only');
  final uid = await Process.run('id', ['-u']);
  final root = (uid.stdout as String).trim() == '0';
  final directory = await Directory.systemTemp.createTemp('flclash-update-');
  try {
    // Shell metacharacters and whitespace must remain literal path characters.
    final staging =
        await Directory('${directory.path}/download \' \$(false)').create();
    final install =
        await Directory('${directory.path}/install \' \$(false)').create();
    final source = await File('${staging.path}/FlClashCore.pending')
        .writeAsString('new core\n');
    final target =
        await File('${install.path}/FlClashCore').writeAsString('old core\n');
    await Process.run('chmod', ['755', target.path]);
    final directoryBefore = await metadata(install.path);

    Future<ProcessResult> update({String? hash, bool authorized = false}) =>
        installLinuxCore(
          source: source.path,
          target: target.path,
          sha256: hash ?? '',
          preserveAuthorization: authorized,
          elevated: authorized && root,
        );

    var result = await update(hash: '0' * 64);
    check(result.exitCode != 0, 'Bad digest was accepted');
    check(await target.readAsString() == 'old core\n', 'Old core lost');
    check(await source.exists(), 'Pending update lost on failure');
    check(await install.list().length == 1, 'Failed staging was not cleaned');
    print('PASS: digest mismatch keeps the current core and pending update');

    final hash = await digest(source);
    final alias = Link('${staging.path}/alias');
    await alias.create(source.path);
    result = await installLinuxCore(
      source: alias.path,
      target: target.path,
      sha256: hash,
      preserveAuthorization: false,
    );
    check(result.exitCode != 0, 'Symlink source was accepted');
    check(await target.readAsString() == 'old core\n', 'Old core lost');
    print('PASS: symlink source is rejected without replacing the core');

    if (!root) {
      await Process.run('chmod', ['555', install.path]);
      try {
        result = await update(hash: hash);
        check(result.exitCode != 0, 'Read-only install unexpectedly succeeded');
        check(await target.readAsString() == 'old core\n', 'Old core lost');
        check(await source.exists(), 'Pending update lost on permission error');
      } finally {
        await Process.run('chmod', ['755', install.path]);
      }
      print('PASS: unwritable install keeps both binaries intact');
    }

    // Hold the old inode open: a successful swap must leave those bytes intact.
    final previous = await target.open();
    try {
      result = await update(hash: hash);
      check(result.exitCode == 0, 'Install failed: ${result.stderr}');
      check(
          await target.readAsString() == 'new core\n', 'Wrong installed bytes');
      check(String.fromCharCodes(await previous.read(100)) == 'old core\n',
          'The old inode was overwritten instead of atomically replaced');
    } finally {
      await previous.close();
    }
    check((await metadata(target.path)).endsWith(':755'), 'Wrong core mode');
    check(await metadata(install.path) == directoryBefore,
        'Install directory permissions changed');
    check(await source.exists(),
        'Installer removed source before caller cleanup');
    check(
        await install.list().length == 1, 'Successful staging was not cleaned');
    print(
        'PASS: atomic portable install handles quoted paths and keeps directory permissions');

    if (root) {
      result = await update(hash: hash, authorized: true);
      check(
          result.exitCode == 0, 'Authorized install failed: ${result.stderr}');
      check(await metadata(target.path) == '0:0:6755',
          'Root ownership or TUN authorization lost');
      check(await metadata(install.path) == directoryBefore,
          'Privileged install changed directory permissions');
      print(
          'PASS: privileged install preserves root ownership and TUN mode 6755');
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
