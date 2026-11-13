import 'dart:io';

import 'package:fl_clash/features/update/asset.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

@immutable
class AndroidPackageIdentity {
  final String packageName;
  final int versionCode;

  /// SHA-256 of each signing certificate, lowercase hex.
  final Set<String> signers;

  const AndroidPackageIdentity({
    required this.packageName,
    required this.versionCode,
    required this.signers,
  });

  factory AndroidPackageIdentity.fromMap(Map<Object?, Object?> map) {
    final packageName = map['packageName'];
    final versionCode = map['versionCode'];
    final signers = map['signers'];
    if (packageName is! String || versionCode is! int || signers is! List) {
      throw const UpdateException(UpdateErrorKind.identityMismatch, 'apk');
    }
    return AndroidPackageIdentity(
      packageName: packageName,
      versionCode: versionCode,
      signers: {for (final signer in signers) '$signer'.toLowerCase()},
    );
  }
}

void checkAndroidUpdate({
  required AndroidPackageIdentity installed,
  required AndroidPackageIdentity candidate,
}) {
  if (candidate.packageName != installed.packageName) {
    throw UpdateException(
      UpdateErrorKind.identityMismatch,
      candidate.packageName,
    );
  }
  if (candidate.signers.isEmpty ||
      !setEquals(candidate.signers, installed.signers)) {
    throw const UpdateException(UpdateErrorKind.identityMismatch, 'signer');
  }
  if (candidate.versionCode <= installed.versionCode) {
    throw UpdateException(
      UpdateErrorKind.notNewer,
      '${candidate.versionCode} <= ${installed.versionCode}',
    );
  }
}

class MacosCodeSign {
  final ProcessRunner run;

  const MacosCodeSign(this.run);

  Future<String?> bundleId(String bundle) async {
    final result = await run('/usr/bin/plutil', [
      '-extract',
      'CFBundleIdentifier',
      'raw',
      '-o',
      '-',
      p.join(bundle, 'Contents', 'Info.plist'),
    ]);
    final id = '${result.stdout}'.trim();
    return result.exitCode == 0 && id.isNotEmpty ? id : null;
  }

  /// Null for an unsigned or ad-hoc signed bundle.
  Future<String?> teamId(String bundle) async {
    final result = await run('/usr/bin/codesign', [
      '-dv',
      '--verbose=2',
      bundle,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final match = RegExp(
      r'^TeamIdentifier=(.+)$',
      multiLine: true,
    ).firstMatch('${result.stderr}');
    final id = match?.group(1)?.trim();
    return id == null || id.isEmpty || id == 'not set' ? null : id;
  }

  Future<bool> isValid(String bundle) async {
    final result = await run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      bundle,
    ]);
    return result.exitCode == 0;
  }

  Future<bool> isNotarized(String bundle) async {
    final result = await run('/usr/sbin/spctl', [
      '--assess',
      '--type',
      'execute',
      bundle,
    ]);
    return result.exitCode == 0;
  }
}

/// An unsigned running app, which every pre-release is, has no signer to
/// hold the update to: there the bundle id and the release checksum are all
/// that vouch for it.
Future<void> verifyMacosUpdate({
  required String running,
  required String candidate,
  required ProcessRunner run,
}) async {
  final codesign = MacosCodeSign(run);
  final ownId = await codesign.bundleId(running);
  final id = await codesign.bundleId(candidate);
  if (ownId == null || id != ownId) {
    throw UpdateException(UpdateErrorKind.identityMismatch, '$id');
  }
  final team = await codesign.teamId(running);
  if (team == null) {
    return;
  }
  if (!await codesign.isValid(candidate) ||
      await codesign.teamId(candidate) != team) {
    throw const UpdateException(UpdateErrorKind.identityMismatch, 'team');
  }
  if (await codesign.isNotarized(running) &&
      !await codesign.isNotarized(candidate)) {
    throw const UpdateException(
      UpdateErrorKind.identityMismatch,
      'notarization',
    );
  }
}

typedef AuthenticodeSignature = ({String status, String subject});

String get windowsPowerShell => p.windows.join(
  Platform.environment['SystemRoot'] ?? r'C:\Windows',
  'System32',
  'WindowsPowerShell',
  'v1.0',
  'powershell.exe',
);

const _signedFileVariable = 'FLCLASHX_SIGNED_FILE';
const _authenticodeScript =
    '\$s = Get-AuthenticodeSignature -LiteralPath \$env:$_signedFileVariable; '
    '\$s.Status.ToString(); \$s.SignerCertificate.Subject';

/// The path travels in the environment, so nothing in it is parsed as script.
Future<AuthenticodeSignature?> authenticodeOf(
  String path,
  ProcessRunner run,
) async {
  final ProcessResult result;
  try {
    result = await run(
      windowsPowerShell,
      ['-NoProfile', '-NonInteractive', '-Command', _authenticodeScript],
      environment: {_signedFileVariable: path},
    );
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) {
    return null;
  }
  final lines = '${result.stdout}'
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return null;
  }
  return (status: lines.first, subject: lines.length > 1 ? lines[1] : '');
}

/// An unsigned running build has no signer to hold the installer to; the
/// host allowlist and the release checksum vouch for it alone. A signature
/// that cannot be read or is broken stops the update instead.
Future<void> verifyWindowsUpdate({
  required String running,
  required String candidate,
  required ProcessRunner run,
}) async {
  final own = await authenticodeOf(running, run);
  if (own?.status == 'NotSigned') {
    return;
  }
  if (own == null || own.status != 'Valid' || own.subject.isEmpty) {
    throw UpdateException(
      UpdateErrorKind.identityMismatch,
      own?.status ?? 'signature unreadable',
    );
  }
  final theirs = await authenticodeOf(candidate, run);
  if (theirs == null ||
      theirs.status != 'Valid' ||
      theirs.subject != own.subject) {
    throw UpdateException(
      UpdateErrorKind.identityMismatch,
      theirs?.subject ?? 'unsigned',
    );
  }
}
