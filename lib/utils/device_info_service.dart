import 'package:package_info_plus/package_info_plus.dart';

class DeviceDetails {
  DeviceDetails({
    this.hwid,
    this.os,
    this.osVersion,
    this.model,
    this.appVersion,
  });
  final String? hwid;
  final String? os;
  final String? osVersion;
  final String? model;
  final String? appVersion;
}

class DeviceInfoService {
  static const _genericHwid =
      '3F2504E0-4F89-41D3-9A0C-0305E82C3301';

  Future<DeviceDetails> getDeviceDetails() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return DeviceDetails(
      hwid: _genericHwid,
      os: 'Windows',
      osVersion: '10.0.19045',
      model: 'Generic PC',
      appVersion: packageInfo.version,
    );
  }
}

