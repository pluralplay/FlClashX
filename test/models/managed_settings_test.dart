import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  test('only the keys a subscription may take over count as managed', () {
    expect(
      managedClashKeysOf(['mixed-port', 'tun.stack', 'dns', 'proxies', 'mode']),
      {'clash.mixed-port', 'clash.tun.stack'},
    );
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
}
