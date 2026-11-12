import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

const _platformProbeTimeout = Duration(seconds: 2);

class App {
  static App? _instance;
  late MethodChannel methodChannel;
  Function()? onExit;
  Function()? onPackagesChanged;
  void Function(VpnRefusal refusal)? onVpnPermissionDenied;
  final floatingKeyboard = ValueNotifier(false);

  App._internal() {
    methodChannel = const MethodChannel('$packageName/app');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'exit':
          if (onExit != null) {
            await onExit!();
          }
        case 'packagesChanged':
          onPackagesChanged?.call();
        case 'floatingImeChanged':
          floatingKeyboard.value = call.arguments as bool;
        case 'vpnPermissionDenied':
          final refusal = VpnRefusal.values.asNameMap()[call.arguments];
          if (refusal != null) {
            onVpnPermissionDenied?.call(refusal);
          }
        default:
          throw MissingPluginException();
      }
    });
  }

  factory App() {
    _instance ??= App._internal();
    return _instance!;
  }

  Future<bool?> moveTaskToBack() async {
    return methodChannel.invokeMethod<bool>('moveTaskToBack');
  }

  Future<String?> getAndroidId() async {
    return methodChannel.invokeMethod<String>('getAndroidId');
  }

  Future<List<Package>> getPackages() async {
    final packagesString = await methodChannel.invokeMethod<String>(
      'getPackages',
    );
    final List<dynamic> packagesRaw =
        (await packagesString?.decodeJson<List<dynamic>>()) ?? [];
    return packagesRaw.map((e) => Package.fromJson(e)).toSet().toList();
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    return await methodChannel.invokeMethod<bool>(
          'isInstalledAppsPermissionGranted',
        ) ??
        true;
  }

  Future<bool> requestInstalledAppsPermission() async {
    return await methodChannel.invokeMethod<bool>(
          'requestInstalledAppsPermission',
        ) ??
        false;
  }

  /// Android 17 drops traffic between the app and the local network until the
  /// user grants this; earlier versions answer true.
  Future<bool> requestLocalNetworkPermission() async {
    return await methodChannel.invokeMethod<bool>(
          'requestLocalNetworkPermission',
        ) ??
        false;
  }

  final Map<String, ImageProvider?> _packageIcons = {};
  final Map<String, Future<ImageProvider?>> _packageIconTasks = {};
  final TaskPool _packageIconPool = TaskPool(maxConcurrentIconLoads);

  ImageProvider? getCachedPackageIcon(String packageName) {
    return _packageIcons[packageName];
  }

  Future<ImageProvider?> getPackageIcon(String packageName) {
    if (_packageIcons.containsKey(packageName)) {
      return Future.value(_packageIcons[packageName]);
    }
    return _packageIconTasks[packageName] ??= _loadPackageIcon(packageName);
  }

  Future<ImageProvider?> _loadPackageIcon(String packageName) async {
    var icon = await _requestPackageIcon(packageName);
    if (icon == null && packageName.isNotEmpty) {
      icon = await getPackageIcon('');
    }
    _packageIcons[packageName] = icon;
    unawaited(_packageIconTasks.remove(packageName));
    return icon;
  }

  Future<ImageProvider?> _requestPackageIcon(String packageName) async {
    try {
      final path = await _packageIconPool.run(
        () => methodChannel.invokeMethod<String>('getPackageIcon', {
          'packageName': packageName,
        }),
      );
      if (path == null || path.isEmpty) {
        return null;
      }
      return FileImage(File(path));
    } catch (error) {
      commonPrint.log('getPackageIcon error: $error');
      return null;
    }
  }

  @visibleForTesting
  void clearPackageIconCache() {
    _packageIcons.clear();
    _packageIconTasks.clear();
  }

  Future<bool?> tip(String? message) async {
    return methodChannel.invokeMethod<bool>('tip', {'message': '$message'});
  }

  /// A vibration that grows from barely felt to full strength over [duration].
  Future<void> riseVibration(Duration duration) async {
    await methodChannel.invokeMethod<bool>('riseVibration', {
      'durationMs': duration.inMilliseconds,
    });
  }

  Future<void> stopVibration() async {
    await methodChannel.invokeMethod<bool>('stopVibration');
  }

  Future<void> setVibration(bool enabled) async {
    await methodChannel.invokeMethod<bool>('setVibration', {
      'enabled': enabled,
    });
  }

  Future<bool?> initShortcuts() async {
    return methodChannel.invokeMethod<bool>('initShortcuts', {
      'start': currentAppLocalizations.start,
      'stop': currentAppLocalizations.stop,
      'toggle': currentAppLocalizations.toggle,
    });
  }

  Future<bool?> updateExcludeFromRecents(bool value) async {
    return methodChannel.invokeMethod<bool>('updateExcludeFromRecents', {
      'value': value,
    });
  }

  Future<bool?> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openAppSettings');
  }

  Future<bool?> openVpnSettings() async {
    return methodChannel.invokeMethod<bool>('openVpnSettings');
  }

  Future<void> shareFile(String path, {required String mimeType}) async {
    await methodChannel.invokeMethod<bool>('shareFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  Future<AppExitInfo?> getLastExitInfo() async {
    try {
      final raw = await methodChannel
          .invokeMapMethod<String, Object?>('getLastExitInfo')
          .timeout(_platformProbeTimeout);
      return AppExitInfo.fromJson(raw);
    } catch (error) {
      commonPrint.log(
        'Failed to read the last process exit info: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }
}

final app = system.isAndroid ? App() : null;
