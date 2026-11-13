import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:fl_clash/features/update/manifest_signature.dart';
import 'package:path/path.dart' as p;

const keyEnvironment = 'FLCLASHX_UPDATE_SIGNING_KEY';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('version', help: 'Release tag, such as v0.5.1.')
    ..addOption('base-url', help: 'Each asset is listed at <base-url>/<name>.')
    ..addOption(
      'key-file',
      help: 'File holding the base64 ed25519 seed; else \$$keyEnvironment.',
    )
    ..addOption('out', help: 'Manifest file, defaults to stdout.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    _fail('${error.message}\n${parser.usage}');
  }
  if (args.flag('help')) {
    stdout.writeln(
      'dart run tool/sign_update_manifest.dart --version <tag> '
      '--base-url <url> [--key-file <file>] [--out <file>] <file|dir>...\n'
      '${parser.usage}',
    );
    return;
  }
  final version = args.option('version');
  final baseUrl = args.option('base-url');
  if (version == null || baseUrl == null || args.rest.isEmpty) {
    _fail(
      '--version, --base-url and at least one file or directory are '
      'required.\n${parser.usage}',
    );
  }
  final keyFile = args.option('key-file');
  final seed = decodeSeed(
    keyFile != null
        ? File(keyFile).readAsStringSync()
        : Platform.environment[keyEnvironment],
  );
  if (seed == null) {
    _fail(
      'No signing key: pass --key-file or set $keyEnvironment to the '
      'base64 32-byte ed25519 seed.',
    );
  }
  final out = args.option('out');
  final files = releaseFiles(
    args.rest,
    skip: out == null ? null : p.absolute(out),
  );
  final signed = await buildSignedManifest(
    version: version.startsWith('v') ? version : 'v$version',
    files: files,
    baseUrl: baseUrl,
    seed: seed,
  );
  if (!updateManifestKeys.contains(signed.publicKey)) {
    _fail(
      'The signing key is not one the app pins in updateManifestKeys; '
      'its public key is ${signed.publicKey}.',
    );
  }
  final text =
      '${const JsonEncoder.withIndent('  ').convert(signed.manifest)}'
      '\n';
  if (out == null) {
    stdout.write(text);
  } else {
    File(out).writeAsStringSync(text);
    stderr.writeln('Signed ${files.length} assets of $version into $out.');
  }
}

List<int>? decodeSeed(String? value) {
  if (value == null) {
    return null;
  }
  try {
    final seed = base64.decode(value.trim());
    return seed.length == 32 ? seed : null;
  } on FormatException {
    return null;
  }
}

/// A directory contributes the files directly inside it, leaving out hidden
/// files, the checksum beside each asset and the manifest being written.
List<File> releaseFiles(List<String> paths, {String? skip}) {
  final files = <File>[];
  for (final path in paths) {
    final entries = FileSystemEntity.isDirectorySync(path)
        ? Directory(path).listSync().whereType<File>()
        : [File(path)];
    for (final file in entries) {
      final name = p.basename(file.path);
      if (name.startsWith('.') ||
          name.endsWith('.sha256') ||
          name == 'manifest.json' ||
          p.absolute(file.path) == skip) {
        continue;
      }
      files.add(file);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<({Map<String, Object> manifest, String publicKey})> buildSignedManifest({
  required String version,
  required List<File> files,
  required String baseUrl,
  required List<int> seed,
}) async {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final assets = [
    for (final file in files)
      (
        name: p.basename(file.path),
        sha256: (await sha256.bind(file.openRead()).first).toString(),
      ),
  ];
  final signed = await signUpdateManifest(
    updateManifestMessage(version, assets),
    seed,
  );
  return (
    manifest: <String, Object>{
      'version': version,
      'assets': [
        for (final asset in assets)
          {
            'name': asset.name,
            'url': '$base/${asset.name}',
            'sha256': asset.sha256,
          },
      ],
      'signature': signed.signature,
    },
    publicKey: signed.publicKey,
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
