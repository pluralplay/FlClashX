import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';
import '../helpers/setup_actions.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

/// Answers each download from [answers] in order; an exception is thrown.
class _ScriptedProfilesAction extends ProfilesAction {
  final List<Object> answers;
  final void Function()? onWait;
  Completer<void>? gate;
  int downloads = 0;
  final waits = <Duration>[];

  _ScriptedProfilesAction(this.answers, {this.onWait});

  @override
  Future<Profile> download(
    Profile profile, {
    bool Function()? isCurrent,
  }) async {
    await gate?.future;
    final answer = answers[downloads++];
    if (answer is Exception) {
      throw answer;
    }
    return profile.copyWith(lastUpdateDate: DateTime.now());
  }

  @override
  Future<void> retryWait(Duration delay) async {
    waits.add(delay);
    onWait?.call();
  }
}

DioException _unreachable() => DioException.connectionError(
  requestOptions: RequestOptions(path: 'https://sub.example.com'),
  reason: 'Failed host lookup',
  error: const SocketException('Failed host lookup: sub.example.com'),
);

DioException _status(int statusCode) => DioException.badResponse(
  statusCode: statusCode,
  requestOptions: RequestOptions(path: 'https://sub.example.com'),
  response: Response(
    requestOptions: RequestOptions(path: 'https://sub.example.com'),
    statusCode: statusCode,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late _MockCoreHandlerInterface core;
  late ProviderContainer container;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-profiles-action-');
    await useAppPaths(home);
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    core = _MockCoreHandlerInterface();
    when(() => core.validateConfig(any())).thenAnswer((_) async => '');
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
  });

  void decodesTo(String link, List<Map<String, dynamic>> proxies) {
    when(
      () => core.decodeShareLinks([link]),
    ).thenAnswer((_) async => [proxies]);
  }

  Future<void> pumpHost(WidgetTester tester) async {
    const size = Size(1200, 1000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).value = size;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(withStatusManager: true, child: SizedBox()),
      ),
    );
  }

  Future<List<Map>> savedProxies(Profile profile) async {
    final config = loadYaml(await (await profile.file).readAsString()) as Map;
    return [for (final proxy in config['proxies'] as List) proxy as Map];
  }

  group('addProfileFromLink with a share link', () {
    test('saves a file profile named after the proxy it holds', () async {
      const link = 'vless://id@hk.example.com:443#HK';
      decodesTo(link, [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(profile.url, isEmpty);
      expect(profile.label, 'HK');
      expect(await savedProxies(profile), [
        {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
      ]);
      verify(() => core.validateConfig(any())).called(1);
    });

    test('names an unnamed proxy after its server', () async {
      const link = 'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388';
      decodesTo(link, [
        {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link, label: 'Mine');

      final profile = container.read(profilesProvider).single;
      expect(profile.label, 'Mine');
      expect((await savedProxies(profile)).single['name'], 'ss.example.com');
    });

    test('moves a proxy off a name mihomo reserves', () async {
      const link = 'trojan://pass@t.example.com:443#DIRECT';
      decodesTo(link, [
        {'name': 'DIRECT', 'type': 'trojan', 'server': 't.example.com'},
      ]);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);

      final profile = container.read(profilesProvider).single;
      expect((await savedProxies(profile)).single['name'], 'DIRECT-01');
    });

    testWidgets('reports a link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      const link = 'vmess://not-base64';
      decodesTo(link, const []);
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(link);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text(currentAppLocalizations.shareLinksInvalid), findsOne);
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });

  group('addProfilesFromLinks with share links', () {
    const links = [
      'vless://id@hk.example.com:443#HK',
      'trojan://pass@hk2.example.com:443#HK',
      'ss://YWVzLTEyOC1nY206cGFzcw@ss.example.com:8388',
    ];

    test('makes one profile of all their proxies', () async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          [
            {'name': 'HK', 'type': 'trojan', 'server': 'hk2.example.com'},
          ],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);

      final profile = container.read(profilesProvider).single;
      expect(profile.type, ProfileType.file);
      expect(
        profile.label,
        currentAppLocalizations.proxiesProfileLabel('HK', 3),
      );
      expect(
        [for (final proxy in await savedProxies(profile)) proxy['name']],
        ['HK', 'HK-01', 'ss.example.com'],
      );
      verify(() => core.decodeShareLinks(links)).called(1);
    });

    testWidgets('names the link no proxy can be read from and adds nothing', (
      tester,
    ) async {
      when(() => core.decodeShareLinks(links)).thenAnswer(
        (_) async => [
          [
            {'name': 'HK', 'type': 'vless', 'server': 'hk.example.com'},
          ],
          const [],
          [
            {'name': '', 'type': 'ss', 'server': 'ss.example.com'},
          ],
        ],
      );
      await pumpHost(tester);

      await container
          .read(profilesActionProvider.notifier)
          .addProfilesFromLinks(links);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final l10n = currentAppLocalizations;
      expect(
        find.text(
          l10n.failedItem(links.first, l10n.shareLinkUnreadable(links[1])),
        ),
        findsOne,
      );
      expect(container.read(profilesProvider), isEmpty);
      verifyNever(() => core.validateConfig(any()));
    });
  });

  group('refresh after start', () {
    Profile subscription({Duration age = const Duration(days: 2)}) =>
        Profile.normal(
          label: 'Sub',
          url: 'https://sub.example.com',
        ).copyWith(lastUpdateDate: DateTime.now().subtract(age));

    (_ScriptedProfilesAction, ApplyRecordingSetupAction) host(
      Profile profile,
      List<Object> answers, {
      void Function()? onWait,
    }) {
      final setupAction = ApplyRecordingSetupAction();
      container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          profilesProvider.overrideWith(() => TestProfiles([profile])),
          profilesActionProvider.overrideWith(
            () => _ScriptedProfilesAction(answers, onWait: onWait),
          ),
          setupActionProvider.overrideWith(() => setupAction),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      return (
        container.read(profilesActionProvider.notifier)
            as _ScriptedProfilesAction,
        setupAction,
      );
    }

    test('retries a transient failure with backoff, then applies', () async {
      final profile = subscription();
      final (action, setupAction) = host(profile, [
        _unreachable(),
        _unreachable(),
        'ok',
      ]);

      final refreshed = await action.autoUpdateProfiles();

      expect(refreshed, {profile.id});
      expect(action.downloads, 3);
      expect(action.waits, ProfilesAction.updateRetryDelays.take(2));
      expect(setupAction.applyCount, 1);
      expect(
        container.read(profilesProvider).single.lastUpdateDate,
        isNot(profile.lastUpdateDate),
      );
    });

    test('gives up once the retries are spent', () async {
      final profile = subscription();
      final (action, setupAction) = host(profile, [
        for (var i = 0; i <= ProfilesAction.updateRetryDelays.length; i++)
          _unreachable(),
      ]);

      final refreshed = await action.autoUpdateProfiles();

      expect(refreshed, isEmpty);
      expect(action.downloads, ProfilesAction.updateRetryDelays.length + 1);
      expect(action.waits, ProfilesAction.updateRetryDelays);
      expect(setupAction.applyCount, 0);
    });

    test('does not retry a failure the next attempt would repeat', () async {
      for (final failure in [
        const MessageException('bad config'),
        _status(404),
      ]) {
        final (action, _) = host(subscription(), [failure, 'ok']);

        expect(await action.autoUpdateProfiles(), isEmpty);
        expect(action.downloads, 1, reason: '$failure');
        expect(action.waits, isEmpty, reason: '$failure');
      }
    });

    test('retries a server that is busy for the moment', () async {
      final profile = subscription();
      final (action, _) = host(profile, [_status(503), 'ok']);

      expect(await action.autoUpdateProfiles(), {profile.id});
      expect(action.downloads, 2);
    });

    test('a profile deleted during the backoff is left alone', () async {
      final profile = subscription();
      final (action, _) = host(
        profile,
        [_unreachable(), 'ok'],
        onWait: () => container.read(profilesProvider.notifier).del(profile.id),
      );

      expect(await action.autoUpdateProfiles(), isEmpty);
      expect(action.downloads, 1);
    });

    test('a profile updated by hand during the backoff is fresh', () async {
      final profile = subscription();
      final (action, _) = host(
        profile,
        [_unreachable(), 'ok'],
        onWait: () => container
            .read(profilesProvider.notifier)
            .put(profile.copyWith(lastUpdateDate: DateTime.now())),
      );

      final refreshed = await action.autoUpdateProfiles();
      await action.refreshCurrentProfileAfterStart(refreshed: refreshed);

      expect(refreshed, {profile.id});
      expect(action.downloads, 1);
    });

    test('the current profile is not fetched twice at start', () async {
      final (action, _) = host(subscription(), ['ok', 'ok']);

      final refreshed = await action.autoUpdateProfiles();
      await action.refreshCurrentProfileAfterStart(refreshed: refreshed);

      expect(action.downloads, 1);
    });

    test('a current profile that was not due is read again at start', () async {
      final (action, _) = host(subscription(age: const Duration(hours: 1)), [
        'ok',
      ]);

      final refreshed = await action.autoUpdateProfiles();
      await action.refreshCurrentProfileAfterStart(refreshed: refreshed);

      expect(refreshed, isEmpty);
      expect(action.downloads, 1);
    });

    test('an interval past what a date holds is never due', () async {
      final profile = subscription().copyWith(
        autoUpdateDuration: const Duration(hours: 2400000000),
      );
      final (action, _) = host(profile, ['ok', 'ok']);

      final refreshed = await action.autoUpdateProfiles();
      await action.refreshCurrentProfileAfterStart(refreshed: refreshed);

      expect(refreshed, isEmpty);
      expect(action.downloads, 1);
    });

    test('a pass already under way is joined, not run again', () async {
      final profile = subscription();
      final (action, _) = host(profile, ['ok', 'ok']);
      final gate = action.gate = Completer<void>();

      final first = action.autoUpdateProfiles();
      final second = action.autoUpdateProfiles();
      gate.complete();

      expect(await first, {profile.id});
      expect(await second, {profile.id});
      expect(action.downloads, 1);
      expect(await action.autoUpdateProfiles(), isEmpty);
    });
  });
}
