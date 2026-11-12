import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

/// A subscription as the Core reads it back: `rule` rather than `rules`.
Map<String, dynamic> _subscription() => {
  'mixed-port': 7890,
  'proxies': [
    {
      'name': 'DE',
      'type': 'ss',
      'server': 'de.example',
      'port': 8388,
      'cipher': 'aes-128-gcm',
      'password': 'p',
    },
    {
      'name': 'NL',
      'type': 'ss',
      'server': 'nl.example',
      'port': 8388,
      'cipher': 'aes-128-gcm',
      'password': 'p',
    },
  ],
  'proxy-groups': [
    {
      'name': 'Auto',
      'type': 'url-test',
      'proxies': ['DE'],
      'url': 'https://www.gstatic.com/generate_204',
      'interval': 300,
    },
    {
      'name': 'Netherlands',
      'type': 'select',
      'proxies': ['NL'],
    },
  ],
  'rule': ['MATCH,Auto'],
};

const _state = SetupState(
  profileId: 5,
  profileLastUpdateDate: null,
  profileType: ProfileType.url,
  extendType: ExtendType.standard,
  rules: [],
  proxyGroups: [],
  addedRules: [],
  script: null,
  overrides: ProfileOverrides(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('proxy_chains_build');
    await useAppPaths(root);
    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clashx',
      version: '0.0.0',
      buildNumber: '0',
    );
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  Future<(BuiltProfile, _MockCore)> build(SetupState state) async {
    final core = _MockCore();
    when(() => core.getProfileBase(any())).thenAnswer(
      (_) async => ProfileBase(
        config: {
          for (final MapEntry(:key, :value) in _subscription().entries)
            if (key != 'proxies' && key != 'proxy-groups' && key != 'rule')
              key: value,
        },
        digest: 'd',
        matchRules: const ['MATCH,Auto'],
      ),
    );
    when(() => core.getConfig(any())).thenAnswer((_) async => _subscription());
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig(tun: Tun(enable: false)),
        ),
        setupActionProvider.overrideWith(SetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    final built = await container
        .read(setupActionProvider.notifier)
        .getProfile(setupState: state, patchConfig: const PatchClashConfig());
    return (built, core);
  }

  test('a subscription with chains is built from its whole config', () async {
    final (built, core) = await build(
      _state.copyWith(
        proxyChains: [
          const ProxyChain(
            id: 'a',
            name: 'Telegram',
            hops: ['Auto', 'Netherlands'],
          ).toJson(),
        ],
      ),
    );

    verifyNever(() => core.getProfileBase(any()));
    expect(built.base, isNull);
    final config = loadYaml(built.yaml) as YamlMap;
    final groups = (config['proxy-groups'] as YamlList).cast<YamlMap>();
    final chain = groups.singleWhere((group) => group['name'] == 'Telegram');
    expect(chain['proxies'], ['NL · Telegram']);
    final clone = (config['proxies'] as YamlList).cast<YamlMap>().singleWhere(
      (proxy) => proxy['name'] == 'NL · Telegram',
    );
    expect(clone['dialer-proxy'], 'Auto');
    expect(config['rules'], ['MATCH,Auto']);
  });

  test('a subscription without chains keeps the lighter base', () async {
    final (built, core) = await build(_state);

    verify(() => core.getProfileBase(any())).called(1);
    expect(built.base, isNotNull);
  });
}
