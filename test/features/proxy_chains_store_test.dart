import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

const _profileId = 3;

class _MockCore extends Mock implements CoreHandlerInterface {}

class _EditableScripts extends Scripts {
  _EditableScripts(this._initial);

  final List<Script> _initial;

  @override
  Stream<List<Script>> build() => Stream.value(_initial);

  void replace(List<Script> scripts) => state = AsyncData(scripts);
}

ProxyChain _chain(String id) =>
    ProxyChain(id: id, name: id, hops: const ['DE', 'FI']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the store', () {
    late ProviderContainer container;
    late Future<bool> Function(String, String) write;

    setUp(() {
      write = ProxyChainsNotifier.write;
      SharedPreferences.setMockInitialValues({
        'proxy_chains_$_profileId': jsonEncode([
          _chain('A').toJson(),
          _chain('B').toJson(),
        ]),
      });
      container = ProviderContainer();
    });

    tearDown(() {
      ProxyChainsNotifier.write = write;
      container.dispose();
    });

    ProxyChainsNotifier notifier() =>
        container.read(proxyChainsProvider(_profileId).notifier);

    test('changes made before the last one is written all land', () async {
      final chains = await container.read(
        proxyChainsProvider(_profileId).future,
      );
      await Future.wait([
        notifier().put(chains[0].copyWith(enabled: false)),
        notifier().put(chains[1].copyWith(enabled: false)),
      ]);

      final saved = await container.read(
        proxyChainsProvider(_profileId).future,
      );
      expect(saved.map((chain) => chain.enabled), [false, false]);
    });

    test(
      'a write that throws or refuses is reported and changes nothing',
      () async {
        final chains = await container.read(
          proxyChainsProvider(_profileId).future,
        );
        for (final failing in <Future<bool> Function(String, String)>[
          (_, _) async => throw const FileSystemException('full'),
          (_, _) async => false,
        ]) {
          ProxyChainsNotifier.write = failing;
          await expectLater(
            notifier().remove(chains.first.id),
            throwsA(isA<ProxyChainsSaveException>()),
          );
          expect(container.read(proxyChainsProvider(_profileId)).value, chains);
        }
      },
    );
  });

  group('restoring a backup', () {
    late Future<bool> Function(String, String) write;
    final refProvider = Provider<Ref>((ref) => ref);

    setUp(() {
      write = ProxyChainsNotifier.write;
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => ProxyChainsNotifier.write = write);

    test(
      'a refused write is reported, the other profiles still restored',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final restored = <String>[];
        ProxyChainsNotifier.write = (key, value) async {
          restored.add(key);
          return key != 'proxy_chains_1';
        };
        final chains = jsonEncode([_chain('A').toJson()]);

        await expectLater(
          restoreProxyChains(
            container.read(refProvider),
            {'1': chains, '2': chains},
            const [1, 2],
          ),
          throwsA(isA<ProxyChainsSaveException>()),
        );
        expect(restored, ['proxy_chains_1', 'proxy_chains_2']);
      },
    );

    test('a backup without the chains key leaves them untouched', () async {
      SharedPreferences.setMockInitialValues({'proxy_chains_1': '["kept"]'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      ProxyChainsNotifier.write = (_, _) async => false;

      await restoreProxyChains(container.read(refProvider), null, const [1]);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('proxy_chains_1'), '["kept"]');
    });
  });

  test('the outbound graph follows edits to the profile script', () async {
    final root = Directory.systemTemp.createTempSync('proxy_chains_script');
    addTearDown(() => root.deleteSync(recursive: true));
    await useAppPaths(root);
    final evaluate = scriptEvaluator;
    addTearDown(() => scriptEvaluator = evaluate);
    scriptEvaluator = ({required script, required config}) async => jsonEncode({
      ...jsonDecode(config) as Map<String, dynamic>,
      'proxies': [
        {'name': script.trim(), 'type': 'ss'},
      ],
    });
    final script = Script(id: 11, label: 's', lastUpdateTime: DateTime(2026));
    final scriptFile = File(await script.path)
      ..createSync(recursive: true)
      ..writeAsStringSync('First');
    final profile = Profile.normal().copyWith(
      id: _profileId,
      extendType: ExtendType.script,
      scriptId: script.id,
    );
    final core = _MockCore();
    when(() => core.getConfig(any())).thenAnswer((_) async => {'rule': []});
    final scripts = _EditableScripts([script]);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        scriptsProvider.overrideWith(() => scripts),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      proxyChainGraphProvider(_profileId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(scriptsProvider.future);

    final first = await container.read(
      proxyChainGraphProvider(_profileId).future,
    );
    expect(first?.proxyTypes.keys, ['First']);

    scriptFile.writeAsStringSync('Second');
    scripts.replace([script.copyWith(lastUpdateTime: DateTime(2027))]);
    final second = await container.read(
      proxyChainGraphProvider(_profileId).future,
    );
    expect(second?.proxyTypes.keys, ['Second']);
  });
}
