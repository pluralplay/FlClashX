import 'dart:io';

String? _mihomoSourceDir;

/// Where the Go toolchain keeps the mihomo release `core/go.mod` requires;
/// the tests that keep the Dart models in step with mihomo's structs read it
/// from there, so `go` must be on PATH and the module downloaded.
String mihomoSourceDir() {
  return _mihomoSourceDir ??= () {
    final result = Process.runSync('go', [
      'list',
      '-m',
      '-f',
      '{{.Dir}}',
      'github.com/metacubex/mihomo',
    ], workingDirectory: 'core');
    final dir = (result.stdout as String).trim();
    if (result.exitCode != 0 || dir.isEmpty) {
      throw StateError(
        'go list could not locate mihomo: ${result.stderr}'.trim(),
      );
    }
    return dir;
  }();
}
