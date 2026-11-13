import 'package:fl_clash/features/update/asset.dart';
import 'package:flutter_test/flutter_test.dart';

const _repository = 'pluralplay/FlClashX';

Map<String, dynamic> _asset(String name, {int size = 1000, String? url}) => {
  'name': name,
  'size': size,
  'browser_download_url':
      url ?? 'https://github.com/$_repository/releases/download/v0.5.1/$name',
};

Map<String, dynamic> _release(
  List<String> names, {
  String tag = 'v0.5.1',
  bool? prerelease,
}) => {
  'tag_name': tag,
  'prerelease': ?prerelease,
  'assets': [
    for (final name in names) ...[_asset(name), _asset('$name.sha256')],
  ],
};

Matcher _fails(UpdateErrorKind kind) =>
    throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', kind));

void main() {
  group('selectUpdateAsset', () {
    const allAssets = [
      'FlClashX-android-arm64-v8a.apk',
      'FlClashX-android-armeabi-v7a.apk',
      'FlClashX-android-universal.apk',
      'FlClashX-windows-amd64-setup.exe',
      'FlClashX-windows-amd64.zip',
      'FlClashX-windows-arm64-setup.exe',
      'FlClashX-macos-amd64.dmg',
      'FlClashX-macos-arm64.dmg',
      'FlClashX-linux-amd64.AppImage',
      'FlClashX-linux-amd64.deb',
      'FlClashX-linux-amd64.rpm',
      'FlClashX-linux-arm64.deb',
    ];

    String select(UpdateTarget target, {List<String> names = allAssets}) =>
        selectUpdateAsset(
          _release(names, prerelease: false),
          target,
          repository: _repository,
          pre: false,
        ).name;

    test('takes the first supported ABI a release builds', () {
      final archs = androidUpdateArchs(['x86', 'arm64-v8a', 'armeabi-v7a']);
      expect(archs, ['arm64-v8a', 'armeabi-v7a', 'universal']);
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.android, ['x86_64'])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        select(UpdateTarget(UpdateInstallKind.android, archs)),
        'FlClashX-android-arm64-v8a.apk',
      );
    });

    test('falls back to the universal APK', () {
      expect(
        select(
          UpdateTarget(UpdateInstallKind.android, androidUpdateArchs(['x86'])),
        ),
        'FlClashX-android-universal.apk',
      );
    });

    test('picks the desktop package for the install type and arch', () {
      expect(
        select(const UpdateTarget(UpdateInstallKind.windows, ['arm64'])),
        'FlClashX-windows-arm64-setup.exe',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.macos, ['amd64'])),
        'FlClashX-macos-amd64.dmg',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.appImage, ['amd64'])),
        'FlClashX-linux-amd64.AppImage',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.deb, ['arm64'])),
        'FlClashX-linux-arm64.deb',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.rpm, ['amd64'])),
        'FlClashX-linux-amd64.rpm',
      );
    });

    test('never substitutes another arch or package type', () {
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.rpm, ['arm64'])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.appImage, [])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        () => select(
          const UpdateTarget(UpdateInstallKind.packageManager, ['amd64']),
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('holds a release to the channel the app runs on', () {
      final pre = _release(
        ['FlClashX-macos-arm64.dmg'],
        tag: 'v0.5.2-pre.1',
        prerelease: true,
      );
      const target = UpdateTarget(UpdateInstallKind.macos, ['arm64']);
      expect(
        selectUpdateAsset(pre, target, repository: _repository, pre: true).name,
        'FlClashX-macos-arm64.dmg',
      );
      expect(
        () =>
            selectUpdateAsset(pre, target, repository: _repository, pre: false),
        _fails(UpdateErrorKind.noAsset),
      );
      final stable = _release(['FlClashX-macos-arm64.dmg'], prerelease: false);
      expect(
        () => selectUpdateAsset(
          stable,
          target,
          repository: _repository,
          pre: true,
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('rejects a tag that is not a version', () {
      final release = _release(['FlClashX-macos-arm64.dmg'], tag: 'v1/../x');
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('requires a published checksum', () {
      final release = {
        'tag_name': 'v0.5.1',
        'assets': [_asset('FlClashX-macos-arm64.dmg')],
      };
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.noChecksum),
      );
    });

    test('caps the size at the release figure and the ceiling', () {
      final asset = selectUpdateAsset(
        _release(['FlClashX-macos-arm64.dmg']),
        const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
        repository: _repository,
        pre: false,
      );
      expect(asset.size, 1000);
      expect(asset.sizeLimit, 1000);
      final huge = {
        'tag_name': 'v0.5.1',
        'assets': [
          _asset('FlClashX-macos-arm64.dmg', size: updateSizeCeiling + 1),
          _asset('FlClashX-macos-arm64.dmg.sha256'),
        ],
      };
      expect(
        () => selectUpdateAsset(
          huge,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.tooLarge),
      );
    });

    test('refuses an asset URL off the allowlist', () {
      final release = {
        'tag_name': 'v0.5.1',
        'assets': [
          _asset(
            'FlClashX-macos-arm64.dmg',
            url: 'https://evil.example/FlClashX-macos-arm64.dmg',
          ),
          _asset('FlClashX-macos-arm64.dmg.sha256'),
        ],
      };
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.untrustedHost),
      );
    });

    test('builds the URL from the tag when the lookup had no assets', () {
      final asset = selectUpdateAsset(
        {'tag_name': 'v0.5.1'},
        const UpdateTarget(UpdateInstallKind.windows, ['amd64']),
        repository: _repository,
        pre: false,
      );
      expect(
        asset.url.toString(),
        'https://github.com/$_repository/releases/download/v0.5.1/'
        'FlClashX-windows-amd64-setup.exe',
      );
      expect(asset.checksumUrl.path, endsWith('setup.exe.sha256'));
      expect(asset.size, isNull);
      expect(asset.sizeLimit, updateSizeCeiling);
    });
  });

  test('only a known package and arch offer a download', () {
    expect(
      const UpdateTarget(UpdateInstallKind.macos, ['arm64']).downloads,
      isTrue,
    );
    expect(const UpdateTarget(UpdateInstallKind.macos, []).downloads, isFalse);
    expect(
      const UpdateTarget(UpdateInstallKind.packageManager, ['amd64']).downloads,
      isFalse,
    );
    expect(
      const UpdateTarget(UpdateInstallKind.unsupported, ['amd64']).downloads,
      isFalse,
    );
  });

  test('allowlist takes only HTTPS on the GitHub download hosts', () {
    expect(isAllowedUpdateUri(Uri.parse('https://github.com/a')), isTrue);
    expect(
      isAllowedUpdateUri(
        Uri.parse('https://release-assets.githubusercontent.com/x'),
      ),
      isTrue,
    );
    expect(
      isAllowedUpdateUri(Uri.parse('https://objects.githubusercontent.com/x')),
      isTrue,
    );
    expect(isAllowedUpdateUri(Uri.parse('http://github.com/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://github.com:8443/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://u@github.com/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://github.com.evil/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://gist.github.com/a')), isFalse);
  });

  group('parseChecksum', () {
    const hash =
        '3dad780109d1524106a07cc6499c7f0fb04f08290b0eb931a5f7bbcf2c153058';
    const name = 'FlClashX-macos-arm64.dmg';

    test('reads the sha256sum line a release publishes', () {
      expect(parseChecksum('$hash  ./$name\n', name), hash);
      expect(parseChecksum('$hash *$name\r\n', name), hash);
      expect(parseChecksum('﻿${hash.toUpperCase()}  $name', name), hash);
    });

    test('reads BSD shasum output and a bare hash', () {
      expect(parseChecksum('SHA256 ($name) = $hash', name), hash);
      expect(parseChecksum('$hash\n', name), hash);
    });

    test('ignores lines for other files and malformed lines', () {
      final other = 'f' * 64;
      expect(parseChecksum('$other  other.dmg\n$hash  $name', name), hash);
      expect(parseChecksum('$other  other.dmg', name), isNull);
      expect(parseChecksum('not a hash  $name', name), isNull);
      expect(parseChecksum('${hash.substring(1)}  $name', name), isNull);
      expect(parseChecksum('', name), isNull);
    });
  });

  test('release page stays on github.com', () {
    expect(
      releasePageOf({
        'tag_name': 'v0.5.1',
        'html_url': 'https://github.com/$_repository/releases/tag/v0.5.1',
      }, repository: _repository).toString(),
      'https://github.com/$_repository/releases/tag/v0.5.1',
    );
    expect(
      releasePageOf({
        'tag_name': 'v0.5.2-pre.1',
        'html_url': 'https://evil.example/',
      }, repository: _repository).toString(),
      'https://github.com/$_repository/releases/tag/v0.5.2-pre.1',
    );
  });
}
