import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

/// A user who changed everything the profile may take over.
const _tuned = PatchClashConfig(
  mixedPort: 1080,
  port: 8080,
  socksPort: 1081,
  redirPort: 7892,
  tproxyPort: 7893,
  allowLan: true,
  ipv6: true,
  mode: Mode.global,
  logLevel: LogLevel.debug,
  findProcessMode: FindProcessMode.always,
  interfaceNameMode: InterfaceNameMode.custom,
  interfaceName: 'en1',
  routingMark: 6666,
  tcpConcurrent: false,
  unifiedDelay: false,
  keepAliveInterval: 10,
  keepAliveIdle: 5,
  disableKeepAlive: true,
  externalController: '0.0.0.0:9091',
  secret: 'kept',
  geodataLoader: GeodataLoader.standard,
  geoAutoUpdate: true,
  geoUpdateInterval: 6,
  globalUa: 'mine',
  tun: Tun(enable: true, device: 'utun9', stack: TunStack.gvisor),
);

void main() {
  test(
    'a profile naming nothing leaves the sticky keys and resets the rest',
    () {
      final synced = syncProfileSettings(_tuned, const {}, const []);

      expect(synced.mode, Mode.global);
      expect(synced.tun.enable, isTrue);
      expect(synced.secret, isEmpty);
      expect(synced.externalController, isEmpty);
      expect(synced.copyWith(mode: Mode.rule), const PatchClashConfig());
    },
  );

  test('every named key is taken, converted to the app types', () {
    final synced = syncProfileSettings(
      const PatchClashConfig(),
      const {
        'mixed-port': 7000,
        'socks-port': 7001,
        'allow-lan': true,
        'ipv6': true,
        'mode': 'direct',
        'log-level': 'warning',
        'find-process-mode': 'strict',
        'interface-name': 'eth0',
        'routing-mark': 255,
        'tcp-concurrent': false,
        'unified-delay': false,
        'keep-alive-interval': 15,
        'keep-alive-idle': 7,
        'disable-keep-alive': true,
        'external-controller': '0.0.0.0:9097',
        'secret': 's3cret',
        'geodata-loader': 'standard',
        'geo-auto-update': true,
        'geo-update-interval': 48,
        'geox-url': {'geoip': 'https://geo.example/geoip.dat', 'mmdb': ''},
        'global-ua': 'clash.meta',
        'tun': {'enable': true, 'device': 'utun5', 'stack': 'gVisor'},
      },
      const [
        'mixed-port',
        'socks-port',
        'allow-lan',
        'ipv6',
        'mode',
        'log-level',
        'find-process-mode',
        'interface-name',
        'routing-mark',
        'tcp-concurrent',
        'unified-delay',
        'keep-alive-interval',
        'keep-alive-idle',
        'disable-keep-alive',
        'external-controller',
        'secret',
        'geodata-loader',
        'geo-auto-update',
        'geo-update-interval',
        'geox-url',
        'global-ua',
        'tun',
        'tun.enable',
        'tun.device',
        'tun.stack',
      ],
    );

    expect(synced.mixedPort, 7000);
    expect(synced.socksPort, 7001);
    expect(synced.allowLan, isTrue);
    expect(synced.ipv6, isTrue);
    expect(synced.mode, Mode.direct);
    expect(synced.logLevel, LogLevel.warning);
    expect(synced.findProcessMode, FindProcessMode.always);
    expect(synced.interfaceNameMode, InterfaceNameMode.custom);
    expect(synced.interfaceName, 'eth0');
    expect(synced.routingMark, 255);
    expect(synced.tcpConcurrent, isFalse);
    expect(synced.unifiedDelay, isFalse);
    expect(synced.keepAliveInterval, 15);
    expect(synced.keepAliveIdle, 7);
    expect(synced.disableKeepAlive, isTrue);
    expect(synced.externalController, '0.0.0.0:9097');
    expect(synced.secret, 's3cret');
    expect(synced.geodataLoader, GeodataLoader.standard);
    expect(synced.geoAutoUpdate, isTrue);
    expect(synced.geoUpdateInterval, 48);
    expect(synced.geoXUrl[GeoResource.GEOIP], 'https://geo.example/geoip.dat');
    expect(synced.geoXUrl[GeoResource.MMDB], defaultGeoXUrl[GeoResource.MMDB]);
    expect(synced.globalUa, 'clash.meta');
    expect(synced.tun.enable, isTrue);
    expect(synced.tun.device, 'utun5');
    expect(synced.tun.stack, TunStack.gvisor);
  });

  test('a key named with a value nothing answers to counts as absent', () {
    final synced = syncProfileSettings(
      _tuned,
      const {
        'mixed-port': 70000,
        'log-level': 'loud',
        'mode': 'tunnel',
        'tun': {'stack': 'kernel', 'enable': 'yes'},
        'allow-lan': 'true',
      },
      const [
        'mixed-port',
        'log-level',
        'mode',
        'tun.stack',
        'tun.enable',
        'allow-lan',
      ],
    );

    expect(synced.mixedPort, defaultMixedPort);
    expect(synced.logLevel, LogLevel.error);
    expect(synced.mode, Mode.global);
    expect(synced.tun.stack, TunStack.mips);
    expect(synced.tun.enable, isTrue);
    expect(synced.allowLan, isFalse);
  });

  test('an empty interface name or controller means off', () {
    final synced = syncProfileSettings(
      _tuned,
      const {'interface-name': '', 'external-controller': '', 'global-ua': ''},
      const ['interface-name', 'external-controller', 'global-ua'],
    );

    expect(synced.interfaceNameMode, InterfaceNameMode.clear);
    expect(synced.externalController, isEmpty);
    expect(synced.globalUa, isNull);
  });

  test('a mode the panel took away is not taken from the file either', () {
    final synced = syncProfileSettings(
      const PatchClashConfig(),
      const {'mode': 'global'},
      const ['mode'],
      modes: const [Mode.rule, Mode.direct],
    );

    expect(synced.mode, Mode.rule);
  });

  test('the settings the sync never touches survive', () {
    final tuned = _tuned.copyWith(
      dnsOverrideKeys: {DnsOverrideKey.nameserver},
      hosts: {'a.example': '10.0.0.1'},
      tun: _tuned.tun.copyWith(mtu: 1500),
    );

    final synced = syncProfileSettings(tuned, const {}, const []);

    expect(synced.dnsOverrideKeys, {DnsOverrideKey.nameserver});
    expect(synced.hosts, {'a.example': '10.0.0.1'});
    expect(synced.tun.mtu, 1500);
  });
}
