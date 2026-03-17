import 'dart:io';
import 'package:flutter/services.dart';

class StatusBarManager {
  static const MethodChannel _channel = MethodChannel('status_bar_icon');

  static Future<void> updateIcon({required bool isConnected}) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('updateIcon', {
        'isConnected': isConnected,
      });
    } catch (e) {
      // silent
    }
  }
}
