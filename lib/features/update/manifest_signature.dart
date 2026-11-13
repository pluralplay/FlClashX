// tool/sign_update_manifest.dart runs this file outside Flutter.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// A list so a new key can ship in the app before the old one retires.
const updateManifestKeys = ['MDf1zyd4RNKZ+Gx6yNgQKungx/XtHn+wNvMJT9xvEiA='];

const _domain = 'flclashx-update-manifest-v1';

final _assetName = RegExp(r'^[A-Za-z0-9._+-]+$');
final _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');
final _version = RegExp(r'^v\d+\.\d+\.\d+(-pre\.\d+)?$');

typedef ManifestAssetHash = ({String name, String sha256});

/// Asset URLs stay unsigned: providers point them at their own mirrors,
/// and the signed hash is what vouches for the file. Names are ASCII, so
/// sorting them as strings is the byte order the format specifies.
List<int> updateManifestMessage(
  String version,
  Iterable<ManifestAssetHash> assets,
) {
  if (!_version.hasMatch(version)) {
    throw FormatException('malformed version', version);
  }
  final entries = <String, String>{};
  for (final asset in assets) {
    if (!_assetName.hasMatch(asset.name)) {
      throw FormatException('malformed asset name', asset.name);
    }
    if (!_sha256.hasMatch(asset.sha256)) {
      throw FormatException('malformed sha256', asset.sha256);
    }
    if (entries.containsKey(asset.name)) {
      throw FormatException('duplicate asset', asset.name);
    }
    entries[asset.name] = asset.sha256.toLowerCase();
  }
  final names = entries.keys.toList()..sort();
  return utf8.encode(
    [
      '$_domain\n$version\n',
      for (final name in names) '$name ${entries[name]}\n',
    ].join(),
  );
}

Future<bool> verifyUpdateManifestSignature(
  List<int> message,
  String signature, {
  List<String> keys = updateManifestKeys,
}) async {
  final signatureBytes = _decode(signature, 64);
  if (signatureBytes == null) {
    return false;
  }
  final algorithm = DartEd25519();
  for (final key in keys) {
    final keyBytes = _decode(key, 32);
    if (keyBytes == null) {
      continue;
    }
    try {
      final valid = await algorithm.verify(
        message,
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(keyBytes, type: KeyPairType.ed25519),
        ),
      );
      if (valid) {
        return true;
      }
    } catch (_) {
      continue;
    }
  }
  return false;
}

Future<({String signature, String publicKey})> signUpdateManifest(
  List<int> message,
  List<int> seed,
) async {
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final signature = await algorithm.sign(message, keyPair: keyPair);
  final publicKey = await keyPair.extractPublicKey();
  return (
    signature: base64.encode(signature.bytes),
    publicKey: base64.encode(publicKey.bytes),
  );
}

List<int>? _decode(String value, int length) {
  try {
    final bytes = base64.decode(value);
    return bytes.length == length ? bytes : null;
  } on FormatException {
    return null;
  }
}
