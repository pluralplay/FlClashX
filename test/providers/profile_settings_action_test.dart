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

  test('a subscription naming nothing puts the settings back', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 1080, ipv6: true));
    answer({}, []);

    await select(_profile(1));

    expect(settings().mixedPort, defaultMixedPort);
    expect(settings().ipv6, isTrue);
  });

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
}
