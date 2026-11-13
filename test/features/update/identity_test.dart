import 'dart:io';

import 'package:fl_clash/features/update/asset.dart';
import 'package:fl_clash/features/update/identity.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _fails(UpdateErrorKind kind) =>
    throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', kind));

ProcessResult _result(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

typedef _Bundle = ({String? id, String? team, bool valid, bool notarized});

/// Answers plutil, codesign and spctl for the bundles it knows.
ProcessRunner _macos(Map<String, _Bundle> bundles) =>
    (executable, arguments, {environment}) async {
      String bundleOf(String path) =>
          bundles.keys.firstWhere((bundle) => path.startsWith(bundle));
      final bundle = bundles[bundleOf(arguments.last)]!;
      switch (executable) {
        case '/usr/bin/plutil':
          return bundle.id == null
              ? _result(1)
              : _result(0, stdout: '${bundle.id}\n');
        case '/usr/bin/codesign' when arguments.first == '-dv':
          return _result(
            0,
            stderr:
                'Executable=x\nTeamIdentifier=${bundle.team ?? 'not set'}\n',
          );
        case '/usr/bin/codesign':
          return _result(bundle.valid ? 0 : 1);
        case '/usr/sbin/spctl':
          return _result(bundle.notarized ? 0 : 3);
      }
      throw StateError('unexpected $executable');
    };

const _running = '/Applications/FlClashX.app';
const _candidate = '/cache/update/1/staged/FlClashX.app';

void main() {
  group('Android', () {
    const installed = AndroidPackageIdentity(
      packageName: 'com.follow.clashx',
      versionCode: 2026111202,
      signers: {'aa'},
    );

    test('accepts a newer build of the same package and signer', () {
      checkAndroidUpdate(
        installed: installed,
        candidate: AndroidPackageIdentity.fromMap(const {
          'packageName': 'com.follow.clashx',
          'versionCode': 2026111301,
          'signers': ['AA'],
        }),
      );
    });

    test('rejects another package, such as the pre-release', () {
      expect(
        () => checkAndroidUpdate(
          installed: installed,
          candidate: const AndroidPackageIdentity(
            packageName: 'com.follow.clashx.pre',
            versionCode: 2026111301,
            signers: {'aa'},
          ),
        ),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });

    test('rejects a different, extra or missing signer', () {
      for (final signers in [
        {'bb'},
        {'aa', 'bb'},
        <String>{},
      ]) {
        expect(
          () => checkAndroidUpdate(
            installed: installed,
            candidate: AndroidPackageIdentity(
              packageName: 'com.follow.clashx',
              versionCode: 2026111301,
              signers: signers,
            ),
          ),
          _fails(UpdateErrorKind.identityMismatch),
        );
      }
    });

    test('rejects the same or an older version code', () {
      expect(
        () => checkAndroidUpdate(installed: installed, candidate: installed),
        _fails(UpdateErrorKind.notNewer),
      );
    });

    test('a malformed answer is an identity failure', () {
      expect(
        () => AndroidPackageIdentity.fromMap(const {'packageName': 'x'}),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });
  });

  group('macOS', () {
    const signed = (
      id: 'com.follow.clashx',
      team: 'TEAM123456',
      valid: true,
      notarized: true,
    );

    Future<void> verify(_Bundle running, _Bundle candidate) =>
        verifyMacosUpdate(
          running: _running,
          candidate: _candidate,
          run: _macos({_running: running, _candidate: candidate}),
        );

    test('accepts the same team, notarized like the running app', () async {
      await verify(signed, signed);
    });

    test('rejects another team or a broken signature', () async {
      await expectLater(
        verify(signed, (
          id: signed.id,
          team: 'OTHERTEAM1',
          valid: true,
          notarized: true,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
      await expectLater(
        verify(signed, (
          id: signed.id,
          team: signed.team,
          valid: false,
          notarized: true,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
      await expectLater(
        verify(signed, (
          id: signed.id,
          team: null,
          valid: false,
          notarized: false,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });

    test('a notarized app takes only a notarized update', () async {
      await expectLater(
        verify(signed, (
          id: signed.id,
          team: signed.team,
          valid: true,
          notarized: false,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
      await verify(
        (id: signed.id, team: signed.team, valid: true, notarized: false),
        (id: signed.id, team: signed.team, valid: true, notarized: false),
      );
    });

    test('an unsigned app checks only the bundle id', () async {
      const unsigned = (
        id: 'com.follow.clashx.pre',
        team: null,
        valid: false,
        notarized: false,
      );
      await verify(unsigned, unsigned);
      await expectLater(
        verify(unsigned, (
          id: 'com.follow.clashx',
          team: null,
          valid: false,
          notarized: false,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });

    test('an unreadable bundle id fails', () async {
      await expectLater(
        verify(signed, (
          id: null,
          team: signed.team,
          valid: true,
          notarized: true,
        )),
        _fails(UpdateErrorKind.identityMismatch),
      );
    });
  });

  group('Windows', () {
    const own = r'C:\Program Files\FlClashX\FlClashX.exe';
    const setup = r'C:\cache\update\1\FlClashX-windows-amd64-setup.exe';

    ProcessRunner signer(Map<String, String> outputs, List<String> paths) =>
        (executable, arguments, {environment}) async {
          expect(executable, endsWith(r'powershell.exe'));
          final path = environment!['FLCLASHX_SIGNED_FILE']!;
          expect(arguments.join(' '), isNot(contains(path)));
          paths.add(path);
          return _result(0, stdout: outputs[path]!);
        };

    test('an unsigned app relies on the checksum alone', () async {
      final paths = <String>[];
      await verifyWindowsUpdate(
        running: own,
        candidate: setup,
        run: signer({own: 'NotSigned\r\n'}, paths),
      );
      expect(paths, [own]);
    });

    test('a signed app takes only the same signer', () async {
      const subject = 'CN=pluralplay';
      await verifyWindowsUpdate(
        running: own,
        candidate: setup,
        run: signer({
          own: 'Valid\r\n$subject\r\n',
          setup: 'Valid\r\n$subject\r\n',
        }, []),
      );
      for (final output in [
        'Valid\r\nCN=someone else\r\n',
        'HashMismatch\r\n$subject\r\n',
        'NotSigned\r\n',
      ]) {
        await expectLater(
          verifyWindowsUpdate(
            running: own,
            candidate: setup,
            run: signer({own: 'Valid\r\n$subject\r\n', setup: output}, []),
          ),
          _fails(UpdateErrorKind.identityMismatch),
        );
      }
    });

    test('a signature of its own it cannot read stops the update', () async {
      for (final output in [
        'UnknownError\r\n',
        'HashMismatch\r\nCN=x\r\n',
        '',
      ]) {
        await expectLater(
          verifyWindowsUpdate(
            running: own,
            candidate: setup,
            run: signer({own: output}, []),
          ),
          _fails(UpdateErrorKind.identityMismatch),
        );
      }
    });
  });
}
