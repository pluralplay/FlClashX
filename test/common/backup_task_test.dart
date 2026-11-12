import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

import '../helpers/app_paths.dart';

/// The public entry points hand their work to a background isolate, which
/// cannot reach the mocked platform channels, so the tests drive the worker
/// functions the isolate calls. Those take every path as an argument, so each
/// test runs against its own temporary tree.
void main() {
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('backup_task_test');
    // File.copy does not create parent directories; in production these are the
    // already-existing temp and cache dirs the platform hands out.
    Directory(join(root.path, 'tmp')).createSync(recursive: true);
    Directory(join(root.path, 'archive')).createSync(recursive: true);
    await useAppPaths(root);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Directory makeDir(String name) =>
      Directory(join(root.path, name, uniqueId))..createSync(recursive: true);

  File writeFile(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  group('shakeOrphanFiles', () {
    test('reports only the files whose name is not a live id', () {
      final profiles = makeDir('profiles');
      final scripts = makeDir('scripts');
      final providers = makeDir('providers');
      writeFile(join(profiles.path, '1.yaml'), 'keep');
      writeFile(join(profiles.path, '2.yaml'), 'drop');
      writeFile(join(scripts.path, '10.js'), 'keep');
      writeFile(join(scripts.path, '20.js'), 'drop');
      writeFile(join(providers.path, '1', 'proxies', 'abc'), 'keep');
      writeFile(join(providers.path, '2', 'proxies', 'abc'), 'drop');

      final orphans = shakeOrphanFiles(
        profileIds: [1],
        scriptIds: [10],
        profilesDirPath: profiles.path,
        providersDirPath: providers.path,
        scriptsDirPath: scripts.path,
        providerFileNames: const [],
        providerCacheDirPath: join(root.path, 'missing'),
      );

      expect(orphans.map(basename), unorderedEquals(['2.yaml', '20.js', '2']));
      expect(
        orphans.singleWhere((path) => basename(path) == '2'),
        join(providers.path, '2'),
      );
    });

    test('reports the whole provider directory a dead profile left behind', () {
      final providers = makeDir('providers');
      writeFile(join(providers.path, '3', 'proxies', 'abc'), 'drop');
      writeFile(join(providers.path, '3', 'rules', 'def'), 'drop');
      writeFile(join(providers.path, 'stray'), 'drop');

      final orphans = shakeOrphanFiles(
        profileIds: const [],
        scriptIds: const [],
        profilesDirPath: join(root.path, 'missing'),
        providersDirPath: providers.path,
        scriptsDirPath: join(root.path, 'missing'),
        providerFileNames: const [],
        providerCacheDirPath: join(root.path, 'missing'),
      );

      expect(
        orphans,
        unorderedEquals([
          join(providers.path, '3'),
          join(providers.path, 'stray'),
        ]),
      );
    });

    test('treats an unparsable file name as an orphan', () {
      final profiles = makeDir('profiles');
      writeFile(join(profiles.path, 'stray.yaml'), 'drop');

      final orphans = shakeOrphanFiles(
        profileIds: [1],
        scriptIds: const [],
        profilesDirPath: profiles.path,
        providersDirPath: join(root.path, 'missing'),
        scriptsDirPath: join(root.path, 'missing'),
        providerFileNames: const [],
        providerCacheDirPath: join(root.path, 'missing'),
      );

      expect(orphans.map(basename), ['stray.yaml']);
    });

    test('does not descend into the nested providers folder', () {
      final profiles = makeDir('profiles');
      final nested = Directory(join(profiles.path, 'providers'))
        ..createSync(recursive: true);
      writeFile(join(nested.path, '99.yaml'), 'not scanned here');

      final orphans = shakeOrphanFiles(
        profileIds: [1],
        scriptIds: const [],
        profilesDirPath: profiles.path,
        providersDirPath: join(root.path, 'missing'),
        scriptsDirPath: join(root.path, 'missing'),
        providerFileNames: const [],
        providerCacheDirPath: join(root.path, 'missing'),
      );

      expect(orphans, isEmpty);
    });

    test('reports a provider cache file no row names any more', () {
      final cache = makeDir('provider_cache');
      writeFile(join(cache.path, 'rules', 'live'), 'keep');
      writeFile(join(cache.path, 'rules', 'stale'), 'drop');

      final orphans = shakeOrphanFiles(
        profileIds: const [],
        scriptIds: const [],
        providerFileNames: const ['live'],
        profilesDirPath: join(root.path, 'missing'),
        providersDirPath: join(root.path, 'missing'),
        providerCacheDirPath: cache.path,
        scriptsDirPath: join(root.path, 'missing'),
      );

      expect(orphans, [join(cache.path, 'rules', 'stale')]);
    });

    test('ignores directories that do not exist', () {
      expect(
        shakeOrphanFiles(
          profileIds: const [],
          scriptIds: const [],
          profilesDirPath: join(root.path, 'nope'),
          providersDirPath: join(root.path, 'nope'),
          scriptsDirPath: join(root.path, 'nope'),
          providerFileNames: const [],
          providerCacheDirPath: join(root.path, 'missing'),
        ),
        isEmpty,
      );
    });
  });

  group('migrateLegacyConfig', () {
    late Directory source;
    late Directory target;

    setUp(() {
      source = makeDir('legacy_source');
      target = makeDir('legacy_target');
    });

    Map<String, Object?> legacyConfig({
      List<Object?> scripts = const [],
      List<Object?> rules = const [],
      List<Object?> profiles = const [],
      Map<String, Object?> extra = const {},
    }) => {'scripts': scripts, 'rules': rules, 'profiles': profiles, ...extra};

    test(
      'rewrites script ids and writes the content into the target',
      () async {
        final data = await migrateLegacyConfig(
          configMap: legacyConfig(
            scripts: [
              {'id': 'script-a', 'label': 'A', 'content': 'export default 1;'},
            ],
          ),
          sourcePath: source.path,
          targetPath: target.path,
        );

        final script = data.scripts.single;
        expect(script.label, 'A');
        expect(
          File(
            join(target.path, 'scripts', '${script.id}.js'),
          ).readAsStringSync(),
          'export default 1;',
        );
      },
    );

    test('skips a script entry that is missing a required field', () async {
      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          scripts: [
            {'id': 'no-content', 'label': 'A'},
            {'id': 'ok', 'label': 'B', 'content': 'body'},
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.scripts.map((item) => item.label), ['B']);
    });

    test('falls back to scriptProps when the scripts list is empty', () async {
      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          extra: {
            'scriptProps': {
              'scripts': [
                {'id': 'nested', 'label': 'Nested', 'content': 'body'},
              ],
            },
          },
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.scripts.map((item) => item.label), ['Nested']);
    });

    test('copies the profile file under its new id', () async {
      writeFile(join(source.path, 'profiles', 'old-1.yaml'), 'proxies: []');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {'id': 'old-1', 'label': 'Legacy', 'autoUpdateDuration': 0},
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final profile = data.profiles.single;
      expect(profile.label, 'Legacy');
      expect(
        File(
          join(target.path, 'profiles', '${profile.id}.yaml'),
        ).readAsStringSync(),
        'proxies: []',
      );
    });

    test('a profile id that is a path reaches no file outside', () async {
      final outside = makeDir('legacy_outside');
      writeFile(join(outside.path, 'secret.yaml'), 'secret: 1');
      final escape = posix.relative(
        join(outside.path, 'secret'),
        from: join(source.path, 'profiles'),
      );

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {'id': escape, 'label': 'Escape', 'autoUpdateDuration': 0},
            {'id': 'missing', 'label': 'Missing', 'autoUpdateDuration': 0},
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.profiles.map((profile) => profile.label), ['Missing']);
      expect(Directory(join(target.path, 'profiles')).existsSync(), isFalse);
      expect(
        File(join(source.path, 'profiles', 'missing.yaml')).existsSync(),
        isFalse,
      );
    });

    test('carries a FlClashX 0.4 profile with its headers and rules', () async {
      writeFile(
        join(source.path, 'profiles', '1720000000000.yaml'),
        'proxies: []',
      );

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {
              'id': '1720000000000',
              'label': 'Remna',
              'url': 'https://sub.example.com/abc',
              'autoUpdateDuration': 86400000000,
              'autoUpdate': true,
              'selectedMap': {'Auto': 'NL'},
              'unfoldSet': ['Auto'],
              'subscriptionInfo': {
                'upload': 1,
                'download': 2,
                'total': 3,
                'expire': 4,
              },
              'providerHeaders': {
                'announce': 'Hi',
                'flclashx-newboard': 'true',
              },
              'overrideData': {
                'enable': true,
                'rule': {
                  'type': 'added',
                  'overrideRules': [
                    {'id': 'o1', 'value': 'DOMAIN,ignored.com,DIRECT'},
                  ],
                  'addedRules': [
                    {'id': 'a1', 'value': 'DOMAIN,example.com,DIRECT'},
                  ],
                },
              },
            },
            {
              'id': '1720000000001',
              'autoUpdateDuration': 0,
              'overrideData': {
                'enable': false,
                'rule': {
                  'type': 'added',
                  'addedRules': [
                    {'id': 'a2', 'value': 'DOMAIN,off.com,DIRECT'},
                  ],
                },
              },
            },
          ],
          extra: {
            'currentProfileId': '1720000000000',
            'appSetting': {
              'newDashboard': true,
              'dashboardWidgets': ['announce', 'metainfo', 'zashboardButton'],
            },
          },
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final profile = data.profiles.first;
      expect(profile.type, ProfileType.url);
      expect(profile.label, 'Remna');
      expect(profile.providerHeaders, {
        'announce': 'Hi',
        'flclashx-newboard': 'true',
      });
      expect(profile.selectedMap, {'Auto': 'NL'});
      expect(profile.subscriptionInfo?.total, 3);
      expect(profile.autoUpdateDuration, const Duration(days: 1));
      expect(data.rules.map((rule) => rule.content), ['example.com']);
      expect(data.rules.single.profileId, profile.id);
      expect(data.configMap?['currentProfileId'], profile.id);
      expect(
        File(
          join(target.path, 'profiles', '${profile.id}.yaml'),
        ).readAsStringSync(),
        'proxies: []',
      );

      final config = Config.realFromJson(data.configMap);
      expect(config.themeProps.style, ThemeStyle.enhanced);
      expect(config.appSettingProps.dashboardWidgets, [
        DashboardWidget.currentOutbound,
        DashboardWidget.announcement,
        DashboardWidget.profiles,
      ]);
    });

    test('keeps a FlClashX 0.4 config without the hero flag on the standard '
        'page', () async {
      final data = await migrateLegacyConfig(
        configMap: legacyConfig(profiles: const []),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final config = Config.realFromJson(data.configMap);
      expect(config.themeProps.style, ThemeStyle.original);
    });

    test(
      'turns the FlClashX 0.4 override switches into owned settings',
      () async {
        final data = await migrateLegacyConfig(
          configMap: legacyConfig(
            extra: {
              'appSetting': {
                'overrideNetworkSettings': true,
                'overrideProviderSettings': true,
              },
            },
          ),
          sourcePath: source.path,
          targetPath: target.path,
        );

        final owned = Config.realFromJson(
          data.configMap,
        ).appSettingProps.ownedSettings;
        expect(
          owned,
          containsAll([
            'clash.mixed-port',
            'clash.allow-lan',
            'clash.ipv6',
            'clash.find-process-mode',
            'clash.tun.stack',
            ...appSwitchSettings.values,
          ]),
        );
        expect(owned, hasLength(5 + appSwitchSettings.length));

        final untouched = await migrateLegacyConfig(
          configMap: legacyConfig(
            extra: {
              'appSetting': {
                'overrideNetworkSettings': false,
                'overrideProviderSettings': false,
              },
            },
          ),
          sourcePath: source.path,
          targetPath: target.path,
        );
        expect(
          Config.realFromJson(
            untouched.configMap,
          ).appSettingProps.ownedSettings,
          isEmpty,
        );
      },
    );

    test('links added rules to the profile that declared them', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {
              'id': 'p1',
              'autoUpdateDuration': 0,
              'overwrite': {
                'type': 'standard',
                'standardOverwrite': {
                  'addedRules': [
                    {'id': 'r1', 'value': 'DOMAIN,example.com,DIRECT'},
                  ],
                },
              },
            },
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final profile = data.profiles.single;
      final rule = data.rules.single;
      expect(rule.content, 'example.com');
      expect(rule.profileId, profile.id);
      expect(profile.type, ProfileType.file);
      expect(data.disabledRules, isEmpty);
    });

    test(
      'keeps a disabled rule only for a rule id it has already seen',
      () async {
        writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

        final data = await migrateLegacyConfig(
          configMap: legacyConfig(
            profiles: [
              {
                'id': 'p1',
                'autoUpdateDuration': 0,
                'overwrite': {
                  'type': 'standard',
                  'standardOverwrite': {
                    'addedRules': [
                      {'id': 'r1', 'value': 'DOMAIN,example.com,DIRECT'},
                    ],
                    'disabledRuleIds': ['r1', 'never-seen'],
                  },
                },
              },
            ],
          ),
          sourcePath: source.path,
          targetPath: target.path,
        );

        expect(data.disabledRules, [
          DisabledRule(
            profileId: data.profiles.single.id,
            ruleId: data.rules.single.id,
          ),
        ]);
      },
    );

    test('gives a profile with a url the url type', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {
              'id': 'p1',
              'url': 'https://example.com/sub',
              'autoUpdateDuration': 0,
            },
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.profiles.single.type, ProfileType.url);
    });

    test('points the profile at its remapped script id', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          scripts: [
            {'id': 's1', 'label': 'S', 'content': 'body'},
          ],
          profiles: [
            {
              'id': 'p1',
              'autoUpdateDuration': 0,
              'overwrite': {
                'type': 'script',
                'scriptOverwrite': {'scriptId': 's1'},
              },
            },
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.profiles.single.scriptId, data.scripts.single.id);
      expect(data.profiles.single.extendType, ExtendType.script);
    });

    test('binds the script FlClashX 0.4 ran on every profile', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {
              'id': 'p1',
              'autoUpdateDuration': 0,
              'overrideData': {
                'enable': true,
                'rule': {
                  'type': 'added',
                  'addedRules': [
                    {'id': 'a1', 'value': 'DOMAIN,example.com,DIRECT'},
                  ],
                },
              },
            },
          ],
          extra: {
            'scriptProps': {
              'currentId': 's1',
              'scripts': [
                {'id': 's1', 'label': 'S', 'content': 'body'},
              ],
            },
          },
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final profile = data.profiles.single;
      expect(profile.extendType, ExtendType.script);
      expect(profile.scriptId, data.scripts.single.id);
      expect(data.rules.single.profileId, profile.id);
    });

    test(
      'keeps a FlClashX 0.4 override list replacing the profile rules',
      () async {
        writeFile(join(source.path, 'profiles', 'p1.yaml'), '');
        writeFile(join(source.path, 'profiles', 'p2.yaml'), '');

        final data = await migrateLegacyConfig(
          configMap: legacyConfig(
            profiles: [
              {
                'id': 'p1',
                'label': 'Work',
                'autoUpdateDuration': 0,
                'overrideData': {
                  'enable': true,
                  'rule': {
                    'type': 'override',
                    'overrideRules': [
                      {'id': 'o1', 'value': 'DOMAIN,example.com,DIRECT'},
                      {'id': 'o2', 'value': 'MATCH,Proxy'},
                    ],
                    'addedRules': [
                      {'id': 'a1', 'value': 'DOMAIN,unused.com,DIRECT'},
                    ],
                  },
                },
              },
              {
                'id': 'p2',
                'autoUpdateDuration': 0,
                'overrideData': {
                  'enable': true,
                  'rule': {'type': 'override', 'overrideRules': []},
                },
              },
            ],
          ),
          sourcePath: source.path,
          targetPath: target.path,
        );

        expect(data.rules, isEmpty);
        expect(data.scripts, hasLength(2));
        String scriptOf(Profile profile) {
          expect(profile.extendType, ExtendType.script);
          return File(
            join(target.path, 'scripts', '${profile.scriptId}.js'),
          ).readAsStringSync();
        }

        final work = scriptOf(data.profiles.first);
        expect(work, contains('config.rules = ['));
        expect(
          work.indexOf('DOMAIN,example.com,DIRECT'),
          lessThan(work.indexOf('MATCH,Proxy')),
        );
        expect(work, isNot(contains('unused.com')));
        expect(scriptOf(data.profiles.last), contains('config.rules = []'));
      },
    );

    test('falls a custom overwrite back to a standard one', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');

      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {
              'id': 'p1',
              'autoUpdateDuration': 0,
              'overwrite': {'type': 'custom'},
            },
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.profiles.single.extendType, ExtendType.standard);
    });

    test('remaps currentProfileId and nulls it when there is none', () async {
      writeFile(join(source.path, 'profiles', 'p1.yaml'), '');
      final configMap = legacyConfig(
        profiles: [
          {'id': 'p1', 'autoUpdateDuration': 0},
        ],
        extra: {'currentProfileId': 'p1'},
      );

      final data = await migrateLegacyConfig(
        configMap: configMap,
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.configMap?['currentProfileId'], data.profiles.single.id);

      final without = await migrateLegacyConfig(
        configMap: legacyConfig(),
        sourcePath: source.path,
        targetPath: target.path,
      );
      expect(without.configMap?['currentProfileId'], isNull);
    });

    test('renames the config keys the current schema expects', () async {
      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          extra: {
            'accessControl': <String, Object?>{'acceptList': <String>[]},
            'isAccessControl': true,
            'vpnProps': <String, Object?>{},
            'dav': {'uri': 'https://dav.example'},
            'appSetting': {'recoveryStrategy': 'compatible'},
            'proxiesStyle': {'cardType': 'expand'},
          },
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      final configMap = data.configMap!;
      final vpnProps = configMap['vpnProps']! as Map;
      expect((vpnProps['accessControl'] as Map)['enable'], isTrue);
      expect(vpnProps['accessControlProps'], vpnProps['accessControl']);
      expect((configMap['davProps'] as Map)['uri'], 'https://dav.example');
      expect(
        (configMap['appSettingProps'] as Map)['restoreStrategy'],
        'compatible',
      );
      expect(configMap['proxiesStyleProps'], configMap['proxiesStyle']);
    });

    test('skips a profile entry without an id', () async {
      final data = await migrateLegacyConfig(
        configMap: legacyConfig(
          profiles: [
            {'label': 'no id', 'autoUpdateDuration': 0},
          ],
        ),
        sourcePath: source.path,
        targetPath: target.path,
      );

      expect(data.profiles, isEmpty);
    });
  });

  group('backup and restore', () {
    const localProvider = ClashProvider(
      id: 4,
      label: 'Local rules',
      behavior: RuleProviderBehavior.classical,
      format: RuleProviderFormat.yaml,
    );
    late Directory home;
    late Directory staging;
    late String databasePath;

    setUp(() async {
      home = makeDir('home');
      staging = makeDir('staging');
      databasePath = join(home.path, 'database.sqlite');
    });

    Future<void> seedDatabase() async {
      final database = db.Database(NativeDatabase(File(databasePath)));
      await database.profilesDao.putAll([
        const Profile(
          id: 1,
          label: 'Backed up',
          autoUpdateDuration: Duration.zero,
        ).toCompanion(),
      ]);
      await database.scripts.put(
        Script(
          id: 2,
          label: 'Script',
          lastUpdateTime: DateTime(2026),
        ).toCompanion(),
      );
      await database.rulesDao.putRule(
        const Rule(id: 3, content: 'example.com', order: 'a'),
        profileId: 1,
      );
      await database.clashProvidersDao.putAll([localProvider.toCompanion()]);
      await database.close();
    }

    Future<String> backup({
      Map<String, Object?> configMap = const {'version': 1},
      List<String>? entries,
    }) async {
      entries ??= BackupEntries.of(
        profileIds: const [1],
        scriptIds: const [2],
        providers: const [localProvider],
      );
      final archivePath = join(root.path, 'archive', '$uniqueId.zip');
      await writeBackupArchive(
        archivePath: archivePath,
        configMap: configMap,
        databaseSnapshotPath: databasePath,
        homeDirPath: home.path,
        entries: entries,
      );
      return archivePath;
    }

    Future<String> zipOf(Map<String, List<int>> files) async {
      final archivePath = join(root.path, 'archive', '$uniqueId.zip');
      final encoder = ZipFileEncoder()..create(archivePath);
      for (final MapEntry(:key, :value) in files.entries) {
        encoder.addArchiveFile(ArchiveFile.bytes(key, value));
      }
      await encoder.close();
      return archivePath;
    }

    Future<MigrationData> restore(String archivePath) {
      return readBackupArchive(
        archivePath: archivePath,
        stagingDirPath: staging.path,
      );
    }

    Matcher failsWith(BackupFailure failure) => throwsA(
      isA<BackupException>().having(
        (error) => error.failure,
        'failure',
        failure,
      ),
    );

    test('the archive carries the database, the config and only the listed '
        'files', () async {
      await seedDatabase();
      writeFile(join(home.path, 'profiles', '1.yaml'), 'proxies: []');
      writeFile(join(home.path, 'profiles', '9.yaml'), 'not listed');
      writeFile(join(home.path, 'scripts', '2.js'), 'body');

      final archivePath = await backup();

      final names = ZipDecoder()
          .decodeStream(InputFileStream(archivePath))
          .files
          .map((file) => file.name)
          .toSet();
      expect(names, {
        backupDatabaseName,
        configJsonName,
        'profiles/1.yaml',
        'scripts/2.js',
      });
    });

    test('restoring returns the rows and stages the files', () async {
      await seedDatabase();
      writeFile(join(home.path, 'profiles', '1.yaml'), 'proxies: []');
      writeFile(join(home.path, 'scripts', '2.js'), 'body');
      writeFile(
        join(home.path, 'providers', 'rules', localProvider.fileName),
        'payload: []',
      );
      final archivePath = await backup();

      final data = await restore(archivePath);

      expect(data.profiles.single.label, 'Backed up');
      expect(data.scripts.single.label, 'Script');
      expect(data.rules.single.content, 'example.com');
      expect(data.rules.single.profileId, 1);
      expect(data.clashProviders.single.label, 'Local rules');
      expect(data.configMap?['version'], 1);
      expect(
        BackupEntries.ofData(data).map(
          (entry) => File(
            BackupEntries.resolve(staging.path, entry),
          ).readAsStringSync(),
        ),
        ['proxies: []', 'body', 'payload: []'],
      );
    });

    test('a version 0 archive goes through the legacy migration', () async {
      await seedDatabase();
      writeFile(join(home.path, 'profiles', 'legacy.yaml'), 'proxies: []');
      final archivePath = await backup(
        configMap: {
          'version': 0,
          'profiles': [
            {'id': 'legacy', 'label': 'Old', 'autoUpdateDuration': 0},
          ],
        },
        entries: const ['profiles/legacy.yaml'],
      );

      final data = await restore(archivePath);

      final profile = data.profiles.single;
      expect(profile.label, 'Old');
      expect(
        profile.id,
        isNot(0),
        reason: 'the legacy string id must be replaced by a snowflake id',
      );
      expect(
        File(
          BackupEntries.resolve(
            staging.path,
            BackupEntries.profile(profile.id),
          ),
        ).readAsStringSync(),
        'proxies: []',
      );
    });

    test(
      'an entry that climbs out of the staging directory is dropped',
      () async {
        final archivePath = await zipOf({
          configJsonName: utf8.encode(json.encode({'version': 1})),
          '../escaped.txt': utf8.encode('outside'),
        });

        await restore(archivePath);

        expect(
          File(join(staging.parent.path, 'escaped.txt')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'an entry whose bytes do not match its checksum is rejected',
      () async {
        final archivePath = join(root.path, 'archive', '$uniqueId.zip');
        final encoder = ZipFileEncoder()..create(archivePath);
        encoder.addArchiveFile(
          ArchiveFile.string(configJsonName, json.encode({'version': 1})),
        );
        final profile = utf8.encode('proxies: GOOD-PROFILE-CONTENT');
        encoder.addArchiveFile(
          ArchiveFile.noCompress('profiles/1.yaml', profile.length, profile),
        );
        await encoder.close();
        final bytes = File(archivePath).readAsBytesSync();
        final at = latin1.decode(bytes).indexOf('GOOD');
        bytes.setRange(at, at + 4, utf8.encode('BAD!'));
        File(archivePath).writeAsBytesSync(bytes);

        await expectLater(
          restore(archivePath),
          failsWith(BackupFailure.invalid),
        );
      },
    );

    test('an archive that inflates past the size limits is rejected', () async {
      final previousEntry = maxBackupEntryBytes;
      final previousTotal = maxBackupBytes;
      addTearDown(() {
        maxBackupEntryBytes = previousEntry;
        maxBackupBytes = previousTotal;
      });
      final config = utf8.encode(json.encode({'version': 1}));
      maxBackupBytes = 1 << 20;

      maxBackupEntryBytes = 64;
      await expectLater(
        restore(
          await zipOf({configJsonName: config, 'big': List.filled(65, 0)}),
        ),
        failsWith(BackupFailure.invalid),
      );

      maxBackupEntryBytes = 1 << 20;
      maxBackupBytes = config.length + 64;
      await expectLater(
        restore(
          await zipOf({
            configJsonName: config,
            'a': List.filled(40, 0),
            'b': List.filled(40, 0),
          }),
        ),
        failsWith(BackupFailure.invalid),
      );
    });

    test(
      'a deflated entry inflating past its declared size is rejected',
      () async {
        final previous = maxBackupEntryBytes;
        addTearDown(() => maxBackupEntryBytes = previous);
        maxBackupEntryBytes = 64 << 10;
        final archivePath = await zipOf({
          configJsonName: utf8.encode(json.encode({'version': 1})),
          'bomb': List.filled(1 << 20, 0),
        });
        // The size fields of both headers claim 16 bytes for the 1 MiB entry.
        final bytes = File(archivePath).readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        for (var at = 0; at + 46 <= bytes.length; at++) {
          final signature = data.getUint32(at, Endian.little);
          final sizeAt = switch (signature) {
            0x04034b50 => at + 22,
            0x02014b50 => at + 24,
            _ => null,
          };
          if (sizeAt != null &&
              data.getUint32(sizeAt, Endian.little) == 1 << 20) {
            data.setUint32(sizeAt, 16, Endian.little);
          }
        }
        File(archivePath).writeAsBytesSync(bytes);

        await expectLater(
          restore(archivePath),
          failsWith(BackupFailure.invalid),
        );
        expect(
          File(join(staging.path, 'bomb')).lengthSync(),
          lessThanOrEqualTo(maxBackupEntryBytes),
        );
      },
    );

    test('a link in the archive is passed over, not unpacked', () async {
      final archivePath = await zipOf({
        configJsonName: utf8.encode(json.encode({'version': 1})),
        'link': utf8.encode('/etc/passwd'),
      });
      // archive writes no links, so the entry is marked one by hand: made on
      // Unix, with the file type of a symbolic link in its attributes.
      final bytes = File(archivePath).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      for (var at = 0; at + 50 <= bytes.length; at++) {
        if (data.getUint32(at, Endian.little) == 0x02014b50 &&
            utf8.decode(bytes.sublist(at + 46, at + 50)) == 'link') {
          data.setUint16(at + 4, 3 << 8 | 20, Endian.little);
          data.setUint32(at + 38, 0xA1FF << 16, Endian.little);
        }
      }
      File(archivePath).writeAsBytesSync(bytes);

      await restore(archivePath);

      expect(File(join(staging.path, configJsonName)).existsSync(), isTrue);
      expect(
        FileSystemEntity.typeSync(join(staging.path, 'link')),
        FileSystemEntityType.notFound,
      );
    });

    test('an archive without a config document is rejected', () async {
      final archivePath = await zipOf({'unrelated.txt': utf8.encode('x')});

      await expectLater(restore(archivePath), failsWith(BackupFailure.invalid));
    });

    test('a file that is not a zip archive is rejected', () async {
      final archivePath = writeFile(
        join(root.path, 'archive', '$uniqueId.zip'),
        'not a zip',
      ).path;

      await expectLater(restore(archivePath), failsWith(BackupFailure.invalid));
    });

    test('a config from a newer data version is rejected', () async {
      final archivePath = await zipOf({
        configJsonName: utf8.encode(
          json.encode({'version': Migration.currentVersion + 1}),
        ),
      });

      await expectLater(
        restore(archivePath),
        failsWith(BackupFailure.newerVersion),
      );
    });

    test('a database from a newer schema is rejected', () async {
      await seedDatabase();
      final raw = db.Database(NativeDatabase(File(databasePath)));
      await raw.customStatement(
        'PRAGMA user_version = ${raw.schemaVersion + 1}',
      );
      await raw.close();
      final archivePath = await backup();

      await expectLater(
        restore(archivePath),
        failsWith(BackupFailure.newerVersion),
      );
    });

    test('an archive without a database yields just the config', () async {
      final archivePath = await zipOf({
        configJsonName: utf8.encode(json.encode({'version': 1})),
      });

      final data = await restore(archivePath);

      expect(data.configMap?['version'], 1);
      expect(data.profiles, isEmpty);
      expect(data.scripts, isEmpty);
      expect(data.includesTables, isFalse);
    });
  });
}
