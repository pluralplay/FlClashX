import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';

class _RecordedRun {
  const _RecordedRun(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get key =>
      arguments.isEmpty ? executable : '$executable ${arguments.first}';

  String get commandLine => [executable, ...arguments].join(' ');
}

/// Stands in for `Process.run`, keyed by executable plus its first argument so
/// the several `networksetup` subcommands can answer differently.
class _FakeProcesses {
  final List<_RecordedRun> runs = [];
  final Map<String, String> _stdout = {};
  final Map<String, int> _exitCodes = {};
  final Set<String> _failures = {};

  void stub(String key, String stdout, {int exitCode = 0}) {
    _stdout[key] = stdout;
    _exitCodes[key] = exitCode;
  }

  void stubThrow(String key) {
    _failures.add(key);
  }

  final List<String> inputs = [];

  Future<ProcessResult> runWithInput(
    String executable,
    List<String> arguments,
    String input,
  ) {
    inputs.add(input);
    return run(executable, arguments);
  }

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final recorded = _RecordedRun(executable, arguments);
    runs.add(recorded);
    if (_failures.contains(recorded.key) || _failures.contains(executable)) {
      throw ProcessException(executable, arguments);
    }
    return ProcessResult(
      0,
      _exitCodes[recorded.commandLine] ??
          _exitCodes[recorded.key] ??
          _exitCodes[executable] ??
          0,
      _stdout[recorded.commandLine] ??
          _stdout[recorded.key] ??
          _stdout[executable] ??
          '',
      '',
    );
  }

  List<String> argumentsFor(String key) => runs
      .firstWhere((run) => run.key == key || run.executable == key)
      .arguments;

  bool ran(String key) =>
      runs.any((run) => run.key == key || run.executable == key);
}

const _routeOutput = '''
   route to: default
destination: default
       mask: default
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
''';

