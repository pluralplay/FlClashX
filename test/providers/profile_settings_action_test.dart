import 'dart:async';
import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

Profile _profile(
  int id, {
  ProfileType type = ProfileType.url,
  ExtendType extendType = ExtendType.standard,
  DateTime? updatedAt,
}) => Profile(
  id: id,
  type: type,
  extendType: extendType,
  autoUpdateDuration: Duration.zero,
  lastUpdateDate: updatedAt,
);

void main() {
  late Directory tempDir;
  late _MockCore core;
  late ProviderContainer container;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('profile_settings_action');
    await useAppPaths(tempDir);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    core = _MockCore();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([])),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    container.listen(currentProfileIdProvider, (_, _) {});
    container.listen(patchClashConfigProvider, (_, _) {});
    container.listen(profileSettingsActionProvider, (_, _) {});
  });

  PatchClashConfig settings() => container.read(patchClashConfigProvider);

  void answer(Map<String, dynamic> config, List<String> present) {
    when(() => core.getProfileBase(any())).thenAnswer(
      (_) async => ProfileBase(config: config, digest: 'd', present: present),
    );
  }

  Future<void> select(Profile profile) async {
    container.read(profilesProvider.notifier).put(profile);
    container.read(currentProfileIdProvider.notifier).value = profile.id;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'switching to a subscription takes its keys into the settings',
    () async {
      answer(
        {'mixed-port': 7000, 'allow-lan': true},
        ['mixed-port', 'allow-lan'],
      );

      await select(_profile(1));

      expect(settings().mixedPort, 7000);
      expect(settings().allowLan, isTrue);
    },
  );

  test('a key no file names keeps what the user set', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 1080, socksPort: 7891));
    answer({}, []);

    await select(_profile(1));
    await select(_profile(1, updatedAt: DateTime(2026, 10, 28)));

    expect(settings().mixedPort, 1080);
    expect(settings().socksPort, 7891);
  });

  test(
    'a key the last file named falls back once the next leaves it out',
    () async {
      answer({'socks-port': 7891}, ['socks-port']);
      await select(_profile(1));
      expect(settings().socksPort, 7891);

      answer({}, []);
      await select(_profile(2));

      expect(settings().socksPort, const PatchClashConfig().socksPort);
    },
  );

  test('an edit under a custom profile outlives the file before it', () async {
    answer({'socks-port': 7891}, ['socks-port']);
    await select(_profile(1));
    await select(_profile(2, type: ProfileType.custom));
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(socksPort: 1234));

    answer({}, []);
    await select(_profile(3));

    expect(settings().socksPort, 1234);
  });

  test(
    'every update sets the mode and tun again until the user takes them',
    () async {
      container.listen(appSettingProvider, (_, _) {});
      answer(
        {
          'mode': 'rule',
          'tun': {'enable': true},
        },
        ['mode', 'tun', 'tun.enable'],
      );
      await select(_profile(1));
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(
              mode: Mode.global,
              tun: state.tun.copyWith(enable: false),
            ),
          );
      await select(_profile(1, updatedAt: DateTime(2026, 10, 28)));
      expect(settings().mode, Mode.rule);
      expect(settings().tun.enable, isTrue);

      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              ownedSettings: {'clash.mode', 'clash.tun.enable'},
            ),
          );
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(
              mode: Mode.global,
              tun: state.tun.copyWith(enable: false),
            ),
          );
      await select(_profile(1, updatedAt: DateTime(2026, 10, 29)));
      expect(settings().mode, Mode.global);
      expect(settings().tun.enable, isFalse);
    },
  );

  test(
    'an owned key stays while the rest follows, and is listed as managed',
    () async {
      container.listen(managedClashKeysProvider, (_, _) {});
      container.listen(appSettingProvider, (_, _) {});
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: 1080, allowLan: false));
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(ownedSettings: {'clash.mixed-port'}),
          );
      answer(
        {'mixed-port': 7000, 'allow-lan': true},
        ['mixed-port', 'allow-lan'],
      );

      await select(_profile(1));

      expect(settings().mixedPort, 1080);
      expect(settings().allowLan, isTrue);
      expect(container.read(managedClashKeysProvider), {
        'clash.mixed-port',
        'clash.allow-lan',
      });
    },
  );

  test('every update of the profile reads the file again', () async {
    final first = DateTime(2026, 10, 19, 10);
    answer({'mixed-port': 7000}, ['mixed-port']);
    await select(_profile(1, updatedAt: first));
    expect(settings().mixedPort, 7000);

    answer({'mixed-port': 7001}, ['mixed-port']);
    container
        .read(profilesProvider.notifier)
        .put(_profile(1, updatedAt: first.add(const Duration(hours: 1))));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(settings().mixedPort, 7001);
    verify(() => core.getProfileBase(any())).called(2);
  });

  test('the file\'s GLOBAL override follows the current profile', () async {
    container.listen(globalOverrideProvider, (_, _) {});
    when(() => core.getProfileBase(any())).thenAnswer(
      (_) async =>
          const ProfileBase(config: {}, digest: 'd', globalOverride: true),
    );

    await select(_profile(1));
    expect(container.read(globalOverrideProvider), isTrue);

    await select(_profile(2, type: ProfileType.custom));
    expect(container.read(globalOverrideProvider), isFalse);
  });

  test(
    'a read still pending when a custom profile is chosen is dropped',
    () async {
      container.listen(globalOverrideProvider, (_, _) {});
      final pending = Completer<ProfileBase>();
      when(() => core.getProfileBase(any())).thenAnswer((_) => pending.future);

      await select(_profile(1));
      await select(_profile(2, type: ProfileType.custom));
      pending.complete(
        const ProfileBase(config: {}, digest: 'd', globalOverride: true),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(globalOverrideProvider), isFalse);
    },
  );

  test('a custom or scripted profile leaves the settings alone', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 1080));
    answer({}, []);

    await select(_profile(1, type: ProfileType.custom));
    await select(_profile(2, extendType: ExtendType.script));

    expect(settings().mixedPort, 1080);
    verifyNever(() => core.getProfileBase(any()));
  });

  test('a file the core cannot read leaves the settings alone', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 1080));
    when(
      () => core.getProfileBase(any()),
    ).thenThrow(const FileSystemException('missing'));

    await select(_profile(1));

    expect(settings().mixedPort, 1080);
  });

  test(
    'the authentication a file names fills the account until taken',
    () async {
      container.listen(appSettingProvider, (_, _) {});
      container.listen(networkSettingProvider, (_, _) {});
      AuthenticationProps auth() =>
          container.read(networkSettingProvider).authentication;
      answer(
        {
          'authentication': ['panel:secret'],
        },
        ['authentication'],
      );

      await select(_profile(1));
      expect(
        auth(),
        const AuthenticationProps(
          enable: true,
          username: 'panel',
          password: 'secret',
        ),
      );
      expect(
        container.read(managedSettingsProvider),
        contains('clash.authentication'),
      );

      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(ownedSettings: {'clash.authentication'}),
          );
      container
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith.authentication(username: 'mine'));
      await select(_profile(1, updatedAt: DateTime(2026, 10, 31)));
      expect(auth().username, 'mine');

      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(ownedSettings: {}));
      answer({}, []);
      await select(_profile(2));
      expect(auth(), const AuthenticationProps());
    },
  );
}
