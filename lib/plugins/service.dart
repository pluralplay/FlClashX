import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flclashx/state.dart';
import 'package:flutter/services.dart';

import '../clash/lib.dart';

class Service {

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Service._internal() {
    methodChannel = const MethodChannel("service");
  }
  static Service? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;

  Future<bool?> init() async => methodChannel.invokeMethod<bool>("init");

  Future<bool?> destroy() async => methodChannel.invokeMethod<bool>("destroy");

  Future<bool?> startVpn() async {
    final options = await clashLib?.getAndroidVpnOptions();
    return methodChannel.invokeMethod<bool>("startVpn", {
      'data': json.encode(options),
    });
  }

  Future<bool?> stopVpn() async => methodChannel.invokeMethod<bool>("stopVpn");
}

Service? get service => Platform.isAndroid && !globalState.isService ? Service() : null;
