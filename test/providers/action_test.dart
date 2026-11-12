import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/app_paths.dart';
import '../helpers/setup_actions.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

const _oldUrl = 'https://sub.example.com/old';
const _newUrl = 'https://sub.example.com/new';

/// Answers [_newUrl] at once and [_oldUrl] only when [answer] is called.
class _HeldFetch {
  final started = Completer<void>();
  final _response = Completer<Response<Uint8List>>();

  Future<Response<Uint8List>> call(
    String url, {
    Duration timeout = downloadTimeoutDuration,
    Map<String, String> headers = const {},
  }) {
    if (url != _oldUrl) {
      return Future.value(_answer(url, 'proxies: [] # new'));
    }
    started.complete();
    return _response.future;
  }

  void answer(String body) => _response.complete(_answer(_oldUrl, body));

  static Response<Uint8List> _answer(String url, String body) => Response(
    requestOptions: RequestOptions(path: url),
    statusCode: 200,
    data: Uint8List.fromList(utf8.encode(body)),
  );
}

typedef _HeldDownload = ({
  Profile profile,
  _HeldFetch fetch,
  ProviderContainer container,
  ProfilesAction action,
  ApplyRecordingSetupAction setupAction,
});

Future<_HeldDownload> _holdDownload() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await AppLocalizations.load(const Locale('en'));
  final root = await Directory.systemTemp.createTemp('profiles_action_');
  addTearDown(() => root.delete(recursive: true));
  await useAppPaths(root);
  final profile = Profile.normal(
    label: 'Sub',
    url: _oldUrl,
    sendDeviceHeaders: false,
  );
  final core = _MockCoreHandlerInterface();
  when(() => core.validateConfig(any())).thenAnswer((_) async => '');
  when(() => core.clearEffect(any())).thenAnswer((_) async => '');
  final setupAction = ApplyRecordingSetupAction();
  final container = ProviderContainer(
    overrides: [
      currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
      profilesProvider.overrideWith(() => TestProfiles([profile])),
      coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      setupActionProvider.overrideWith(() => setupAction),
    ],
  );
  addTearDown(container.dispose);
  final fetch = _HeldFetch();
  final action = container.read(profilesActionProvider.notifier)
    ..fetch = fetch.call;
  return (
    profile: profile,
    fetch: fetch,
    container: container,
    action: action,
    setupAction: setupAction,
  );
}

