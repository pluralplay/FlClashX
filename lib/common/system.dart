import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/plugins/app.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/input.dart';
import 'package:flutter/services.dart';

class System {

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  System._internal();
  static System? _instance;
  List<String>? originDns;

  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  Future<bool> get isAndroidTV async {
    if (!Platform.isAndroid) return false;
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    return deviceInfo.systemFeatures.contains('android.software.leanback');
  }

  Future<int> get version async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return switch (Platform.operatingSystem) {
      "macos" => (deviceInfo as MacOsDeviceInfo).majorVersion,
      "android" => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      "windows" => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0
    };
  }

  Future<bool> checkIsAdmin() async {
    final corePath = appPath.corePath.replaceAll(' ', r'\\ ');
    if (Platform.isWindows) {
      final result = await windows?.checkService();
      return result == WindowsHelperServiceStatus.running;
    } else if (Platform.isMacOS) {
      final result = await Process.run('stat', ['-f', '%Su:%Sg %Sp', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:admin') && output.contains('rws')) {
        return true;
      }
      return false;
    } else if (Platform.isLinux) {
      final result = await Process.run('stat', ['-c', '%U:%G %A', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:') && output.contains('rws')) {
        return true;
      }
      return false;
    }
    return true;
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (Platform.isAndroid) {
      return AuthorizeCode.error;
    }

    if (Platform.isMacOS) {
      return AuthorizeCode.none;
    }

    final corePath = appPath.corePath.replaceAll(' ', r'\\ ');
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (Platform.isWindows) {
      // First, try to start existing service without UAC
      final startedWithoutUac = await windows?.tryStartExistingService();
      if (startedWithoutUac == true) {
        return AuthorizeCode.success;
      }
      
      // Service not installed or couldn't start - need to install with UAC
      final result = await windows?.installService();
      if (result == true) {
        return AuthorizeCode.success;
      }
      return AuthorizeCode.error;
    } else if (Platform.isLinux) {
      final shell = Platform.environment['SHELL'] ?? 'bash';
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          title: appLocalizations.pleaseInputAdminPassword,
          value: '',
        ),
      );
      final arguments = [
        "-c",
        'echo "$password" | sudo -S chown root:root "$corePath" && echo "$password" | sudo -S chmod +sx "$corePath"'
      ];
      final result = await Process.run(shell, arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<String?> getMacOSDefaultServiceName() async {
    if (!Platform.isMacOS) {
      return null;
    }
    final result = await Process.run('route', ['-n', 'get', 'default']);
    final output = result.stdout.toString();
    final deviceLine = output
        .split('\n')
        .firstWhere((s) => s.contains('interface:'), orElse: () => "");
    final lineSplits = deviceLine.trim().split(' ');
    if (lineSplits.length != 2) {
      return null;
    }
    final device = lineSplits[1];
    final serviceResult = await Process.run(
      'networksetup',
      ['-listnetworkserviceorder'],
    );
    final serviceResultOutput = serviceResult.stdout.toString();
    final currentService = serviceResultOutput.split('\n\n').firstWhere(
          (s) => s.contains("Device: $device"),
          orElse: () => "",
        );
    if (currentService.isEmpty) {
      return null;
    }
    final currentServiceNameLine = currentService.split("\n").firstWhere(
        (line) => RegExp(r'^\(\d+\).*').hasMatch(line),
        orElse: () => "");
    final currentServiceNameLineSplits =
        currentServiceNameLine.trim().split(' ');
    if (currentServiceNameLineSplits.length < 2) {
      return null;
    }
    return currentServiceNameLineSplits[1];
  }

  Future<List<String>?> getMacOSOriginDns() async {
    if (!Platform.isMacOS) {
      return null;
    }
    final deviceServiceName = await getMacOSDefaultServiceName();
    if (deviceServiceName == null) {
      return null;
    }
    final result = await Process.run(
      'networksetup',
      ['-getdnsservers', deviceServiceName],
    );
    final output = result.stdout.toString().trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      originDns = [];
    } else {
      originDns = output.split("\n");
    }
    return originDns;
  }

  Future<void> setMacOSDns(bool restore) async {
    if (!Platform.isMacOS) {
      return;
    }
    final serviceName = await getMacOSDefaultServiceName();
    if (serviceName == null) {
      return;
    }
    List<String>? nextDns;
    if (restore) {
      nextDns = originDns;
    } else {
      final originDns = await system.getMacOSOriginDns();
      if (originDns == null) {
        return;
      }
      const needAddDns = "1.1.1.1"; // Cloudflare DNS
      if (originDns.contains(needAddDns)) {
        return;
      }
      nextDns = List.from(originDns)..add(needAddDns);
    }
    if (nextDns == null) {
      return;
    }
    await Process.run(
      'networksetup',
      [
        '-setdnsservers',
        serviceName,
        if (nextDns.isNotEmpty) ...nextDns,
        if (nextDns.isEmpty) "Empty",
      ],
    );
  }

  Future<void> back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  Future<void> exit() async {
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    }
    await window?.close();
  }
}

final system = System();
