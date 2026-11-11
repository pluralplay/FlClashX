import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32_registry/win32_registry.dart';

import 'print.dart';

const hwidHeader = 'x-hwid';
const deviceOsHeader = 'x-device-os';
const deviceOsVersionHeader = 'x-ver-os';
const deviceModelHeader = 'x-device-model';

const _machineGuidKey = r'SOFTWARE\Microsoft\Cryptography';
const _compactHwidLength = 16;

/// What a panel is told about this device, as request headers: a stable
/// hardware id and the OS, its version and the model, those present.
class DeviceIdentity {
  DeviceIdentity({DeviceInfoPlugin? plugin, Future<String?>? androidId})
    : _plugin = plugin ?? DeviceInfoPlugin(),
      _androidId = androidId;

  final DeviceInfoPlugin _plugin;
  final Future<String?>? _androidId;
  Future<Map<String, String>>? _headers;

  /// Resolved once per run; nothing is persisted, since the same inputs give
  /// the same id again.
  Future<Map<String, String>> headers() => _headers ??= _resolve();

  Future<Map<String, String>> _resolve() async {
    try {
      final (id, os, version, model) = await _platformDetails();
      final hwid = id == null || id.isEmpty
          ? null
          : Platform.isAndroid
          ? id
          : compactHwid(id);
      return {
        hwidHeader: ?hwid,
        deviceOsHeader: ?os,
        if (version != null && version.isNotEmpty)
          deviceOsVersionHeader: version,
        if (model != null && model.isNotEmpty) deviceModelHeader: model,
      };
    } catch (error) {
      commonPrint.log('device identity unavailable: $error');
      return const {};
    }
  }

  Future<(String?, String?, String?, String?)> _platformDetails() async {
    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;
      final id = await (_androidId ?? app?.getAndroidId() ?? _noId);
      return (
        id != null && id.isNotEmpty
            ? id
            : '${info.brand}-${info.device}-${info.hardware}-${info.id}',
        'Android',
        info.version.release,
        '${info.manufacturer} ${info.model}',
      );
    }
    if (Platform.isWindows) {
      final info = await _plugin.windowsInfo;
      return (
        _machineGuid() ??
            '${info.computerName}-${info.deviceId}-${info.productId}',
        'Windows',
        info.displayVersion,
        info.productName,
      );
    }
    if (Platform.isMacOS) {
      final info = await _plugin.macOsInfo;
      return (
        info.systemGUID ?? '${info.model}-${info.computerName}',
        'macOS',
        info.osRelease,
        info.model,
      );
    }
    if (Platform.isLinux) {
      final info = await _plugin.linuxInfo;
      return (
        info.machineId ?? '${info.id}-${info.name}',
        'Linux',
        info.versionId,
        info.name,
      );
    }
    return (null, null, null, null);
  }

  String? _machineGuid() {
    try {
      final key = LOCAL_MACHINE.open(_machineGuidKey);
      try {
        return switch (key.getValue('MachineGuid')) {
          StringValue(:final value) => value,
          _ => null,
        };
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }
}

/// The first 16 hex digits of the SHA-256 of [id], upper-cased: the panel
/// sees a short opaque token, never the machine id itself.
@visibleForTesting
String compactHwid(String id) => sha256
    .convert(utf8.encode(id))
    .toString()
    .substring(0, _compactHwidLength)
    .toUpperCase();

final Future<String?> _noId = Future.value();

DeviceIdentity deviceIdentity = DeviceIdentity();
