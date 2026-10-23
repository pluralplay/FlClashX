import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/linux_core_update.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/widgets/input.dart';

class CoreUpdater {
  factory CoreUpdater() {
    _instance ??= CoreUpdater._internal();
    return _instance!;
  }

  CoreUpdater._internal();

  static CoreUpdater? _instance;

  String? _cachedHash;
  DateTime? _cachedMtime;
  int? _cachedSize;

  /// SHA-256 of the core binary currently on disk. Cached by mtime+size so
  /// repeated helper pings don't rehash the file.
  Future<String?> calcCoreSha256() async {
    try {
      final file = File(appPath.corePath);
      final stat = await file.stat();
      if (_cachedHash != null &&
          stat.modified == _cachedMtime &&
          stat.size == _cachedSize) {
        return _cachedHash;
      }
      final digest = await sha256.bind(file.openRead()).first;
      _cachedMtime = stat.modified;
      _cachedSize = stat.size;
      _cachedHash = digest.toString();
      return _cachedHash;
    } catch (e) {
      commonPrint.log("calcCoreSha256 failed: $e");
      return null;
    }
  }

  /// Swap the core for a downloaded `.pending` binary. Must run before any core
  /// process is spawned: a running exe can't be deleted on Windows, and on
  /// macOS/Linux a swap after spawn leaves the whole session on the old core.
  Future<void> applyPending() async {
    final pending = File(await appPath.corePendingPath);
    if (!await pending.exists()) {
      return;
    }
    commonPrint.log("Applying pending core update...");
    try {
      if (Platform.isLinux) {
        await _applyLinuxPending(pending);
        return;
      }
      // Windows service mode: the core lives under Program Files, which the
      // unelevated app can't overwrite (rename -> access-denied). The SYSTEM
      // helper does the swap (stop + move + refresh allow-list hash) for us.
      if (Platform.isWindows) {
        final status = await windows?.checkService();
        if (status == WindowsHelperServiceStatus.running) {
          final ok = await request.replaceCoreByHelper(
            pending.path,
            appPath.corePath,
          );
          if (ok) {
            commonPrint.log("Pending core update applied via helper");
            return;
          }
          commonPrint.log("Helper swap failed, falling back to local swap");
        }
        // A helper-started core survives app restarts and holds the exe lock.
        await request.stopCoreByHelper();
      }
      // Read the setuid state BEFORE the old binary is deleted.
      final wasAuthorized = Platform.isMacOS && await system.checkIsAdmin();
      final target = File(appPath.corePath);
      if (await target.exists()) {
        for (var i = 0; i < 10; i++) {
          try {
            await target.delete();
            break;
          } catch (_) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
      await pending.rename(appPath.corePath);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', appPath.corePath]);
      }
      if (Platform.isWindows) {
        final status = await windows?.checkService();
        if (status != null && status != WindowsHelperServiceStatus.none) {
          await syncHelperAllowedHash();
        }
      }
      if (wasAuthorized) {
        await _restoreMacSetuid();
      }
      commonPrint.log("Pending core update applied successfully");
    } catch (e) {
      commonPrint.log("Failed to apply pending core update: $e");
    }
  }

  Future<void> _applyLinuxPending(File pending) async {
    final authorized = await system.checkIsAdmin();
    final digest = (await sha256.bind(pending.openRead()).first).toString();
    Future<ProcessResult> install({bool elevated = false, String? password}) =>
        installLinuxCore(
          source: pending.path,
          target: appPath.corePath,
          sha256: digest,
          preserveAuthorization: authorized,
          elevated: elevated,
          password: password,
        );

    // A portable, unprivileged core can be replaced without a password. A
    // setuid core must always be installed as root to keep TUN authorization.
    var result = authorized
        ? await install(elevated: true)
        : await install();
    if (result.exitCode != 0) {
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          title: appLocalizations.pleaseInputAdminPassword,
          value: '',
        ),
      );
      if (password == null) {
        commonPrint.log('Core update cancelled; keeping the current core');
        return;
      }
      result = await install(elevated: true, password: password);
    }
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Core installation failed: ${result.stderr}',
        appPath.corePath,
      );
    }
    await pending.delete();
    commonPrint.log('Pending core update applied successfully');
  }

  /// The helper service only launches a core whose SHA-256 matches its
  /// allow-list; keep that list in sync with the binary on disk. A plain write
  /// covers per-user installs; Program Files needs one UAC prompt.
  Future<void> syncHelperAllowedHash() async {
    final hash = await calcCoreSha256();
    if (hash == null) {
      return;
    }
    final path = appPath.allowedCoreHashPath;
    try {
      await File(path).writeAsString(hash, flush: true);
      commonPrint.log("helper allowed-hash updated");
    } catch (_) {
      final ok = windows?.runas("cmd.exe", '/c echo $hash> "$path"') ?? false;
      commonPrint.log("helper allowed-hash elevated write: $ok");
    }
  }

  /// TUN needs the core setuid-root (mirrors setCorePermissions in
  /// AppDelegate.swift). The fresh binary loses the bit, so re-request it in
  /// the update context; on cancel the Swift launch check prompts again later.
  Future<void> _restoreMacSetuid() async {
    final path = appPath.corePath.replaceAll("'", r"'\''");
    final script =
        'do shell script "chown root:admin \'$path\' && chmod +sx \'$path\'"'
        ' with administrator privileges';
    final res = await Process.run('osascript', ['-e', script]);
    if (res.exitCode != 0) {
      commonPrint.log("core setuid restore declined/failed: ${res.stderr}");
    }
  }
}

final coreUpdater = CoreUpdater();
