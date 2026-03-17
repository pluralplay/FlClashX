import 'dart:async';
import 'dart:convert';

import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class VpnListener {
  void onDnsChanged(String dns) {}
}

class Vpn {

  factory Vpn() {
    _instance ??= Vpn._internal();
    return _instance!;
  }

  Vpn._internal() {
    methodChannel = const MethodChannel("vpn");
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "gc":
          clashCore.requestGc();
        case "getStartForegroundParams":
          if (handleGetStartForegroundParams != null) {
            return await handleGetStartForegroundParams!();
          }
          // Default handler for UI mode - get current proxy name from core
          return _getDefaultForegroundParams();
        case "status":
          return clashLibHandler?.getRunTime() != null;
        default:
          for (final listener in _listeners) {
            switch (call.method) {
              case "dnsChanged":
                final dns = call.arguments as String;
                listener.onDnsChanged(dns);
            }
          }
      }
    });
  }
  static Vpn? _instance;
  late MethodChannel methodChannel;
  FutureOr<String> Function()? handleGetStartForegroundParams;
  
  /// Cached server name for foreground notification (updated via updateServerName)
  String _cachedServerName = "";
  
  /// Cached profile info for foreground notification
  String _cachedProfileName = "FlClashX";
  String _cachedServiceName = "";
  
  /// Update cached server name (called from UI when proxy changes)
  void updateServerName(String serverName) {
    _cachedServerName = serverName;
  }
  
  /// Update cached profile info (called when profile changes or on init)
  void updateProfileInfo({
    required String profileName,
    required String serviceName,
  }) {
    _cachedProfileName = profileName;
    _cachedServiceName = serviceName;
  }
  
  /// Get cached server name
  String get cachedServerName => _cachedServerName;
  
  /// Get cached profile name
  String get cachedProfileName => _cachedProfileName;
  
  /// Get cached service name
  String get cachedServiceName => _cachedServiceName;
  
  /// Decode base64 string if needed
  String? _decodeBase64IfNeeded(String? value) {
    if (value == null || value.isEmpty) return value;
    try {
      final normalized = base64.normalize(value);
      return utf8.decode(base64.decode(normalized));
    } catch (e) {
      return value;
    }
  }

  /// Default foreground params when running in UI mode
  String _getDefaultForegroundParams() {
    try {
      final traffic = clashCore.getTraffic();
      final profile = globalState.config.currentProfile;
      final profileName = profile?.label ?? profile?.id ?? "FlClashX";
      
      // Resolve current proxy name using appController (always up-to-date via Riverpod)
      String? proxyName;
      try {
        final serverInfoGroupName = _decodeBase64IfNeeded(
          profile?.providerHeaders['flclashx-serverinfo'],
        );
        if (serverInfoGroupName != null && serverInfoGroupName.isNotEmpty) {
          proxyName = globalState.appController.getSelectedProxyName(serverInfoGroupName);
        }
      } catch (_) {}

      // Build title
      final serverDisplay = (proxyName ?? "").trim();
      final title = serverDisplay.isNotEmpty ? "$profileName / $serverDisplay" : profileName;

      // Service name for subtext from header flclashx-servicename
      String serviceName = "";
      try {
        String? svc = profile?.providerHeaders['flclashx-servicename'];
        if (svc != null && svc.isNotEmpty) {
          serviceName = _decodeBase64IfNeeded(svc)?.trim() ?? "";
        }
      } catch (_) {}
      
      return json.encode({
        "title": title,
        "server": serviceName,
        "content": "$traffic"
      });
    } catch (e) {
      return json.encode({
        "title": "FlClashX",
        "server": "",
        "content": ""
      });
    }
  }

  final ObserverList<VpnListener> _listeners = ObserverList<VpnListener>();

  Future<bool?> start(AndroidVpnOptions options) async => methodChannel.invokeMethod<bool>("start", {
      'data': json.encode(options),
    });

  Future<bool?> stop() async => methodChannel.invokeMethod<bool>("stop");

  /// Show subscription expiration notification
  Future<bool?> showSubscriptionNotification({
    required String title,
    required String message,
    required String actionLabel,
    required String actionUrl,
  }) async => methodChannel.invokeMethod<bool>("showSubscriptionNotification", {
    'title': title,
    'message': message,
    'actionLabel': actionLabel,
    'actionUrl': actionUrl,
  });

  void addListener(VpnListener listener) {
    _listeners.add(listener);
  }

  void removeListener(VpnListener listener) {
    _listeners.remove(listener);
  }
}

Vpn? get vpn {
  // On Android, we always need Vpn instance to handle method channel calls
  // from the VPN service (e.g., getStartForegroundParams)
  if (defaultTargetPlatform == TargetPlatform.android) {
    return Vpn();
  }
  // On other platforms, only create in service mode
  return globalState.isService ? Vpn() : null;
}
