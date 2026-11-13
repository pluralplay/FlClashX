import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_paths.dart';
import '../helpers/preferences.dart';
import '../helpers/setup_actions.dart';

Profile _profile(int id, String label) => Profile(
  id: id,
  label: label,
  autoUpdateDuration: Duration.zero,
  extendType: ExtendType.standard,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database testDatabase;
  late Directory home;

  setUpAll(() async {
    await mockPreferences({'version': 1});
    await AppLocalizations.load(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-backup-action-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    testDatabase = Database(NativeDatabase.memory());
    database = testDatabase;
  });

  tearDown(() async {
    await testDatabase.close();
  });

  late ApplyRecordingSetupAction setupAction;

  ProviderContainer buildContainer() {
    setupAction = ApplyRecordingSetupAction();
    final container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(() => setupAction)],
    );
    addTearDown(container.dispose);
    return container;
  }

  BackupAction actionOf(ProviderContainer container) =>
      container.read(backupActionProvider.notifier);

  Map<String, Object?> configMapOf(ProviderContainer container) =>
      jsonDecode(jsonEncode(container.read(configProvider).toJson()))
          as Map<String, Object?>;

  group('backup and restore round trip', () {
    late Directory kept;

    setUp(() {
      kept = Directory.systemTemp.createTempSync('flclash-backup-kept-');
      addTearDown(() => kept.deleteSync(recursive: true));
    });

    Set<String> workDirs() => home
        .listSync()
        .map((entity) => basename(entity.path))
        .where((name) => name.startsWith('backup'))
        .toSet();

    Future<String> backupToKept(BackupAction action) async {
      final keptPath = join(kept.path, 'kept.zip');
      final delivered = await action.backup((archivePath) async {
        File(archivePath).copySync(keptPath);
        return true;
      });
      expect(delivered, isTrue);
      return keptPath;
    }

    test('restores the rows, files and settings a backup carries', () async {
      await testDatabase.profilesDao.putAll([
        _profile(1, 'Backed up').toCompanion(0),
      ]);
      final profileFile = File(await appPath.getProfilePath('1'))
        ..createSync(recursive: true)
        ..writeAsStringSync('proxies: []');
      final source = buildContainer()..listen(configProvider, (_, _) {});
      source.read(excludeSSIDsProvider.notifier).value = ['home-wifi'];
      final archivePath = await backupToKept(actionOf(source));

      await testDatabase.delete(testDatabase.profiles).go();
      profileFile.deleteSync();
      final target = buildContainer()..listen(configProvider, (_, _) {});
      final restored = await actionOf(
        target,
      ).restore(RestoreOption.all, (_) async => archivePath);

      expect(restored, isTrue);
      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['Backed up']);
      expect(profileFile.readAsStringSync(), 'proxies: []');
      expect(target.read(excludeSSIDsProvider), ['home-wifi']);
      expect(workDirs(), isEmpty);
    });

    test('carries the proxy chains of the profiles it backs up', () async {
      await testDatabase.profilesDao.putAll([
        _profile(1, 'Backed up').toCompanion(0),
      ]);
      final chains = jsonEncode([
        const ProxyChain(
          id: 'a',
          name: 'Telegram',
          hops: ['DE', 'NL'],
        ).toJson(),
      ]);
      final shared = await SharedPreferences.getInstance();
      await shared.setString('proxy_chains_1', chains);
      final archivePath = await backupToKept(actionOf(buildContainer()));

      await shared.setString('proxy_chains_1', '[]');
      final target = buildContainer();
      await actionOf(
        target,
      ).restore(RestoreOption.onlyProfiles, (_) async => archivePath);

      expect(shared.getString('proxy_chains_1'), chains);
      final restored = await target.read(proxyChainsProvider(1).future);
      expect(restored.single.name, 'Telegram');
    });

    test('pushes a restore that keeps the selected profile', () async {
      await testDatabase.profilesDao.putAll([
        _profile(1, 'Running').toCompanion(0),
      ]);
      final source = buildContainer()..listen(configProvider, (_, _) {});
      source.read(currentProfileIdProvider.notifier).value = 1;
      final archivePath = await backupToKept(actionOf(source));

      final target = buildContainer()..listen(configProvider, (_, _) {});
      target.read(currentProfileIdProvider.notifier).value = 1;
      await actionOf(
        target,
      ).restore(RestoreOption.onlyProfiles, (_) async => archivePath);

      expect(setupAction.applyCount, 1);
    });

    test('leaves a restore that switches the profile to its setup', () async {
      await testDatabase.profilesDao.putAll([
        _profile(1, 'Backed up').toCompanion(0),
        _profile(2, 'Other').toCompanion(1),
      ]);
      final source = buildContainer()..listen(configProvider, (_, _) {});
      source.read(currentProfileIdProvider.notifier).value = 1;
      final archivePath = await backupToKept(actionOf(source));

      final target = buildContainer()..listen(configProvider, (_, _) {});
      target.read(currentProfileIdProvider.notifier).value = 2;
      await actionOf(
        target,
      ).restore(RestoreOption.all, (_) async => archivePath);

      expect(target.read(currentProfileIdProvider), 1);
      expect(setupAction.applyCount, 0);
    });

    test('restores an icon gallery imported from a file', () async {
      const gallery = IconSet(
        id: 7,
        name: 'Local',
        icons: [IconSetIcon(name: 'cat', url: 'https://icons.example/cat.png')],
      );
      await testDatabase.iconSetsDao.putAll([gallery.toCompanion()]);
      final archivePath = await backupToKept(actionOf(buildContainer()));

      await testDatabase.delete(testDatabase.iconSets).go();
      final restored = await actionOf(
        buildContainer(),
      ).restore(RestoreOption.all, (_) async => archivePath);

      expect(restored, isTrue);
      expect(await testDatabase.iconSetsDao.query().get(), [gallery]);
    });

    test('removes the work directory when delivery fails', () async {
      final container = buildContainer();

      await expectLater(
        actionOf(
          container,
        ).backup((_) async => throw const SocketException('offline')),
        throwsA(isA<SocketException>()),
      );

      expect(workDirs(), isEmpty);
    });

    test('a cancelled fetch changes nothing', () async {
      final container = buildContainer();

      final restored = await actionOf(
        container,
      ).restore(RestoreOption.all, (_) async => null);

      expect(restored, isFalse);
    });

    test('an unreadable archive is reported and changes nothing', () async {
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      final bogus = File(join(kept.path, 'bogus.zip'))
        ..writeAsStringSync('not a zip');
      final container = buildContainer();

      await expectLater(
        actionOf(container).restore(RestoreOption.all, (_) async => bogus.path),
        throwsA(
          isA<MessageException>().having(
            (error) => error.message,
            'message',
            currentAppLocalizations.invalidBackupFile,
          ),
        ),
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['Pre-existing']);
      expect(workDirs(), isEmpty);
    });

    test('removes the staging an earlier version left behind', () async {
      final legacyArchive = File(join(home.path, 'backup.zip'))
        ..writeAsStringSync('stale');
      final legacyStaging = Directory(join(home.path, 'restore'))..createSync();
      final container = buildContainer();

      await actionOf(container).restore(RestoreOption.all, (_) async => null);

      expect(legacyArchive.existsSync(), isFalse);
      expect(legacyStaging.existsSync(), isFalse);
    });
  });

  group('applyRestore writes the database', () {
    test('inserts the profiles the backup carries', () async {
      final container = buildContainer();

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
    });

    test('a backup without chains leaves the chains a profile has', () async {
      final shared = await SharedPreferences.getInstance();
      await shared.setString('proxy_chains_1', '["kept"]');

      await actionOf(buildContainer()).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      expect(shared.getString('proxy_chains_1'), '["kept"]');
    });

    test('an override restore drops profiles the backup omits', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
    });

    for (final (name, data, kept) in [
      (
        'an override restore of an empty backup leaves no profile',
        const MigrationData(),
        <String>[],
      ),
      (
        'an override restore of settings alone keeps the profiles',
        const MigrationData(includesTables: false),
        ['Pre-existing'],
      ),
    ]) {
      test(name, () async {
        final container = buildContainer();
        await testDatabase.profilesDao.putAll([
          _profile(9, 'Pre-existing').toCompanion(0),
        ]);
        container
            .read(appSettingProvider.notifier)
            .update(
              (state) =>
                  state.copyWith(restoreStrategy: RestoreStrategy.override),
            );

        await actionOf(
          container,
        ).applyRestore(data, RestoreOption.onlyProfiles);

        final stored = await testDatabase.profilesDao.query().get();
        expect(stored.map((item) => item.label), kept);
      });
    }

    test('a compatible restore keeps profiles the backup omits', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.compatible),
          );

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'From backup')]),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label).toSet(), {
        'Pre-existing',
        'From backup',
      });
    });

    test('a restore drops the cache of a provider it replaced', () async {
      const dropped = ClashProvider(
        id: 5,
        label: 'Dropped',
        url: 'https://example.com/dropped.yaml',
      );
      const kept = ClashProvider(id: 6, label: 'Kept');
      await testDatabase.clashProvidersDao.putAll(
        [dropped, kept].map((item) => item.toCompanion()),
      );
      for (final path in [
        await dropped.path,
        await dropped.compiledPath,
        await kept.path,
        await kept.compiledPath,
      ]) {
        File(path).createSync(recursive: true);
      }
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        const MigrationData(clashProviders: [kept]),
        RestoreOption.onlyProfiles,
      );

      expect(File(await dropped.path).existsSync(), isFalse);
      expect(File(await dropped.compiledPath).existsSync(), isFalse);
      expect(File(await kept.path).existsSync(), isTrue);
      expect(
        File(await kept.compiledPath).existsSync(),
        isFalse,
        reason: 'the restored source is compiled again on first use',
      );
    });

    test('rows that fail to restore take their files back out', () async {
      final replaced = File(await appPath.getProfilePath('41'))
        ..createSync(recursive: true)
        ..writeAsStringSync('current');
      final added = File(await appPath.getProfilePath('42'));
      final staging = Directory.systemTemp.createTempSync('flclash-staging-');
      addTearDown(() => staging.deleteSync(recursive: true));
      for (final id in [41, 42]) {
        File(BackupEntries.resolve(staging.path, BackupEntries.profile(id)))
          ..createSync(recursive: true)
          ..writeAsStringSync('from backup');
      }
      await testDatabase.customStatement(
        'CREATE TRIGGER refuse_profiles BEFORE INSERT ON profiles '
        "BEGIN SELECT RAISE(ABORT, 'refused'); END",
      );

      await expectLater(
        actionOf(buildContainer()).applyRestore(
          MigrationData(profiles: [_profile(41, 'One'), _profile(42, 'Two')]),
          RestoreOption.onlyProfiles,
          stagingDirPath: staging.path,
        ),
        throwsA(anything),
      );

      expect(replaced.readAsStringSync(), 'current');
      expect(added.existsSync(), isFalse);
    });

    test('a backup carrying only proxy groups still writes them', () async {
      await testDatabase.profiles.put(
        const Profile(id: 7, autoUpdateDuration: Duration.zero).toCompanion(),
      );
      final container = buildContainer();

      await actionOf(container).applyRestore(
        const MigrationData(
          proxyGroups: [
            ProxyGroup(
              id: 1,
              profileId: 7,
              name: 'Selector',
              type: GroupType.Selector,
            ),
          ],
        ),
        RestoreOption.onlyProfiles,
      );

      final stored = await testDatabase.proxyGroupsDao.query(7).get();
      expect(
        stored.map((item) => item.name),
        ['Selector'],
        reason:
            'proxyGroups belongs in the guard that decides whether the batch '
            'runs, not only in the batch body',
      );
    });
  });

  group('applyRestore writes the settings providers', () {
    test('restores every settings provider the config carries', () async {
      final source = buildContainer();
      source
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoLaunch: true));
      source.read(currentProfileIdProvider.notifier).value = 42;
      source
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: 7899));
      final configMap = configMapOf(source);

      final target = buildContainer();
      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(currentProfileIdProvider), 42);
      expect(target.read(appSettingProvider).autoLaunch, isTrue);
      expect(target.read(patchClashConfigProvider).mixedPort, 7899);
    });

    test('keeps the bound WebDAV account when the backup has none', () async {
      final configMap = configMapOf(buildContainer());
      const dav = DAVProps(uri: 'https://dav.example', user: 'me');
      final target = buildContainer();
      target.read(davSettingProvider.notifier).value = dav;

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(davSettingProvider), dav);
    });

    test('keeps the picked apps when the backup lists none', () async {
      final configMap = configMapOf(buildContainer());
      const picked = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['com.example.browser'],
      );
      final target = buildContainer();
      target
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: picked));

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(vpnSettingProvider).accessControlProps, picked);
    });

    test('takes the apps a backup lists from another phone', () async {
      const listed = AccessControlProps(
        enable: true,
        rejectList: ['com.example.bank'],
      );
      final source = buildContainer();
      source
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: listed));
      final configMap = configMapOf(source);
      final target = buildContainer();
      target
          .read(vpnSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              accessControlProps: const AccessControlProps(
                acceptList: ['com.example.browser'],
              ),
            ),
          );

      await actionOf(
        target,
      ).applyRestore(MigrationData(configMap: configMap), RestoreOption.all);

      expect(target.read(vpnSettingProvider).accessControlProps, listed);
    });

    test('leaves the settings untouched for an onlyProfiles restore', () async {
      final source = buildContainer();
      source.read(currentProfileIdProvider.notifier).value = 42;
      final configMap = configMapOf(source);

      final target = buildContainer();
      final before = target.read(currentProfileIdProvider);

      await actionOf(target).applyRestore(
        MigrationData(configMap: configMap, profiles: [_profile(1, 'P')]),
        RestoreOption.onlyProfiles,
      );

      expect(target.read(currentProfileIdProvider), before);
      expect(await testDatabase.profilesDao.query().get(), hasLength(1));
    });

    test('a backup without a config still restores the database', () async {
      final container = buildContainer();
      final before = container.read(currentProfileIdProvider);

      await actionOf(container).applyRestore(
        MigrationData(profiles: [_profile(1, 'P')]),
        RestoreOption.all,
      );

      expect(container.read(currentProfileIdProvider), before);
      expect(await testDatabase.profilesDao.query().get(), hasLength(1));
    });
  });

  group('a config with unreadable values', () {
    test('restores the rest without keeping a dropped profile', () async {
      final container = buildContainer();
      await testDatabase.profilesDao.putAll([
        _profile(9, 'Pre-existing').toCompanion(0),
      ]);
      container.read(currentProfileIdProvider.notifier).value = 9;
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(restoreStrategy: RestoreStrategy.override),
          );

      await actionOf(container).applyRestore(
        MigrationData(
          configMap: const {
            'currentProfileId': 'not an int',
            'appSettingProps': {'hideIp': true},
          },
          profiles: [_profile(1, 'From backup')],
        ),
        RestoreOption.all,
      );

      final stored = await testDatabase.profilesDao.query().get();
      expect(stored.map((item) => item.label), ['From backup']);
      expect(container.read(currentProfileIdProvider), isNull);
      expect(container.read(appSettingProvider).hideIp, true);
    });
  });
}
