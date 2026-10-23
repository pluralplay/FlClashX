import 'dart:convert';
import 'dart:io';

// Run the same transaction locally for portable installs, or through sudo for
// system installs. Arguments are positional: no paths are interpolated into sh.
const linuxCoreInstallScript = r'''
set -eu
source=$1
target=$2
expected=$3
mode=$4
test -f "$source"
test ! -L "$source"
test ! -L "$target"
directory=$(dirname -- "$target")
temporary=$(mktemp -- "$directory/.FlClashCore.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
trap 'exit 1' HUP INT TERM
cp -- "$source" "$temporary"
actual=$(sha256sum < "$temporary")
test "${actual%% *}" = "$expected"
if [ "$(id -u)" = 0 ]; then
  chown 0:0 -- "$temporary"
fi
chmod "$mode" -- "$temporary"
mv -fT -- "$temporary" "$target"
''';

Future<ProcessResult> installLinuxCore({
  required String source,
  required String target,
  required String sha256,
  required bool preserveAuthorization,
  bool elevated = false,
  String? password,
}) async {
  final arguments = [
    '-c',
    linuxCoreInstallScript,
    'flclash-core-update',
    source,
    target,
    sha256,
    preserveAuthorization ? '6755' : '0755',
  ];
  if (!elevated) {
    return Process.run('/bin/sh', arguments);
  }
  final process = await Process.start('sudo', [
    if (password == null) '-n' else ...['-S', '-p', ''],
    '--',
    '/bin/sh',
    ...arguments,
  ]);
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  if (password != null) process.stdin.writeln(password);
  await process.stdin.close();
  return ProcessResult(
    process.pid,
    await process.exitCode,
    await stdout,
    await stderr,
  );
}
