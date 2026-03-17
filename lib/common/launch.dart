import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'system.dart';

class AutoLaunch {

  factory AutoLaunch() {
    _instance ??= AutoLaunch._internal();
    return _instance!;
  }

  AutoLaunch._internal() {
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }
  static AutoLaunch? _instance;

  Future<bool> get isEnable async => launchAtStartup.isEnabled();

  Future<bool> enable() async => launchAtStartup.enable();

  Future<bool> disable() async => launchAtStartup.disable();

  Future<void> updateStatus(bool isAutoLaunch) async {
    if (kDebugMode) {
      return;
    }
    if (await isEnable == isAutoLaunch) return;
    if (isAutoLaunch == true) {
      enable();
    } else {
      disable();
    }
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;
