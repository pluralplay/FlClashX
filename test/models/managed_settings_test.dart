import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  test('only the keys a subscription may take over count as managed', () {
    expect(
      managedClashKeysOf([
        'mixed-port',
        'tun.stack',
        'tun.enable',
        'dns',
        'proxies',
        'mode',
      ]),
      {'clash.mixed-port', 'clash.tun.stack', 'clash.tun.enable', 'clash.mode'},
    );
  });

  test('an owned mode and tun switch keep what the user chose', () {
    const mine = PatchClashConfig(mode: Mode.global, tun: Tun(enable: false));
    const synced = PatchClashConfig(tun: Tun(enable: true));

    final kept = keepOwnedSettings(mine, synced, {
      'clash.mode',
      'clash.tun.enable',
    });

    expect(kept.mode, Mode.global);
    expect(kept.tun.enable, isFalse);
  });

  test('owned settings keep the value the user chose through a sync', () {
    const mine = PatchClashConfig(
      mixedPort: 1080,
      logLevel: LogLevel.debug,
      interfaceNameMode: InterfaceNameMode.custom,
      interfaceName: 'en1',
      tun: Tun(stack: TunStack.gvisor),
    );
    const theirs = PatchClashConfig(
      mixedPort: 7000,
      logLevel: LogLevel.warning,
      allowLan: true,
      tun: Tun(stack: TunStack.system),
    );

    final kept = keepOwnedSettings(mine, theirs, {
      'clash.mixed-port',
      'clash.interface-name',
      'clash.tun.stack',
    });

    expect(kept.mixedPort, 1080);
    expect(kept.interfaceNameMode, InterfaceNameMode.custom);
    expect(kept.interfaceName, 'en1');
    expect(kept.tun.stack, TunStack.gvisor);
    expect(kept.logLevel, LogLevel.warning);
    expect(kept.allowLan, isTrue);
  });

  test('owned route lists survive a sync that brings others', () {
    const mine = PatchClashConfig(
      tun: Tun(
        routeAddress: ['10.0.0.0/8'],
        routeExcludeAddress: ['192.168.0.0/16'],
      ),
    );
    const theirs = PatchClashConfig(
      tun: Tun(
        routeAddress: ['0.0.0.0/1'],
        routeExcludeAddress: ['172.16.0.0/12'],
      ),
    );

    final kept = keepOwnedSettings(mine, theirs, {
      'clash.tun.route-address',
      'clash.tun.route-exclude-address',
    });

    expect(kept.tun.routeAddress, ['10.0.0.0/8']);
    expect(kept.tun.routeExcludeAddress, ['192.168.0.0/16']);
    expect(
      managedClashKeysOf(['tun.route-address', 'tun.route-exclude-address']),
      {'clash.tun.route-address', 'clash.tun.route-exclude-address'},
    );
  });
}
