import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';
import 'package:proxy/proxy_method_channel.dart';
import 'package:proxy/src/linux_proxy.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';
import 'package:proxy/src/windows_proxy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Proxy', () {
    test('rejects ports outside the TCP port range', () async {
      final proxy = Proxy(
        processRunner: (executable, arguments, {runInShell = false}) async {
          fail('invalid ports must not execute platform commands');
        },
      );

      expect(await proxy.startProxy(0), isFalse);
      expect(await proxy.startProxy(65536), isFalse);
    });
  });

  group('ProxyCommandRunner', () {
    test('treats an empty command set as failure', () async {
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        fail('empty command sets must not start a process');
      });

      expect(await runner.run(const []), isFalse);
    });

    test('stops after the first failed command', () async {
      var callCount = 0;
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        callCount++;
        return ProcessResult(callCount, callCount == 1 ? 1 : 0, '', '');
      });

      final result = await runner.run([
        ProxyCommand('first', const []),
        ProxyCommand('second', const []),
      ]);

      expect(result, isFalse);
      expect(callCount, 1);
    });

    test('converts process launch failures to false', () async {
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        throw ProcessException(executable, arguments);
      });

      expect(await runner.run([ProxyCommand('missing', const [])]), isFalse);
    });

    test('carries on past an optional command that fails', () async {
      final started = <String>[];
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        started.add(executable);
        if (executable == 'missing') {
          throw ProcessException(executable, arguments);
        }
        return ProcessResult(0, executable == 'refused' ? 1 : 0, '', '');
      });

      final result = await runner.run([
        ProxyCommand('missing', const [], optional: true),
        ProxyCommand('refused', const [], optional: true),
        ProxyCommand('last', const []),
      ]);

      expect(result, isTrue);
      expect(started, ['missing', 'refused', 'last']);
    });
  });

  group('Linux proxy command builders', () {
    test(
      'checks each fallback command only once for unknown desktops',
      () async {
        final checkedExecutables = <String>[];
        final executedCommands = <String>[];
        final proxy = LinuxProxy(
          commandRunner: ProxyCommandRunner((
            executable,
            arguments, {
            runInShell = false,
          }) async {
            executedCommands.add(executable);
            return ProcessResult(1, 0, '', '');
          }),
          executableChecker: (executable) async {
            checkedExecutables.add(executable);
            return executable == 'kwriteconfig5';
          },
        );

        final result = await proxy.start(
          7890,
          const ['localhost'],
          desktop: 'UNKNOWN',
          homeDir: '/home/user',
        );

        expect(result, isTrue);
        expect(checkedExecutables, [
          'gsettings',
          'kwriteconfig6',
          'kwriteconfig5',
        ]);
        expect(executedCommands.toSet(), {'kwriteconfig5', 'dbus-send'});
      },
    );

    test('builds GNOME commands without duplicate port writes', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost', '127.0.0.1'],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      final portCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'port',
      );
      final hostCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'host',
      );

      expect(portCommands, hasLength(3));
      expect(hostCommands, hasLength(3));
      expect(commands.last.args, [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'manual',
      ]);
      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        "['localhost', '127.0.0.1']",
      );
    });

    test('builds empty GNOME ignore-hosts as an empty list', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: const [],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        '[]',
      );
    });

    test('escapes backslashes and quotes in GNOME ignore-hosts', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: [r'local\host', "it's"],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      expect(
        commands
            .singleWhere((command) => command.args.contains('ignore-hosts'))
            .args
            .last,
        r"['local\\host', 'it\'s']",
      );
    });

    test('builds MATE commands with MATE proxy schema', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'MATE',
        homeDir: '/home/user',
      );

      expect(
        commands.any(
          (command) => command.args.contains('org.mate.system.proxy'),
        ),
        isTrue,
      );
      expect(
        commands.any(
          (command) => command.args.contains('org.gnome.system.proxy'),
        ),
        isFalse,
      );
    });

    test('falls back to GNOME gsettings commands for XFCE when available', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'XFCE',
        homeDir: '/home/user',
        availableExecutables: {'gsettings'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'gsettings',
      });
      expect(
        commands.any(
          (command) =>
              command.args.contains('org.gnome.system.proxy') &&
              command.args.contains('manual'),
        ),
        isTrue,
      );
    });

    test('prefers kwriteconfig6 for KDE when available', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig6', 'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig6',
        'dbus-send',
      });
    });

    test('points every KDE proxy at the plain HTTP or SOCKS listener and '
        'tells running KIO programs to reload', () {
      for (final commands in [
        LinuxProxyCommands.buildStart(
          port: 7890,
          bypassDomain: ['localhost'],
          desktop: 'KDE',
          homeDir: '/home/user',
          availableExecutables: {'kwriteconfig6'},
        ),
        LinuxProxyCommands.buildStop(
          desktop: 'KDE',
          homeDir: '/home/user',
          availableExecutables: {'kwriteconfig6'},
        ),
      ]) {
        final reload = commands.last;
        expect(reload.executable, 'dbus-send');
        expect(reload.args, [
          '--session',
          '--type=signal',
          '/KIO/Scheduler',
          'org.kde.KIO.Scheduler.reparseSlaveConfiguration',
          'string:',
        ]);
        expect(reload.optional, isTrue);
      }
      final proxies = {
        for (final command in LinuxProxyCommands.buildStart(
          port: 7890,
          bypassDomain: ['localhost'],
          desktop: 'KDE',
          homeDir: '/home/user',
          availableExecutables: {'kwriteconfig6'},
        ))
          if (command.args.length > 6 && command.args[5].endsWith('Proxy'))
            command.args[5]: command.args[6],
      };
      expect(proxies, {
        'httpProxy': 'http://127.0.0.1:7890',
        'httpsProxy': 'http://127.0.0.1:7890',
        'socksProxy': 'socks://127.0.0.1:7890',
      });
    });

    test(
      'falls back to kwriteconfig5 for KDE when kwriteconfig6 is missing',
      () {
        final commands = LinuxProxyCommands.buildStart(
          port: 7890,
          bypassDomain: ['localhost'],
          desktop: 'KDE',
          homeDir: '/home/user',
          availableExecutables: {'kwriteconfig5'},
        );

        expect(commands.map((command) => command.executable).toSet(), {
          'kwriteconfig5',
          'dbus-send',
        });
      },
    );

    test('uses available backend for unknown desktops', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'UNKNOWN',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig5',
        'dbus-send',
      });
    });

    test('does not use an unrelated backend for a known desktop', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'gsettings'},
      );

      expect(commands, isEmpty);
    });
  });

  group('macOS proxy command builders', () {
    test(
      'filters networksetup service list headers, disabled services, and blanks',
      () {
        final services = MacosProxyCommands.parseNetworkServices('''
An asterisk (*) denotes that a network service is disabled.
Wi-Fi
*Thunderbolt Bridge
USB 10/100/1000 LAN

''');

        expect(services, ['Wi-Fi', 'USB 10/100/1000 LAN']);
      },
    );

    test('passes bypass domains as separate networksetup arguments', () {
      final command = MacosProxyCommands.buildProxyBypass('Wi-Fi', [
        'localhost',
        '127.0.0.1',
      ]);

      expect(command.executable, '/usr/sbin/networksetup');
      expect(command.args, [
        '-setproxybypassdomains',
        'Wi-Fi',
        'localhost',
        '127.0.0.1',
      ]);
    });

    test('uses Empty when clearing bypass domains', () {
      final command = MacosProxyCommands.buildProxyBypass('Wi-Fi', const []);

      expect(command.args, ['-setproxybypassdomains', 'Wi-Fi', 'Empty']);
    });

    test('configures values before enabling proxy states', () {
      final commands = MacosProxyCommands.buildStart('Wi-Fi', 7890, const [
        'localhost',
      ]);

      final firstStateCommand = commands.indexWhere(
        (command) => command.args.first.endsWith('proxystate'),
      );

      expect(firstStateCommand, 4);
      expect(commands[3].args.first, '-setproxybypassdomains');
    });

    test('reports failure when no active network service is found', () async {
      var callCount = 0;
      final proxy = MacosProxy(
        commandRunner: ProxyCommandRunner((
          executable,
          arguments, {
          runInShell = false,
        }) async {
          callCount++;
          return ProcessResult(
            callCount,
            0,
            'An asterisk (*) denotes that a network service is disabled.\n',
            '',
          );
        }),
      );

      expect(await proxy.start(7890, const []), isFalse);
      expect(callCount, 1);
    });
  });

  group('stale proxy clearing', () {
    ProxyProcessRunner recording(
      List<List<String>> calls,
      String Function(List<String> arguments) stdout,
    ) {
      return (executable, arguments, {runInShell = false}) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(0, 0, stdout(arguments), '');
      };
    }

    String macosProxy(String server, int port, {bool enabled = true}) =>
        'Enabled: ${enabled ? 'Yes' : 'No'}\nServer: $server\nPort: $port\n'
        'Authenticated Proxy Enabled: 0\n';

    Future<bool> deadExcept(int port, Set<int> live) async =>
        live.contains(port);

    test('reads the proxy a macOS query reports as on', () {
      expect(
        MacosProxyCommands.parseEnabledProxy(macosProxy('127.0.0.1', 7890)),
        (host: '127.0.0.1', port: 7890),
      );
      expect(
        MacosProxyCommands.parseEnabledProxy(
          macosProxy('127.0.0.1', 7890, enabled: false),
        ),
        isNull,
      );
    });

    test('a setting is stale only if all it turns on is a dead local '
        'port', () async {
      Future<bool> stale(
        List<ProxyEndpoint> enabled, {
        Set<int> live = const {},
      }) => isStaleLocalProxy(enabled, (port) => deadExcept(port, live));
      const local = (host: '127.0.0.1', port: 7890);

      expect(await stale([local, local]), isTrue);
      expect(await stale([local], live: {7890}), isFalse);
      expect(await stale([local, (host: '10.0.0.1', port: 3128)]), isFalse);
      expect(await stale(const []), isFalse);
      expect(await stale([(host: '127.0.0.1', port: 0)]), isFalse);
    });

    test(
      'turns off only the macOS services all on a dead local port',
      () async {
        final calls = <List<String>>[];
        final proxy = MacosProxy(
          commandRunner: ProxyCommandRunner(
            recording(calls, (arguments) {
              return switch (arguments) {
                ['-listallnetworkservices'] => 'Wi-Fi\nEthernet\nVPN\nUSB\n',
                [_, 'Wi-Fi'] => macosProxy('127.0.0.1', 7890),
                [_, 'Ethernet'] => macosProxy('127.0.0.1', 7891),
                ['-getsecurewebproxy', 'VPN'] => macosProxy('10.0.0.1', 3128),
                [_, 'VPN'] => macosProxy('127.0.0.1', 7890),
                [_, 'USB'] => macosProxy('127.0.0.1', 7890, enabled: false),
                _ => '',
              };
            }),
          ),
        );

        expect(
          await proxy.clearStale((port) => deadExcept(port, {7891})),
          isTrue,
        );

        final changed = {
          for (final call in calls)
            if (call[1].startsWith('-set')) call[2],
        };
        expect(changed, {'Wi-Fi'});
      },
    );

    test('reads the proxies a manual GNOME or KDE setting turns on', () {
      expect(
        LinuxProxyCommands.parseGSettingsProxies("'manual'", {
          'http.host': "'127.0.0.1'",
          'http.port': '7890',
          'https.host': "''",
          'https.port': '0',
          'socks.host': "'10.0.0.1'",
          'socks.port': '1080',
        }),
        [(host: '127.0.0.1', port: 7890), (host: '10.0.0.1', port: 1080)],
      );
      expect(LinuxProxyCommands.parseGSettingsProxies("'none'", {}), isEmpty);

      const kde =
          '[Proxy Settings]\nProxyType=1\nhttpProxy=http://127.0.0.1:7890\n'
          'httpsProxy=http://127.0.0.1 7891\nsocksProxy=\n'
          '[Other]\nProxyType=0\n';
      expect(LinuxProxyCommands.parseKdeProxies(kde), [
        (host: '127.0.0.1', port: 7890),
        (host: '127.0.0.1', port: 7891),
      ]);
      expect(
        LinuxProxyCommands.parseKdeProxies(kde.replaceFirst('=1', '=0')),
        isEmpty,
      );
      expect(
        LinuxProxyCommands.parseKdeProxies(
          '[Proxy Settings]\nProxyType=1\nhttpProxy=http://127.0.0.1\n',
        ),
        [(host: '127.0.0.1', port: 0)],
      );
    });

    test('turns a GNOME proxy off only while its ports are dead', () async {
      for (final live in [
        <int>{},
        {7890},
      ]) {
        final calls = <List<String>>[];
        final proxy = LinuxProxy(
          commandRunner: ProxyCommandRunner(
            recording(calls, (arguments) {
              return switch (arguments) {
                ['get', _, 'mode'] => "'manual'\n",
                ['get', _, 'host'] => "'127.0.0.1'\n",
                ['get', _, 'port'] => '7890\n',
                _ => '',
              };
            }),
          ),
          executableChecker: (executable) async => executable == 'gsettings',
        );

        expect(
          await proxy.clearStale(
            (port) => deadExcept(port, live),
            desktop: 'GNOME',
            homeDir: '/home/user',
          ),
          isTrue,
        );
        expect(calls.any((call) => call.contains('set')), live.isEmpty);
      }
    });

    test('counts only a refused connection as a dead port', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final calls = <List<String>>[];
      String stdout(List<String> arguments) => switch (arguments) {
        ['-listallnetworkservices'] => 'Wi-Fi\n',
        [_, 'Wi-Fi'] => macosProxy('127.0.0.1', port),
        _ => '',
      };
      final proxy = Proxy(processRunner: recording(calls, stdout));
      if (!Platform.isMacOS) {
        await server.close();
        return;
      }

      await proxy.clearStaleProxy();
      expect(calls.any((call) => call[1].startsWith('-set')), isFalse);

      await server.close();
      await proxy.clearStaleProxy();
      expect(calls.any((call) => call[1].startsWith('-set')), isTrue);
    });
  });

  group('windowsBypassList', () {
    test('adds the intranet token once', () {
      expect(windowsBypassList(['localhost', '127.*', '<local>']), [
        'localhost',
        '127.*',
        '<local>',
      ]);
      expect(windowsBypassList(['localhost']), ['localhost', '<local>']);
    });

    test('brackets bare IPv6 literals and drops blank entries', () {
      expect(
        windowsBypassList([' ::1 ', 'fe80::1', '', '[fd00::1]', '*.lan']),
        ['[::1]', '[fe80::1]', '[fd00::1]', '*.lan', '<local>'],
      );
    });

    test('drops trailing slashes that fail the whole list', () {
      expect(
        windowsBypassList(['example.test/', 'example.test', 'nas//', '/']),
        ['example.test', 'nas', '<local>'],
      );
    });
  });

  group('MethodChannelProxy', () {
    final proxy = MethodChannelProxy();

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, null);
    });

    test('sends the Windows start contract', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            capturedCall = call;
            return true;
          });

      final result = await proxy.startProxy(7890, const ['localhost']);

      expect(result, isTrue);
      expect(capturedCall?.method, 'StartProxy');
      expect(capturedCall?.arguments, {
        'port': 7890,
        'bypassDomain': ['localhost'],
      });
    });

    test('asks Windows to clear a stale proxy', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            capturedCall = call;
            return true;
          });

      expect(await proxy.clearStaleProxy(), isTrue);
      expect(capturedCall?.method, 'ClearStaleProxy');
    });

    test('maps a null native response to false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (_) async => null);

      expect(await proxy.stopProxy(), isFalse);
    });
  });
}
