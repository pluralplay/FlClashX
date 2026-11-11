import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proxy_platform_interface.dart';

class MethodChannelProxy extends ProxyPlatform {
  static const _startProxyMethod = 'StartProxy';
  static const _stopProxyMethod = 'StopProxy';
  static const _clearStaleProxyMethod = 'ClearStaleProxy';

  @visibleForTesting
  final methodChannel = const MethodChannel('proxy');

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) async {
    return await methodChannel.invokeMethod<bool>(_startProxyMethod, {
          'port': port,
          'bypassDomain': bypassDomain,
        }) ??
        false;
  }

  @override
  Future<bool> stopProxy() async {
    return await methodChannel.invokeMethod<bool>(_stopProxyMethod) ?? false;
  }

  @override
  Future<bool> clearStaleProxy() async {
    return await methodChannel.invokeMethod<bool>(_clearStaleProxyMethod) ??
        false;
  }
}