void main() {
  group('ProfilesAction', () {
    test('keeps edited profile data when remote update fails', () async {
      final original = Profile.normal(label: 'old label', url: 'bad-url');
      final edited = original.copyWith(
        label: 'new label',
        url: 'still-bad-url',
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => TestProfiles([original])),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(profilesProvider).getProfile(original.id),
        original,
      );

      await expectLater(
        container.read(profilesActionProvider.notifier).updateProfile(edited),
        throwsA(anything),
      );

      final profile = container.read(profilesProvider).getProfile(original.id);
      expect(profile?.label, edited.label);
      expect(profile?.url, edited.url);
    });

    group('a download held open while', () {
      late _HeldDownload held;

      Future<List<String>> profileFiles() async {
        final directory = Directory(await appPath.profilesPath);
        if (!await directory.exists()) {
          return const [];
        }
        return [
          await for (final entity in directory.list())
            entity.path.split(Platform.pathSeparator).last,
        ];
      }

      Future<String> saved() async => (await held.profile.file).readAsString();

      setUp(() async {
        held = await _holdDownload();
      });

      test('a request for a new source leaves the file to it', () async {
        final next = held.profile.copyWith(url: _newUrl);

        final stale = held.action.updateProfile(held.profile);
        await held.fetch.started.future;
        await held.action.updateProfile(next);
        expect(held.setupAction.applyCount, 1);

        held.fetch.answer('proxies: [] # old');
        await stale;

        final profile = held.container.read(profilesProvider).single;
        expect(profile.url, next.url);
        expect(await saved(), 'proxies: [] # new');
        expect(held.setupAction.applyCount, 1);
        expect(await profileFiles(), ['${held.profile.id}.yaml']);
      });

      test('a file saved by hand is kept with its settings', () async {
        final pending = held.action.updateProfile(held.profile);
        await held.fetch.started.future;
        final edited = await held.profile
            .copyWith(autoUpdate: false)
            .saveFile(
              Uint8List.fromList(utf8.encode('proxies: [] # by hand')),
              validate: (_, _) async => '',
            );
        held.container.read(profilesProvider.notifier).put(edited);

        held.fetch.answer('proxies: [] # stale');
        await pending;

        final profile = held.container.read(profilesProvider).single;
        expect(profile.autoUpdate, isFalse);
        expect(profile.lastUpdateDate, edited.lastUpdateDate);
        expect(profile.subscriptionInfo, isNull);
        expect(await saved(), 'proxies: [] # by hand');
        expect(held.setupAction.applyCount, 0);
      });

      test('a source edit retires it but a label edit does not', () async {
        final pending = held.action.updateProfile(held.profile);
        await held.fetch.started.future;
        held.container
            .read(profilesProvider.notifier)
            .put(
              held.profile.copyWith(
                label: 'Renamed',
                ageSecretKey: 'AGE-SECRET-KEY-1FAKE',
              ),
            );

        held.fetch.answer('proxies: [] # stale');
        await pending;

        final profile = held.container.read(profilesProvider).single;
        expect(profile.label, 'Renamed');
        expect(profile.lastUpdateDate, isNull);
        expect(await profileFiles(), isEmpty);
        expect(held.setupAction.applyCount, 0);
      });

      test('a label edit alone lets it land', () async {
        final pending = held.action.updateProfile(held.profile);
        await held.fetch.started.future;
        held.container
            .read(profilesProvider.notifier)
            .put(held.profile.copyWith(label: 'Renamed'));

        held.fetch.answer('proxies: [] # landed');
        await pending;

        final profile = held.container.read(profilesProvider).single;
        expect(profile.label, 'Renamed');
        expect(profile.lastUpdateDate, isNotNull);
        expect(await saved(), 'proxies: [] # landed');
        expect(held.setupAction.applyCount, 1);
      });

      test('its date read back to the second lets it land', () async {
        final pending = held.action.updateProfile(
          held.profile.copyWith(
            lastUpdateDate: DateTime(2026, 10, 27, 12, 0, 0, 345, 678),
          ),
        );
        await held.fetch.started.future;
        held.container
            .read(profilesProvider.notifier)
            .put(
              held.profile.copyWith(lastUpdateDate: DateTime(2026, 10, 27, 12)),
            );

        held.fetch.answer('proxies: [] # landed');
        await pending;

        expect(await saved(), 'proxies: [] # landed');
        expect(held.setupAction.applyCount, 1);
      });

      test('its deletion leaves no file behind', () async {
        held.container.listen(currentProfileIdProvider, (_, _) {});
        held.container.read(currentProfileIdProvider.notifier).value = null;

        final pending = held.action.updateProfile(held.profile);
        await held.fetch.started.future;
        await held.action.deleteProfile(held.profile.id);

        held.fetch.answer('proxies: [] # stale');
        await pending;

        expect(held.container.read(profilesProvider), isEmpty);
        expect(await profileFiles(), isEmpty);
        expect(held.setupAction.applyCount, 0);
      });
    });

    test('updates selection and inserts the first profile', () {
      final first = Profile.normal(label: 'First');
      final second = Profile.normal(label: 'Second');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => TestProfiles([first])),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(profilesActionProvider.notifier);

      action.updateCurrentSelectedMap('Group', 'Proxy');
      final updatedFirst = container.read(profilesProvider).single;
      expect(updatedFirst.selectedMap['Group'], 'Proxy');

      action.updateCurrentSelectedMap('Group', 'Proxy');
      expect(container.read(profilesProvider), hasLength(1));

      container.read(currentProfileIdProvider.notifier).value = null;
      action.putProfile(second);
      expect(container.read(currentProfileIdProvider), second.id);
      expect(container.read(profilesProvider), [updatedFirst, second]);
    });

    test(
      'skips profile updates that are disabled, fresh, or file-based',
      () async {
        final profiles = [
          Profile.normal(label: 'Disabled').copyWith(autoUpdate: false),
          Profile.normal(label: 'Fresh').copyWith(
            autoUpdate: true,
            lastUpdateDate: DateTime.now().add(const Duration(days: 1)),
          ),
          Profile.normal(label: 'File').copyWith(
            autoUpdate: true,
            lastUpdateDate: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => TestProfiles(profiles)),
          ],
        );
        addTearDown(container.dispose);
        final action = container.read(profilesActionProvider.notifier);

        await action.autoUpdateProfiles();
        await action.updateProfiles();

        expect(container.read(profilesProvider), profiles);
      },
    );
  });

  group('ScriptsAction', () {
    ProviderContainer scriptsContainer(
      Profile profile,
      ApplyRecordingSetupAction setupAction,
    ) {
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          scriptsProvider.overrideWith(_MemoryScripts.new),
          setupActionProvider.overrideWith(() => setupAction),
        ],
      );
      addTearDown(container.dispose);
      container.listen(scriptsProvider, (_, _) {});
      return container;
    }

    Script script(int id, {String? url}) => Script(
      id: id,
      label: 'Script $id',
      lastUpdateTime: DateTime(2026),
      url: url,
    );

    test('putScript re-applies only a current profile running that script', () {
      final profile = Profile.normal().copyWith(
        extendType: ExtendType.script,
        scriptId: 1,
      );
      final setupAction = ApplyRecordingSetupAction();
      final container = scriptsContainer(profile, setupAction);
      final action = container.read(scriptsActionProvider.notifier);

      action.putScript(script(2));
      expect(setupAction.applyCount, 0);

      action.putScript(script(1));
      expect(setupAction.applyCount, 1);
      expect(container.read(scriptsProvider).value?.map((item) => item.id), [
        2,
        1,
      ]);

      container
          .read(profilesProvider.notifier)
          .put(profile.copyWith(extendType: ExtendType.standard));
      action.putScript(script(1));
      expect(setupAction.applyCount, 1);
    });

    test(
      'updateScript releases the updating key when the download fails',
      () async {
        final profile = Profile.normal().copyWith(
          extendType: ExtendType.script,
          scriptId: 1,
        );
        final setupAction = ApplyRecordingSetupAction();
        final container = scriptsContainer(profile, setupAction);
        final remote = script(1, url: 'bad-url');

        await expectLater(
          container.read(scriptsActionProvider.notifier).updateScript(remote),
          throwsA(anything),
        );

        expect(container.read(isUpdatingProvider(remote.updatingKey)), isFalse);
        expect(container.read(scriptsProvider).value, isEmpty);
        expect(setupAction.applyCount, 0);
      },
    );

    Future<
      ({
        ProviderContainer container,
        ScriptsAction action,
        Completer<String> body,
        Script remote,
      })
    >
    heldScriptUpdate() async {
      final root = await Directory.systemTemp.createTemp('scripts_action_');
      addTearDown(() => root.delete(recursive: true));
      await useAppPaths(root);
      final container = scriptsContainer(
        Profile.normal(),
        ApplyRecordingSetupAction(),
      );
      final action = container.read(scriptsActionProvider.notifier);
      final body = Completer<String>();
      action.download = (_) => body.future;
      final remote = await script(
        1,
        url: 'https://example.com/s.js',
      ).save('v1');
      action.putScript(remote);
      return (container: container, action: action, body: body, remote: remote);
    }

    test(
      'a finished download writes the body and keeps the saved label',
      () async {
        final held = await heldScriptUpdate();
        final update = held.action.updateScript(held.remote);
        held.body.complete('v2');
        await update;

        expect(await held.remote.content, 'v2');
        expect(
          held.container.read(scriptsProvider).value?.single.label,
          'Script 1',
        );
        expect(
          File('${await held.remote.path}.download').existsSync(),
          isFalse,
        );
      },
    );

    test('a save made during the download outlives it', () async {
      final held = await heldScriptUpdate();
      final update = held.action.updateScript(held.remote);
      held.action.putScript(
        await held.remote.copyWith(label: 'Edited').save('edited'),
      );
      held.body.complete('downloaded');
      await update;

      expect(await held.remote.content, 'edited');
      expect(
        held.container.read(scriptsProvider).value?.single.label,
        'Edited',
      );
      expect(
        held.container.read(isUpdatingProvider(held.remote.updatingKey)),
        isFalse,
      );
    });

    test('a script deleted during the download stays deleted', () async {
      final held = await heldScriptUpdate();
      final update = held.action.updateScript(held.remote);
      held.container.read(scriptsProvider.notifier).del(held.remote.id);
      held.body.complete('downloaded');
      await update;

      expect(held.container.read(scriptsProvider).value, isEmpty);
    });
  });

  group('GeoResourceAction', () {
    test('GeoResource has correct updatingKey', () {
      expect(GeoResource.MMDB.updatingKey, 'geo_resource_MMDB');
      expect(GeoResource.ASN.updatingKey, 'geo_resource_ASN');
      expect(GeoResource.GEOIP.updatingKey, 'geo_resource_GEOIP');
      expect(GeoResource.GEOSITE.updatingKey, 'geo_resource_GEOSITE');
    });

    test('IsUpdating provider works with geo resource key', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final key = GeoResource.MMDB.updatingKey;
      expect(container.read(isUpdatingProvider(key)), false);

      final operation = container
          .read(updatingKeysProvider.notifier)
          .start(key);
      expect(container.read(isUpdatingProvider(key)), true);

      container.read(updatingKeysProvider.notifier).stop(key, operation);
      expect(container.read(isUpdatingProvider(key)), false);
    });

    test('forwards a manual resource update to Core', () async {
      final core = _MockCoreHandlerInterface();
      when(() => core.updateGeoData('MMDB')).thenAnswer((_) async => '');
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(geoResourceActionProvider.notifier);

      await action.updateGeoResource(GeoResource.MMDB);

      verify(() => core.updateGeoData('MMDB')).called(1);
    });

    test('propagates a failed manual Core request', () async {
      final core = _MockCoreHandlerInterface();
      when(
        () => core.updateGeoData('MMDB'),
      ).thenThrow(StateError('disconnected'));
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(geoResourceActionProvider.notifier);

      await expectLater(
        action.updateGeoResource(GeoResource.MMDB),
        throwsStateError,
      );
      verify(() => core.updateGeoData('MMDB')).called(1);
    });

    test('updates valid resource URLs and rejects malformed URLs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final action = container.read(geoResourceActionProvider.notifier);

      expect(
        () => action.updateGeoResourceUrl(GeoResource.MMDB, 'not-a-url'),
        throwsA(isA<ArgumentError>()),
      );

      const url = 'https://example.com/Country.mmdb';
      action.updateGeoResourceUrl(GeoResource.MMDB, url);
      expect(
        container.read(patchClashConfigProvider).geoXUrl[GeoResource.MMDB],
        url,
      );
    });
  });

  group('CoreAction', () {
    test('an embedded core is stopped, shut down and started again', () async {
      final core = _MockCoreHandlerInterface();
      when(() => core.shutdown()).thenAnswer((_) async => true);
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          coreActionProvider.overrideWith(
            () => _TestCoreAction()..embedded = true,
          ),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      container.read(runTimeProvider.notifier).value = 0;
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _TestSetupAction;

      await coreAction.restartCore();

      verify(() => core.shutdown()).called(1);
      expect(coreAction.lifecycleRestartCount, 1);
      expect(setupAction.runningCalls, [(false, false), (true, true)]);
      expect(setupAction.applyProfileCount, 0);
    });

    test(
      'a stop made while an embedded core shuts down keeps it off',
      () async {
        final core = _MockCoreHandlerInterface();
        final shutdown = Completer<bool>();
        when(() => core.shutdown()).thenAnswer((_) => shutdown.future);
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
            coreActionProvider.overrideWith(
              () => _TestCoreAction()..embedded = true,
            ),
            setupActionProvider.overrideWith(_RestartSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _RestartSetupAction;
        await setupAction.setRunning(true);

        final restart = coreAction.restartCore();
        await Future<void>.delayed(Duration.zero);
        await setupAction.setRunning(false);
        shutdown.complete(true);
        await restart;

        expect(container.read(isStartProvider), isFalse);
        expect(setupAction.transitions.last, isFalse);
        expect(setupAction.applyProfileCount, 1);
      },
    );

    test(
      'clears the DNS cache on a network change only while connected',
      () async {
        final core = _MockCoreHandlerInterface();
        when(core.clearDnsCache).thenAnswer((_) async => true);
        final container = ProviderContainer(
          overrides: [
            coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          ],
        );
        addTearDown(container.dispose);
        final action = container.read(coreActionProvider.notifier);

        await action.clearDnsCacheOnNetworkChange();
        verifyNever(core.clearDnsCache);

        container.read(coreStatusProvider.notifier).value =
            CoreStatus.connected;
        await action.clearDnsCacheOnNetworkChange();
        verify(core.clearDnsCache).called(1);

        when(core.clearDnsCache).thenThrow(StateError('disconnected'));
        await expectLater(action.clearDnsCacheOnNetworkChange(), completes);
      },
    );

    test('applies the profile after restarting a stopped core', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _TestSetupAction;

      await coreAction.restartCore();

      expect(coreAction.lifecycleRestartCount, 1);
      expect(setupAction.setRunningCount, 0);
      expect(setupAction.applyProfileCount, 1);
    });

    test(
      'restores the started state after restarting a running core',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        container.read(runTimeProvider.notifier).value = 0;
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;

        await coreAction.restartCore();

        expect(coreAction.lifecycleRestartCount, 1);
        expect(setupAction.setRunningCount, 1);
        expect(setupAction.applyProfileCount, 0);
      },
    );

    test('a stop confirmed mid-restart keeps the proxy off', () async {
      final container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          commonActionProvider.overrideWith(_RaceCommonAction.new),
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_RestartSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _RestartSetupAction;
      await setupAction.setRunning(true);
      final restartCompleter = Completer<CoreLifecycleResult>();
      coreAction.restartCompleter = restartCompleter;

      final restart = coreAction.restartCore();
      await Future<void>.delayed(Duration.zero);
      await setupAction.setRunning(false);
      expect(container.read(isStartProvider), isFalse);

      restartCompleter.complete(_restartResult);
      await restart;

      expect(setupAction.transitions, [true, false]);
      expect(container.read(isStartProvider), isFalse);
      expect(setupAction.applyProfileCount, 1);
    });

    test('a stop rolled back mid-restart keeps the proxy off', () async {
      final container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          commonActionProvider.overrideWith(_RaceCommonAction.new),
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_RestartSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _RestartSetupAction;
      await setupAction.setRunning(true);
      final restartCompleter = Completer<CoreLifecycleResult>();
      coreAction.restartCompleter = restartCompleter;

      final restart = coreAction.restartCore();
      await Future<void>.delayed(Duration.zero);
      setupAction.coreRunningError = const CoreMethodException(
        code: 'transport_disconnected',
        message: 'Core transport disconnected',
      );
      await expectLater(
        setupAction.setRunning(false),
        throwsA(isA<CoreMethodException>()),
      );
      expect(container.read(isStartProvider), isTrue);
      setupAction.coreRunningError = null;

      restartCompleter.complete(_restartResult);
      await restart;

      expect(setupAction.transitions, [true, false, false]);
      expect(container.read(isStartProvider), isFalse);
      expect(setupAction.applyProfileCount, 1);
    });

    test(
      'a rejected setup while running reports restartCore as unsuccessful',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        container.read(runTimeProvider.notifier).value = 0;
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;
        setupAction.setRunningResult = false;

        final applied = await coreAction.restartCore();

        expect(applied, isFalse);
        expect(setupAction.setRunningCount, 1);
      },
    );

    test(
      'coalesces concurrent restart requests into one lifecycle restart',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;
        final restartCompleter = Completer<CoreLifecycleResult>();
        coreAction.restartCompleter = restartCompleter;

        final first = coreAction.restartCore();
        final second = coreAction.restartCore();
        await Future<void>.delayed(Duration.zero);

        expect(coreAction.lifecycleRestartCount, 1);
        restartCompleter.complete(_restartResult);
        await Future.wait([first, second]);

        expect(setupAction.applyProfileCount, 1);
      },
    );

    test('reapplies the latest request without restarting twice', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _TestSetupAction;
      final restartCompleter = Completer<CoreLifecycleResult>();
      final firstApplyStarted = Completer<void>();
      final firstApplyCompleter = Completer<void>();
      coreAction.restartCompleter = restartCompleter;
      setupAction.firstApplyStarted = firstApplyStarted;
      setupAction.firstApplyCompleter = firstApplyCompleter;

      final first = coreAction.restartCore();
      await Future<void>.delayed(Duration.zero);
      restartCompleter.complete(_restartResult);
      await firstApplyStarted.future;

      final second = coreAction.restartCore();
      firstApplyCompleter.complete();
      await Future.wait([first, second]);

      expect(coreAction.lifecycleRestartCount, 1);
      expect(setupAction.applyProfileCount, 2);
    });

    test('surfaces a failed restart to its caller as a rejection', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final restartCompleter = Completer<CoreLifecycleResult>();
      coreAction.restartCompleter = restartCompleter;

      final restart = coreAction.restartCore();
      restartCompleter.completeError(StateError('core is gone'));

      await expectLater(restart, throwsA(isA<StateError>()));
      expect(container.read(coreStatusProvider), CoreStatus.disconnected);

      // The failed operation must not latch: a later restart still runs.
      coreAction.restartCompleter = null;
      await coreAction.restartCore();
      expect(coreAction.lifecycleRestartCount, 2);
      expect(container.read(coreStatusProvider), CoreStatus.connected);
    });

    test(
      'startCore leaves status and initCore to the superseding operation',
      () async {
        final container = ProviderContainer(
          overrides: [coreActionProvider.overrideWith(_TestCoreAction.new)],
        );
        addTearDown(container.dispose);
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        coreAction.startResult = const CoreLifecycleResult(
          revision: 1,
          outcome: CoreLifecycleOutcome.superseded,
        );

        await coreAction.startCore();

        expect(coreAction.initCoreCount, 0);
        expect(container.read(coreStatusProvider), CoreStatus.connecting);
      },
    );

    test('startCore treats a coalesced outcome as applied', () async {
      final container = ProviderContainer(
        overrides: [coreActionProvider.overrideWith(_TestCoreAction.new)],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      coreAction.startResult = const CoreLifecycleResult(
        revision: 1,
        outcome: CoreLifecycleOutcome.coalesced,
      );

      await coreAction.startCore();

      expect(coreAction.initCoreCount, 1);
      expect(container.read(coreStatusProvider), CoreStatus.connected);
    });

    test(
      'restartCore leaves status and initCore to the superseding operation',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;
        coreAction.restartCompleter = Completer<CoreLifecycleResult>()
          ..complete(
            const CoreLifecycleResult(
              revision: 1,
              outcome: CoreLifecycleOutcome.superseded,
            ),
          );

        final applied = await coreAction.restartCore();

        expect(applied, isFalse);
        expect(coreAction.initCoreCount, 0);
        expect(container.read(coreStatusProvider), CoreStatus.connecting);
        expect(setupAction.setRunningCount, 0);
        expect(setupAction.applyProfileCount, 0);
      },
    );

    test('restartCore treats a coalesced outcome as applied', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      coreAction.restartCompleter = Completer<CoreLifecycleResult>()
        ..complete(
          const CoreLifecycleResult(
            revision: 1,
            outcome: CoreLifecycleOutcome.coalesced,
          ),
        );

      await coreAction.restartCore();

      expect(coreAction.initCoreCount, 1);
      expect(container.read(coreStatusProvider), CoreStatus.connected);
    });

    group('after a crash', () {
      late List<String> printed;
      late ProviderContainer container;
      late _TestCoreAction coreAction;
      late _TestSetupAction setupAction;

      setUp(() {
        printed = [];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        addTearDown(() => debugPrint = original);
        container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        container.read(runTimeProvider.notifier).value = 0;
        coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;
      });

      Future<void> crashAfter(Duration uptime, String reason) {
        coreAction.now = coreAction.now.add(uptime);
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        return coreAction.restartAfterCrash(reason);
      }

      test('answers a crash during the first init and keeps the status the '
          'restart set', () async {
        final init = Completer<void>();
        coreAction.initCompleter = init;
        final start = coreAction.startCore();
        await pumpEventQueue();
        expect(container.read(coreStatusProvider), CoreStatus.connected);

        coreAction.initCompleter = null;
        await crashAfter(Duration.zero, 'boom');
        init.completeError(StateError('the Core is gone'));
        await start;

        expect(coreAction.lifecycleRestartCount, 1);
        expect(container.read(coreStatusProvider), CoreStatus.connected);
      });

      test('restarts the Core with the run it had', () async {
        await crashAfter(Duration.zero, 'boom');

        expect(coreAction.lifecycleRestartCount, 1);
        expect(setupAction.runningCalls, [(true, true)]);
        expect(container.read(coreStatusProvider), CoreStatus.connected);
        expect(printed, contains(contains('boom')));
      });

      test('leaves a Core that fell within 5 s of two restarts in a row '
          'down and logs why', () async {
        await crashAfter(Duration.zero, 'first');
        await crashAfter(const Duration(seconds: 4), 'second');
        await crashAfter(const Duration(seconds: 4), 'third');

        expect(coreAction.lifecycleRestartCount, 2);
        expect(container.read(coreStatusProvider), CoreStatus.disconnected);
        expect(printed.last, allOf(contains('5s'), contains('third')));
      });

      test('restarts a Core that outlived the window again', () async {
        await crashAfter(Duration.zero, 'first');
        await crashAfter(const Duration(seconds: 4), 'second');
        await crashAfter(const Duration(seconds: 6), 'third');

        expect(coreAction.lifecycleRestartCount, 3);
        expect(container.read(coreStatusProvider), CoreStatus.connected);
      });

      test(
        'answers a crash that came while the restart was under way',
        () async {
          final init = Completer<void>();
          coreAction.initCompleter = init;
          final first = crashAfter(Duration.zero, 'first');
          await pumpEventQueue();
          expect(container.read(coreStatusProvider), CoreStatus.connected);

          coreAction.initCompleter = null;
          await crashAfter(const Duration(seconds: 1), 'second');
          init.complete();
          await first;

          expect(coreAction.lifecycleRestartCount, 2);
          expect(container.read(coreStatusProvider), CoreStatus.connected);
        },
      );

      test('relaunches a Core that fell during a restart already under '
          'way', () async {
        final init = Completer<void>();
        coreAction.initCompleter = init;
        final userRestart = coreAction.restartCore();
        await pumpEventQueue();

        coreAction.initCompleter = null;
        final recovery = crashAfter(const Duration(seconds: 1), 'boom');
        init.complete();
        await userRestart;
        await recovery;

        expect(coreAction.lifecycleRestartCount, 2);
        expect(container.read(coreStatusProvider), CoreStatus.connected);
      });

      (ProviderContainer, _TestCoreAction, _RestartSetupAction) realRun() {
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_RestartSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        return (
          container,
          container.read(coreActionProvider.notifier) as _TestCoreAction,
          container.read(setupActionProvider.notifier) as _RestartSetupAction,
        );
      }

      test('restores the run a crash during the restart rolled back', () async {
        final (container, coreAction, setupAction) = realRun();
        await setupAction.setRunning(true);
        setupAction.crashOnNextApply = () {
          container.read(coreStatusProvider.notifier).value =
              CoreStatus.disconnected;
          unawaited(coreAction.restartAfterCrash('during restore'));
        };

        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        await coreAction.restartAfterCrash('boom');

        expect(coreAction.lifecycleRestartCount, 2);
        expect(setupAction.transitions, [true, true, false, true]);
        expect(container.read(isStartProvider), isTrue);
      });

      test('keeps a stop made while the Core was being restarted', () async {
        final (container, coreAction, setupAction) = realRun();
        await setupAction.setRunning(true);
        final init = Completer<void>();
        coreAction.initCompleter = init;
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        final recovery = coreAction.restartAfterCrash('boom');
        await pumpEventQueue();

        await setupAction.setRunning(false);
        coreAction.initCompleter = null;
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        unawaited(coreAction.restartAfterCrash('second'));
        init.complete();
        await recovery;

        expect(coreAction.lifecycleRestartCount, 2);
        expect(container.read(isStartProvider), isFalse);
      });

      test('keeps a stop that the crash itself rolled back', () async {
        final (container, coreAction, setupAction) = realRun();
        await setupAction.setRunning(true);
        final init = Completer<void>();
        coreAction.initCompleter = init;
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        final recovery = coreAction.restartAfterCrash('boom');
        await pumpEventQueue();

        setupAction.coreRunningError = Exception('Core is gone');
        await expectLater(setupAction.setRunning(false), throwsException);
        expect(container.read(isStartProvider), isTrue);
        setupAction.coreRunningError = null;
        coreAction.initCompleter = null;
        container.read(coreStatusProvider.notifier).value =
            CoreStatus.disconnected;
        unawaited(coreAction.restartAfterCrash('second'));
        init.completeError(StateError('Core is gone'));
        await recovery;

        expect(coreAction.lifecycleRestartCount, 2);
        expect(container.read(isStartProvider), isFalse);
      });

      test('a crash during a restart counts however long it took', () async {
        var slowCrashes = 0;
        coreAction.onInit = () {
          if (slowCrashes == 2) {
            return;
          }
          slowCrashes++;
          coreAction.now = coreAction.now.add(const Duration(seconds: 10));
          container.read(coreStatusProvider.notifier).value =
              CoreStatus.disconnected;
          unawaited(coreAction.restartAfterCrash('slow $slowCrashes'));
        };

        await crashAfter(Duration.zero, 'boom');

        expect(coreAction.lifecycleRestartCount, 2);
        expect(printed.last, contains('slow 2'));
      });

      test('stops once the app exit has closed the Core', () async {
        coreAction.restartError = const DesktopCoreFailure(
          code: 'lifecycle_closed',
          phase: DesktopCorePhase.closed,
          revision: 3,
        );

        await crashAfter(Duration.zero, 'boom');

        expect(coreAction.lifecycleRestartCount, 1);
        expect(printed, isNot(contains(contains('leaving it down'))));
      });

      test('a restart that fails counts as one that fell', () async {
        coreAction.restartError = StateError('no core binary');

        await crashAfter(Duration.zero, 'boom');

        expect(coreAction.lifecycleRestartCount, 2);
        expect(container.read(coreStatusProvider), CoreStatus.disconnected);
        expect(printed.last, contains('no core binary'));
      });
    });
  });

  group('SetupAction', () {
    group('rapid status changes', () {
      test('updates runtime and traffic while core start is pending', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        final commonAction =
            container.read(commonActionProvider.notifier) as _RaceCommonAction;
        action.startCompleter = startCompleter;

        final startFuture = action.setRunning(true);
        final initialRunTime = container.read(runTimeProvider)!;
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(container.read(runTimeProvider), greaterThan(initialRunTime));
        expect(commonAction.updateTrafficCount, greaterThanOrEqualTo(2));

        startCompleter.complete(true);
        await startFuture;

        expect(action.transitions, [true]);
        await action.setRunning(false);
      });

      test('serializes listener changes while latest start owns UI', () async {
        final stopCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        await action.setRunning(true);
        action.transitions.clear();
        action.applyProfileDebounceCount = 0;
        action.stopCompleter = stopCompleter;

        final stopFuture = action.setRunning(false);
        await Future<void>.delayed(Duration.zero);
        expect(action.transitions, [false]);

        final startFuture = action.setRunning(true);

        expect(container.read(runTimeProvider), isNotNull);

        stopCompleter.complete(true);
        await Future.wait([stopFuture, startFuture]);

        expect(action.transitions, [false, true]);
        expect(container.read(runTimeProvider), isNotNull);
        expect(container.read(isStartProvider), isTrue);
        expect(action.applyProfileDebounceCount, 1);
        expect(action.resetCoreTrafficCount, 0);

        await action.setRunning(false);
      });

      test('newer stop prevents stale start continuation', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
            // Bypassing private addresses computes the routes in an isolate,
            // which outlasts the zero delay below.
            networkSettingProvider.overrideWithBuild(
              (_, _) => const NetworkProps(bypassPrivateRoute: false),
            ),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        action.startCompleter = startCompleter;

        final startFuture = action.setRunning(true);
        await Future<void>.delayed(Duration.zero);
        expect(action.transitions, [true]);

        final stopFuture = action.setRunning(false);
        expect(container.read(runTimeProvider), isNull);

        startCompleter.complete(true);
        await Future.wait([startFuture, stopFuture]);

        expect(action.transitions, [true, false]);
        expect(container.read(runTimeProvider), isNull);
        expect(container.read(isStartProvider), isFalse);
        expect(action.applyProfileDebounceCount, 0);
        expect(action.resetCoreTrafficCount, 1);
      });

      test('skips an intermediate stop when a newer start is queued', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        action.startCompleter = startCompleter;

        final firstStart = action.setRunning(true);
        await Future<void>.delayed(Duration.zero);
        final stop = action.setRunning(false);
        final latestStart = action.setRunning(true);

        startCompleter.complete(true);
        await Future.wait([firstStart, stop, latestStart]);

        expect(action.transitions, [true, true]);
        expect(container.read(isStartProvider), isTrue);
        expect(action.applyProfileDebounceCount, 1);
        expect(action.resetCoreTrafficCount, 0);

        await action.setRunning(false);
      });

      test('stale initialization cannot start after a newer stop', () async {
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_InitializingSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier)
                as _InitializingSetupAction;

        final start = action.setRunning(true, initialize: true);
        final stop = action.setRunning(false);
        await stop;

        expect(action.transitions, [false]);
        expect(container.read(isStartProvider), isFalse);

        action.continueInitialization();
        await start;

        expect(action.transitions, [false]);
        expect(container.read(isStartProvider), isFalse);
      });

      test(
        'keeps suspended startup local until the listener resumes',
        () async {
          final container = ProviderContainer(
            overrides: [
              initProvider.overrideWithBuild((_, _) => true),
              suspendProvider.overrideWithValue(true),
              commonActionProvider.overrideWith(_RaceCommonAction.new),
              setupActionProvider.overrideWith(_RaceSetupAction.new),
            ],
          );
          addTearDown(container.dispose);
          final action =
              container.read(setupActionProvider.notifier) as _RaceSetupAction;

          await action.setRunning(true);

          expect(action.transitions, isEmpty);
          expect(container.read(isStartProvider), isTrue);
          expect(action.applyProfileDebounceCount, 1);

          await action.setRunning(false);
          expect(action.transitions, [false]);
        },
      );
    });

    test(
      'restarts core after newly granting admin during config update',
      () async {
        late _AuthorizationSetupAction setupAction;
        late _RestartRecordingCoreAction coreAction;
        final container = ProviderContainer(
          overrides: [
            setupActionProvider.overrideWith(() {
              setupAction = _AuthorizationSetupAction([AuthorizeCode.success]);
              return setupAction;
            }),
            coreActionProvider.overrideWith(() {
              coreAction = _RestartRecordingCoreAction();
              return coreAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        container.read(setupActionProvider);
        container.read(coreActionProvider);

        await setupAction.updateConfig();

        expect(setupAction.authorizationRequestCount, 1);
        expect(
          container.read(authorizedTunEnableProvider),
          TunAuthorizationState.authorized,
        );
        expect(coreAction.restartCount, 1);
      },
    );

    test(
      'a TUN the Core could not open relaunches it on the next enable, once',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        await AppLocalizations.load(const Locale('en'));
        late _AuthorizationSetupAction setupAction;
        late _RestartRecordingCoreAction coreAction;
        final container = ProviderContainer(
          overrides: [
            setupActionProvider.overrideWith(() {
              setupAction = _AuthorizationSetupAction([
                AuthorizeCode.none,
                AuthorizeCode.none,
              ]);
              return setupAction;
            }),
            coreActionProvider.overrideWith(() {
              coreAction = _RestartRecordingCoreAction();
              return coreAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        final patch = container.read(patchClashConfigProvider.notifier);
        patch.update((state) => state.copyWith.tun(enable: true));
        container.read(setupActionProvider);
        container.read(coreActionProvider);

        setupAction.tunStillFailed = true;
        await setupAction.tunFailed();
        setupAction.tunStillFailed = false;
        patch.update((state) => state.copyWith.tun(enable: true));
        await setupAction.updateConfig();

        expect(coreAction.restartCount, 1);
        container.read(authorizedTunEnableProvider.notifier).value =
            TunAuthorizationState.none;
        expect(await setupAction.requestAdmin(true), isTrue);
        expect(setupAction.authorizationRequestCount, 2);
      },
    );

    test(
      'a config Core rejects on the handoff path reports failure, not success',
      () async {
        late _AuthorizationSetupAction setupAction;
        late _RestartRecordingCoreAction coreAction;
        final container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(null),
            setupActionProvider.overrideWith(() {
              setupAction = _AuthorizationSetupAction([AuthorizeCode.success]);
              return setupAction;
            }),
            coreActionProvider.overrideWith(() {
              coreAction = _RestartRecordingCoreAction()..restartResult = false;
              return coreAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        container.read(setupActionProvider);
        container.read(coreActionProvider);

        final succeeded = await setupAction.applyProfile(force: true);

        expect(coreAction.restartCount, 1);
        expect(succeeded, isFalse);
      },
    );

    test(
      'a restart whose restore is newly authorized launches the Core again',
      () async {
        final container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(null),
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(
              () => _HandoffSetupAction([AuthorizeCode.success]),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _HandoffSetupAction;
        final statuses = <CoreStatus>[];
        container.listen(
          coreStatusProvider,
          (_, next) => statuses.add(next),
          fireImmediately: true,
        );

        final restarted = await coreAction.restartCore().timeout(
          const Duration(seconds: 5),
        );

        expect(restarted, isTrue);
        expect(setupAction.authorizationRequestCount, 1);
        expect(coreAction.lifecycleRestartCount, 2);
        expect(setupAction.applyCount, 2);
        expect(statuses.skipWhile((status) => status != CoreStatus.connected), [
          CoreStatus.connected,
          CoreStatus.connecting,
          CoreStatus.connected,
        ]);
      },
    );

    test(
      'a relaunch that fails after a new authorization reopens it',
      () async {
        final container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(null),
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(
              () => _HandoffSetupAction([AuthorizeCode.success]),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        container.read(setupActionProvider.notifier);
        coreAction.onInit = () {
          coreAction.restartError = _restartFailure;
        };

        await expectLater(
          coreAction.restartCore().timeout(const Duration(seconds: 5)),
          throwsA(same(_restartFailure)),
        );
        await pumpEventQueue();

        expect(coreAction.lifecycleRestartCount, 2);
        expect(
          container.read(authorizedTunEnableProvider),
          TunAuthorizationState.none,
        );
        expect(container.read(coreStatusProvider), CoreStatus.disconnected);
      },
    );

    test('reopens authorization and propagates a failed restart', () async {
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(null),
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([AuthorizeCode.success]);
            return setupAction;
          }),
          coreActionProvider.overrideWith(_FailingRestartCoreAction.new),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      container.read(setupActionProvider);
      container.read(coreActionProvider);

      await expectLater(
        setupAction.applyProfile(force: true),
        throwsA(same(_restartFailure)),
      );

      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
    });

    test('asks once while an authorization request is pending', () async {
      final pending = Completer<AuthorizeCode>();
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([], pending: pending);
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(setupActionProvider);

      final first = setupAction.requestAdmin(true);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.unauthorized,
      );

      expect(await setupAction.requestAdmin(true), isTrue);
      expect(setupAction.authorizationRequestCount, 1);

      pending.complete(AuthorizeCode.success);
      expect(await first, isFalse);
    });

    test('a failed authorization leaves tun and system DNS off', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await AppLocalizations.load(const Locale('en'));
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([AuthorizeCode.error]);
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      container.read(setupActionProvider);

      expect(await setupAction.requestAdmin(true), isTrue);

      expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(container.read(shouldPatchSystemDnsProvider), isFalse);
      expect(
        await setupAction.requestAdmin(
          container.read(patchClashConfigProvider).tun.enable,
        ),
        isTrue,
      );
      expect(setupAction.authorizationRequestCount, 1);
    });
  });
}

class _TestCoreAction extends CoreAction {
  bool embedded = false;
  int lifecycleRestartCount = 0;

  @override
  bool get coreIsEmbedded => embedded;
  int initCoreCount = 0;
  Completer<void>? initCompleter;
  void Function()? onInit;
  Completer<CoreLifecycleResult>? restartCompleter;
  Completer<CoreLifecycleResult>? startCompleter;
  CoreLifecycleResult startResult = _restartResult;
  Object? restartError;
  DateTime now = DateTime(2026, 11, 3);

  @override
  DateTime currentTime() => now;

  @override
  Future<void> initCore() async {
    initCoreCount++;
    onInit?.call();
    await initCompleter?.future;
  }

  @override
  Future<CoreLifecycleResult> startLifecycle() {
    return startCompleter?.future ?? Future.value(startResult);
  }

  @override
  Future<CoreLifecycleResult> restartLifecycle() {
    lifecycleRestartCount++;
    final error = restartError;
    if (error != null) {
      return Future.error(error);
    }
    return restartCompleter?.future ?? Future.value(_restartResult);
  }
}

class _MemoryScripts extends Scripts {
  @override
  Stream<List<Script>> build() => Stream.value(const []);

  @override
  void put(Script script) {
    state = AsyncData([...value.where((item) => item.id != script.id), script]);
  }

  @override
  void del(int id) {
    state = AsyncData([...value.where((item) => item.id != id)]);
  }
}

class _TestSetupAction extends SetupAction {
  int setRunningCount = 0;
  final List<(bool, bool)> runningCalls = [];
  int applyProfileCount = 0;
  bool setRunningResult = true;
  Completer<void>? firstApplyStarted;
  Completer<void>? firstApplyCompleter;
  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    setRunningCount++;
    runningCalls.add((running, initialize));
    if (!running) {
      ref.read(runTimeProvider.notifier).value = null;
    }
    return setRunningResult;
  }

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyProfileCount++;
    if (applyProfileCount == 1) {
      firstApplyStarted?.complete();
      await firstApplyCompleter?.future;
    }
    return true;
  }
}

const _restartResult = CoreLifecycleResult(
  revision: 1,
  outcome: CoreLifecycleOutcome.applied,
);

class _RestartRecordingCoreAction extends CoreAction {
  int restartCount = 0;
  bool restartResult = true;

  @override
  Future<bool> restartCore({bool? running}) async {
    restartCount++;
    return restartResult;
  }
}

class _FailingRestartCoreAction extends CoreAction {
  @override
  Future<bool> restartCore({bool? running}) async {
    throw _restartFailure;
  }
}

final _restartFailure = Exception('restart failed');

class _AuthorizationSetupAction extends SetupAction {
  final List<AuthorizeCode> authorizationResults;
  final Completer<AuthorizeCode>? pending;
  int authorizationRequestCount = 0;

  _AuthorizationSetupAction(this.authorizationResults, {this.pending});

  bool tunStillFailed = false;

  @override
  Future<bool> confirmTunFailed() async => tunStillFailed;

  @override
  Future<AuthorizeCode> authorizeCore() async {
    final index = authorizationRequestCount++;
    final pending = this.pending;
    if (pending != null) {
      return pending.future;
    }
    return authorizationResults[index];
  }
}

/// Only its first apply runs for real: the one that meets the authorization.
class _HandoffSetupAction extends _AuthorizationSetupAction {
  _HandoffSetupAction(super.authorizationResults);

  int applyCount = 0;

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) {
    applyCount++;
    if (applyCount > 1) {
      return Future.value(true);
    }
    return super.applyProfile(
      silence: silence,
      force: force,
      preloadInvoke: preloadInvoke,
    );
  }
}

class _RaceSetupAction extends SetupAction {
  int applyProfileDebounceCount = 0;
  int resetCoreTrafficCount = 0;
  final transitions = <bool>[];
  Completer<bool>? startCompleter;
  Completer<bool>? stopCompleter;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    applyProfileDebounceCount++;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return running
        ? await startCompleter?.future ?? true
        : await stopCompleter?.future ?? true;
  }

  @override
  void resetCoreTraffic() {
    resetCoreTrafficCount++;
  }
}

class _InitializingSetupAction extends _RaceSetupAction {
  final _initializationCompleter = Completer<void>();

  void continueInitialization() {
    _initializationCompleter.complete();
  }

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    await _initializationCompleter.future;
    await preloadInvoke?.call();
    return true;
  }
}

class _RaceCommonAction extends CommonAction {
  int updateTrafficCount = 0;

  @override
  Future<void> updateTraffic() async {
    updateTrafficCount++;
  }
}

class _RestartSetupAction extends SetupAction {
  final transitions = <bool>[];
  int applyProfileCount = 0;
  Exception? coreRunningError;
  void Function()? crashOnNextApply;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {}

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    final error = coreRunningError;
    if (error != null) {
      throw error;
    }
    return true;
  }

  @override
  void resetCoreTraffic() {}

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyProfileCount++;
    await preloadInvoke?.call();
    final crash = crashOnNextApply;
    crashOnNextApply = null;
    crash?.call();
    return crash == null;
  }
}
