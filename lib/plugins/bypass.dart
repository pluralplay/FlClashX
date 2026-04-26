import 'package:flutter/services.dart';

class ForegroundMonitor {
  static const _ch = MethodChannel('foreground_monitor');

  static Future<bool> hasPermission() async =>
      await _ch.invokeMethod<bool>('hasPermission') ?? false;

  static Future<void> requestPermission() =>
      _ch.invokeMethod('requestPermission');

  static Future<void> setBypassPackages(List<String> packages) =>
      _ch.invokeMethod('setBypassPackages', {'packages': packages});

  static Future<void> setVpnOptions(String optionsJson) =>
      _ch.invokeMethod('setVpnOptions', {'options': optionsJson});

  static Future<void> startMonitor() => _ch.invokeMethod('startMonitor');

  static Future<void> stopMonitor() => _ch.invokeMethod('stopMonitor');
}
