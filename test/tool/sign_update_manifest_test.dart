import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:fl_clash/features/update/manifest.dart';
import 'package:fl_clash/features/update/manifest_signature.dart';
import 'package:test/test.dart';

import '../../tool/sign_update_manifest.dart';

List<int> _hex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  late Directory dist;

  setUp(() async {
    dist = await Directory.systemTemp.createTemp('flclashx_sign_manifest');
  });

  tearDown(() => dist.delete(recursive: true));

  test('the signed message is the version and the sorted hashes', () {
    final message = updateManifestMessage('v0.5.1', [
      (name: 'b.apk', sha256: 'B' * 64),
      (name: 'B.dmg', sha256: 'c' * 64),
      (name: 'a.exe', sha256: 'a' * 64),
    ]);
    expect(
      utf8.decode(message),
      'flclashx-update-manifest-v1\n'
      'v0.5.1\n'
      'B.dmg ${'c' * 64}\n'
      'a.exe ${'a' * 64}\n'
      'b.apk ${'b' * 64}\n',
    );
  });

  test('the message refuses what would make it ambiguous', () {
    for (final assets in [
      [(name: 'a b', sha256: 'a' * 64)],
      [(name: 'a\nb', sha256: 'a' * 64)],
      [(name: 'a', sha256: 'a' * 63)],
      [(name: 'a', sha256: 'a' * 64), (name: 'a', sha256: 'b' * 64)],
    ]) {
      expect(
        () => updateManifestMessage('v0.5.1', assets),
        throwsFormatException,
      );
    }
    expect(() => updateManifestMessage('0.5.1', []), throwsFormatException);
  });

  test('signs as RFC 8032 specifies', () async {
    final signed = await signUpdateManifest(
      const [],
      _hex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'),
    );
    expect(
      base64.decode(signed.publicKey),
      _hex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
    );
    expect(
      base64.decode(signed.signature),
      _hex(
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
    );
  });

  test('a manifest it signs is one the app verifies', () async {
    final keyPair = await DartEd25519().newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    final publicKey = base64.encode((await keyPair.extractPublicKey()).bytes);
    final payload = utf8.encode('dmg bytes');
    File('${dist.path}/FlClashX-macos-arm64.dmg').writeAsBytesSync(payload);
    File('${dist.path}/FlClashX-android-universal.apk').writeAsStringSync('a');
    File('${dist.path}/FlClashX-macos-arm64.dmg.sha256').writeAsStringSync('x');
    File('${dist.path}/manifest.json').writeAsStringSync('{}');

    final signed = await buildSignedManifest(
      version: 'v0.5.1',
      files: releaseFiles([dist.path]),
      baseUrl:
          'https://github.com/pluralplay/FlClashX/releases/download/v0.5.1/',
      seed: seed,
    );
    expect(signed.publicKey, publicKey);
    final manifest = jsonDecode(jsonEncode(signed.manifest));
    expect(manifest['assets'], [
      {
        'name': 'FlClashX-android-universal.apk',
        'url':
            'https://github.com/pluralplay/FlClashX/releases/download/v0.5.1/'
            'FlClashX-android-universal.apk',
        'sha256': sha256.convert(utf8.encode('a')).toString(),
      },
      {
        'name': 'FlClashX-macos-arm64.dmg',
        'url':
            'https://github.com/pluralplay/FlClashX/releases/download/v0.5.1/'
            'FlClashX-macos-arm64.dmg',
        'sha256': sha256.convert(payload).toString(),
      },
    ]);

    expect(
      await verifyUpdateManifest(manifest, pre: false, keys: [publicKey]),
      {'version': 'v0.5.1', 'assets': manifest['assets']},
    );
    await expectLater(
      verifyUpdateManifest(manifest, pre: false),
      throwsA(isA<UpdateManifestException>()),
    );
  });

  test('reads the seed as base64 32 bytes only', () {
    final seed = List<int>.generate(32, (i) => i);
    expect(decodeSeed(' ${base64.encode(seed)}\n'), seed);
    expect(decodeSeed(base64.encode(seed.take(31).toList())), isNull);
    expect(decodeSeed('not base64!'), isNull);
    expect(decodeSeed(null), isNull);
  });
}