const _serviceOrderOutput =
    '''An asterisk (*) denotes that a network service is disabled.
(1) Wi-Fi
(Hardware Port: Wi-Fi, Device: en0)

(2) Thunderbolt Bridge
(Hardware Port: Thunderbolt Bridge, Device: bridge0)

(3) iPhone USB
(Hardware Port: iPhone USB, Device: en5)
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _FakeProcesses processes;
  String? password;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('system_test');
    await useAppPaths(root);
  });

  tearDownAll(() {
    // The shared system temp dir is not exclusively ours; another suite running
    // alongside this one can take the tree out from under the teardown.
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  setUp(() {
    processes = _FakeProcesses();
    system.runProcess = processes.run;
    MacOS().runProcess = processes.run;
    linuxElevation.run = processes.run;
    linuxElevation.runWithInput = processes.runWithInput;
    linuxElevation.askPassword = () async => password;
    password = null;
  });

  tearDown(() {
    system.runProcess = Process.run;
    MacOS().runProcess = Process.run;
    linuxElevation.run = Process.run;
  });

  group('statArguments', () {
    test('selects the BSD format on macOS and the GNU one elsewhere', () {
      expect(System.statArguments('/a/core', isMacOS: true), [
        '-f',
        '%Su:%Sg %Sp',
        '/a/core',
      ]);
      expect(System.statArguments('/a/core', isMacOS: false), [
        '-c',
        '%U:%G %A',
        '/a/core',
      ]);
    });

    test('passes a path containing spaces through untouched', () {
      const path = '/Users/a b/FlClash.app/Contents/MacOS/FlClashCore';
      for (final isMacOS in [true, false]) {
        final arguments = System.statArguments(path, isMacOS: isMacOS);
        expect(arguments.last, path);
        expect(arguments.last, isNot(contains(r'\')));
      }
    });
  });

  group('aclArguments', () {
    test('grants the inheriting user access to the whole tree', () {
      final arguments = System.aclArguments('/Users/a/Support', 'alice');

      expect(arguments.first, '-R');
      expect(arguments[1], '+a');
      expect(arguments[2], startsWith('user:alice allow '));
      expect(arguments.last, '/Users/a/Support');
      expect(
        arguments[2].split(' allow ').last.split(','),
        unorderedEquals(const [
          'list',
          'search',
          'add_file',
          'add_subdirectory',
          'delete',
          'delete_child',
          'file_inherit',
          'directory_inherit',
        ]),
      );
    });

    test('never hands out ownership or the ACL itself', () {
      final arguments = System.aclArguments('/Users/a/Support', 'alice');

      expect(arguments[2], isNot(contains('writesecurity')));
      expect(arguments[2], isNot(contains('chown')));
    });

    test('passes a path containing spaces through untouched', () {
      const path = '/Users/a b/Library/Application Support/com.follow.clashx';

      final arguments = System.aclArguments(path, 'alice');

      expect(arguments.last, path);
      expect(arguments.last, isNot(contains(r'\')));
    });
  });

  group('grantHomeDirAccess', () {
    test('only touches the filesystem on macOS', () async {
      await system.grantHomeDirAccess('/Users/a/Support');

      final userName = Platform.environment['USER'];
      expect(
        processes.ran('chmod'),
        system.isMacOS && userName != null && userName.isNotEmpty,
      );
    });

    test('survives a chmod that cannot apply an ACL', () async {
      processes.stub('chmod', '', exitCode: 1);

      await expectLater(
        system.grantHomeDirAccess('/Users/a/Support'),
        completes,
      );

      processes.stubThrow('chmod');

      await expectLater(
        system.grantHomeDirAccess('/Users/a/Support'),
        completes,
      );
    });
  });

  group('isPrivilegedStatOutput', () {
    test('accepts a root-owned setuid binary closed to others', () {
      expect(
        System.isPrivilegedStatOutput(
          'root:admin -rwsr-x---\n',
          ownerPrefix: 'root:admin',
        ),
        isTrue,
      );
      expect(
        System.isPrivilegedStatOutput(
          'root:alice -rws------+',
          ownerPrefix: 'root:',
        ),
        isTrue,
      );
    });

    test('rejects a setuid binary that others can execute', () {
      for (final mode in [
        '-rwsr-sr-x',
        '-rwsr-xr-x',
        '-rwsr-x--x',
        '-rwsr-x--t',
      ]) {
        expect(
          System.isPrivilegedStatOutput(
            'root:admin $mode',
            ownerPrefix: 'root:admin',
          ),
          isFalse,
          reason: mode,
        );
      }
    });

    test('rejects a root-owned binary without the setuid bit', () {
      expect(
        System.isPrivilegedStatOutput(
          'root:admin -rwxr-xr-x',
          ownerPrefix: 'root:admin',
        ),
        isFalse,
      );
    });

    test('rejects a setuid binary owned by somebody else', () {
      expect(
        System.isPrivilegedStatOutput(
          'alice:staff -rwsr-sr-x',
          ownerPrefix: 'root:admin',
        ),
        isFalse,
      );
    });

    test('rejects the empty output stat leaves for a missing file', () {
      expect(
        System.isPrivilegedStatOutput('', ownerPrefix: 'root:admin'),
        isFalse,
      );
    });
  });

  group(
    'checkIsAdmin',
    () {
      test('stats the core path verbatim', () async {
        processes.stub('stat', 'root:admin -rwsr-x---');

        expect(await system.checkIsAdmin(), isTrue);
        expect(
          processes.argumentsFor('stat').last,
          await appPath.privilegedCorePath,
        );
      });

      test(
        'does not trust a core earlier versions left executable by all',
        () async {
          processes.stub('stat', 'root:admin -rwsr-sr-x');

          expect(await system.checkIsAdmin(), isFalse);
        },
      );

      test('reports a core that is not setuid root', () async {
        processes.stub('stat', 'alice:staff -rwxr-xr-x');

        expect(await system.checkIsAdmin(), isFalse);
      });

      test('reports a core stat could not find', () async {
        processes.stub('stat', '');

        expect(await system.checkIsAdmin(), isFalse);
      });
    },
    skip: system.hasHelperService
        ? 'the Helper probe replaces stat here'
        : false,
  );

  group('elevation shells', () {
    test('macOS installs a copy only root may replace and admins may run', () {
      expect(
        System.macOSElevationShell(
          '/Apps/Fl Clash/core',
          '/Library/Application Support/app/core',
        ),
        "dir='/Library/Application Support/app' && "
        r'{ [ ! -L "$dir" ] || rm -f "$dir"; } && '
        r'mkdir -p "$dir" && chown root:wheel "$dir" && '
        r'chmod -N "$dir" && chmod 755 "$dir" && '
        "install -S -o root -g admin -m 4750 '/Apps/Fl Clash/core' "
        "'/Library/Application Support/app/core'",
      );
    });

    test('Linux installs a copy in a directory only the requesting user may '
        'enter, leaving the shared Core as it was', () {
      expect(
        System.linuxElevationShell(
          '/opt/Fl ClashX/FlClashCore',
          '/usr/local/lib/app/1000/FlClashCore',
        ),
        "dir='/usr/local/lib/app/1000' && "
        r'uid="${dir##*/}" && group=$(id -g "$uid") && '
        r'app="${dir%/*}" && base="${app%/*}" && mkdir -p "$base" && '
        r'base=$(readlink -f "$base") && app="$base/${app##*/}" && '
        r'dir="$app/$uid" && p="$base" && while [ -n "$p" ]; do '
        r'{ [ ! -L "$p" ] && [ "$(stat -c %u "$p")" = 0 ] && '
        r'[ $((0$(stat -c %a "$p") & 022)) = 0 ]; } || exit 1; '
        r'p="${p%/*}"; done && '
        r'{ [ ! -L "$app" ] || rm -f "$app"; } && mkdir -p "$app" && '
        r'chown root:root "$app" && chmod 755 "$app" && '
        r'staged=$(mktemp "$app/.FlClashCore.XXXXXX") && '
        "{ cat '/opt/Fl ClashX/FlClashCore' > \"\$staged\" && "
        r'chown "root:$group" "$staged" && '
        r'rm -rf "$dir" && mkdir -m 700 "$dir" && '
        "mv -f \"\$staged\" \"\$dir\"/'FlClashCore' && "
        "chmod 4750 \"\$dir\"/'FlClashCore' && "
        r'chown "$uid:$group" "$dir" && chmod 500 "$dir" || '
        r'{ rm -f "$staged"; exit 1; }; }',
      );
    });

    test('the Linux copy turns setuid only inside its private directory', () {
      final shell = System.linuxElevationShell('/core', '/elevated/1000/core');

      expect(
        shell.indexOf('chmod 4750'),
        greaterThan(shell.indexOf('mv -f "\$staged"')),
      );
    });

    test('neither leaves execute to others', () {
      for (final shell in [
        System.macOSElevationShell('/core', '/elevated/core'),
        System.linuxElevationShell('/core', '/elevated/core'),
      ]) {
        expect(shell, isNot(contains('+sx')));
        expect(shell, contains(' 4750 '));
      }
    });
  });

  group('authorizeCore on macOS', () {
    test('refuses an account outside the admin group', () async {
      processes.stub('id', 'alice staff everyone');

      expect(await system.authorizeCore(), AuthorizeCode.error);
      expect(processes.ran('osascript'), isFalse);
    });

    test('elevates the Core for an admin account', () async {
      processes.stub('id', 'alice staff admin');

      expect(await system.authorizeCore(), AuthorizeCode.success);
      final arguments = processes.argumentsFor('osascript');
      expect(arguments.last, contains("'${await appPath.privilegedCorePath}'"));
      expect(
        arguments.where((argument) => argument.contains('do shell script')),
        ['do shell script (item 1 of argv) with administrator privileges'],
      );
    });

    test('reports a cancelled password prompt as an error', () async {
      processes.stub('id', 'alice staff admin');
      processes.stub('osascript', '', exitCode: 1);

      expect(await system.authorizeCore(), AuthorizeCode.error);
    });
  }, skip: system.isMacOS ? false : 'macOS only');

  group(
    'launchableCorePath',
    () {
      test('runs the elevated copy while it is the bundled Core', () async {
        processes.stub('stat', 'root:admin -rwsr-x---');
        final elevated = await appPath.privilegedCorePath;

        expect(await system.launchableCorePath(), elevated);
        expect(processes.argumentsFor('cmp'), [
          '-s',
          appPath.corePath,
          elevated,
        ]);
      });

      test('runs the bundled Core once an update replaced it', () async {
        processes.stub('stat', 'root:admin -rwsr-x---');
        processes.stub('cmp', '', exitCode: 1);

        expect(await system.launchableCorePath(), appPath.corePath);
        expect(await system.checkIsAdmin(), isFalse);
      });

      test('runs the bundled Core when the copy cannot be compared', () async {
        processes.stub('stat', 'root:admin -rwsr-x---');
        processes.stubThrow('cmp');

        expect(await system.launchableCorePath(), appPath.corePath);
      });

      test('runs the bundled Core while no copy is setuid root', () async {
        processes.stub('stat', 'alice:staff -rwxr-xr-x');

        expect(await system.launchableCorePath(), appPath.corePath);
        expect(processes.ran('cmp'), isFalse);
      });
    },
    skip: !system.isMacOS && !(system.isLinux && !system.hasHelperService)
        ? 'the Helper or the bundled Core alone runs TUN here'
        : safeModeBuild
        ? 'a safe mode build never runs the elevated copy'
        : false,
  );

  group('Windows installArguments', () {
    test('names this process as the account the Helper serves', () {
      expect(Windows.installArguments(4242), 'install --owner-pid 4242');
    });
  });

  group('Linux installService', () {
    test('asks pkexec to install the bundled Helper', () async {
      expect(await Linux().installService(), isTrue);
      expect(processes.argumentsFor('pkexec'), [appPath.helperPath, 'install']);
    });

    test('reports an installation the user dismissed', () async {
      processes.stub('pkexec', '', exitCode: 126);

      expect(await Linux().installService(), isFalse);
    });

    test('installs through cached sudo credentials without pkexec', () async {
      processes.stubThrow('pkexec');

      expect(await Linux().installService(), isTrue);
      expect(processes.argumentsFor('sudo'), [
        '-n',
        '--',
        appPath.helperPath,
        'install',
      ]);
      expect(processes.inputs, isEmpty);
    });

    test('asks for the sudo password when no polkit agent answers', () async {
      processes.stub('pkexec', '', exitCode: 127);
      processes.stub('sudo -n', '', exitCode: 1);
      password = 'secret';

      expect(await Linux().installService(), isTrue);
      expect(processes.runs.last.arguments, [
        '-S',
        '-p',
        '',
        '--',
        appPath.helperPath,
        'install',
      ]);
      expect(processes.inputs, ['secret\n']);
    });

    test('reports a command that failed under cached sudo', () async {
      processes.stubThrow('pkexec');
      processes.stub('sudo -n', '', exitCode: 1);
      processes.stub('sudo -n true', '');
      password = 'secret';

      expect(await Linux().installService(), isFalse);
      expect(processes.ran('sudo -S'), isFalse);
      expect(processes.inputs, isEmpty);
    });

    test('gives up when the sudo prompt is cancelled', () async {
      processes.stubThrow('pkexec');
      processes.stub('sudo -n', '', exitCode: 1);

      expect(await Linux().installService(), isFalse);
      expect(processes.ran('sudo -S'), isFalse);
    });

    test('does not ask sudo after the polkit dialog is dismissed', () async {
      processes.stub('pkexec', '', exitCode: 126);

      expect(await Linux().installService(), isFalse);
      expect(processes.ran('sudo'), isFalse);
    });
  });

  group('parseDefaultInterface', () {
    test('reads the interface off route output', () {
      expect(MacOS.parseDefaultInterface(_routeOutput), 'en0');
    });

    test('returns null when there is no default route', () {
      expect(
        MacOS.parseDefaultInterface('route: writing to routing socket'),
        isNull,
      );
    });

    test('returns null when the interface line carries extra fields', () {
      expect(MacOS.parseDefaultInterface('  interface: en0 en1\n'), isNull);
    });
  });

  group('parseServiceName', () {
    test('reads a single-word service name', () {
      expect(MacOS.parseServiceName(_serviceOrderOutput, 'en0'), 'Wi-Fi');
    });

    test('keeps every word of a multi-word service name', () {
      expect(
        MacOS.parseServiceName(_serviceOrderOutput, 'bridge0'),
        'Thunderbolt Bridge',
      );
      expect(MacOS.parseServiceName(_serviceOrderOutput, 'en5'), 'iPhone USB');
    });

    test('returns null for a device no service claims', () {
      expect(MacOS.parseServiceName(_serviceOrderOutput, 'utun0'), isNull);
    });

    test('returns null when the block carries no numbered name line', () {
      expect(
        MacOS.parseServiceName('(Hardware Port: Wi-Fi, Device: en0)', 'en0'),
        isNull,
      );
    });
  });

  group('parseDnsServers', () {
    test('maps the empty notice onto an empty list', () {
      expect(
        MacOS.parseDnsServers("There aren't any DNS Servers set on Wi-Fi.\n"),
        isEmpty,
      );
    });

    test('splits a configured list', () {
      expect(MacOS.parseDnsServers('1.1.1.1\n8.8.8.8\n'), [
        '1.1.1.1',
        '8.8.8.8',
      ]);
    });
  });

  group('resolveDefaultService', () {
    test('joins the route lookup to the service order listing', () async {
      processes.stub('route', _routeOutput);
      processes.stub(
        'networksetup -listnetworkserviceorder',
        _serviceOrderOutput,
      );

      expect(await MacOS().resolveDefaultService(), 'Wi-Fi');
    });

    test('stops before listing services without a default route', () async {
      expect(await MacOS().resolveDefaultService(), isNull);
      expect(processes.ran('networksetup -listnetworkserviceorder'), isFalse);
    });

    test('reports a failing route lookup as unresolved', () async {
      processes.stub('route', '', exitCode: 1);

      expect(await MacOS().resolveDefaultService(), isNull);
      expect(processes.ran('networksetup -listnetworkserviceorder'), isFalse);
    });

    test('survives a missing executable', () async {
      processes.stubThrow('route');

      expect(await MacOS().resolveDefaultService(), isNull);
    });
  });

  group('readDnsServers', () {
    test('reads the servers of the requested service', () async {
      processes.stub('networksetup -getdnsservers', '1.1.1.1\n8.8.8.8\n');

      expect(await MacOS().readDnsServers('Wi-Fi'), ['1.1.1.1', '8.8.8.8']);
      expect(processes.argumentsFor('networksetup -getdnsservers'), [
        '-getdnsservers',
        'Wi-Fi',
      ]);
    });

    test('returns null when the lookup fails', () async {
      processes.stub('networksetup -getdnsservers', '', exitCode: 1);

      expect(await MacOS().readDnsServers('Wi-Fi'), isNull);
    });
  });

  group('writeDnsServers', () {
    test('writes the requested servers', () async {
      expect(await MacOS().writeDnsServers('Wi-Fi', ['1.1.1.1']), isTrue);
      expect(processes.argumentsFor('networksetup -setdnsservers'), [
        '-setdnsservers',
        'Wi-Fi',
        '1.1.1.1',
      ]);
    });

    test('clears the servers with the literal networksetup keyword', () async {
      expect(await MacOS().writeDnsServers('Wi-Fi', []), isTrue);
      expect(processes.argumentsFor('networksetup -setdnsservers'), [
        '-setdnsservers',
        'Wi-Fi',
        'Empty',
      ]);
    });

    test('reports a rejected write instead of assuming success', () async {
      processes.stub('networksetup -setdnsservers', '', exitCode: 1);

      expect(await MacOS().writeDnsServers('Wi-Fi', ['1.1.1.1']), isFalse);
    });
  });
}
