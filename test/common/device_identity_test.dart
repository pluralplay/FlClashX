import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dev.fluttercommunity.plus/device_info');

const _macInfo = {
  'computerName': 'Studio',
  'hostName': 'studio.local',
  'arch': 'arm64',
  'model': 'Mac14,13',
  'modelName': 'Mac Studio',
  'kernelVersion': 'Darwin 27.0.0',
  'osRelease': '26.0.1',
  'majorVersion': 26,
  'minorVersion': 0,
  'patchVersion': 1,
  'activeCPUs': 12,
  'memorySize': 68719476736,
  'cpuFrequency': 0,
  'systemGUID': '0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answerDeviceInfo(
    WidgetTester tester,
    Future<Map<String, Object?>> Function() answer,
  ) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'getDeviceInfo' ? await answer() : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );
  }

  test('the compact id is 16 upper-case hex digits of the SHA-256', () {
    expect(compactHwid('machine'), matches(RegExp(r'^[0-9A-F]{16}$')));
    expect(compactHwid('machine'), compactHwid('machine'));
    expect(compactHwid('machine'), isNot(compactHwid('other')));
    expect(
      compactHwid('0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0'),
      compactHwid('0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0'),
    );
  });

  testWidgets(
    'macOS sends the hashed system GUID with the OS, version and model',
    (tester) async {
      answerDeviceInfo(tester, () async => _macInfo);

      final headers = await DeviceIdentity().headers();

      expect(headers, {
        hwidHeader: compactHwid('0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0'),
        deviceOsHeader: 'macOS',
        deviceOsVersionHeader: '26.0.1',
        deviceModelHeader: 'Mac14,13',
      });
    },
    skip: !Platform.isMacOS,
  );

  testWidgets('the id is resolved once and then remembered', (tester) async {
    var asked = 0;
    answerDeviceInfo(tester, () async {
      asked++;
      return _macInfo;
    });
    final identity = DeviceIdentity();

    final first = await identity.headers();
    final second = await identity.headers();

    expect(second, first);
    expect(asked, 1);
  }, skip: !Platform.isMacOS);

  testWidgets('a platform without the plugin sends no device headers', (
    tester,
  ) async {
    answerDeviceInfo(tester, () async => throw MissingPluginException());

    expect(await DeviceIdentity().headers(), isEmpty);
  });
}
