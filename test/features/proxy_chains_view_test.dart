import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart' hide Profiles;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/features/proxy_chains/proxy_chains.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _profileId = 7;

/// The whole config, members included, as the editor reads it; the outbound
/// names a profile lists on its own carry no members.
final _graph = ProxyChainGraph.fromRaw({
  'proxies': [
    {'name': 'DE', 'type': 'vless'},
    {'name': 'NL', 'type': 'trojan'},
    {'name': 'Bypass', 'type': 'direct'},
  ],
  'proxy-groups': [
    {
      'name': 'Auto',
      'type': 'url-test',
      'proxies': ['DE', 'NL'],
    },
  ],
});

const _working = ProxyChain(id: 'a', name: 'Telegram', hops: ['Auto', 'NL']);
const _broken = ProxyChain(id: 'b', name: 'Banks', hops: ['DE', 'Moscow']);
const _telegramRule = Rule(
  id: 1,
  ruleAction: RuleAction.DOMAIN_SUFFIX,
  content: 't.me',
  ruleTarget: 'Telegram',
  order: 'a',
);

class _Profiles extends TestProfiles {
  _Profiles(super.initial, {required this.failWrites});

  final bool failWrites;

  @override
  Future<void> rewriteCustom(
    Future<Map<int, Profile Function(Profile profile)>> Function() body,
  ) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    final changes = await body();
    state = [for (final item in state) changes[item.id]?.call(item) ?? item];
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  List<ProxyChain> chains = const [],
  String? matchTarget,
  bool failProfileWrites = false,
  List<Rule> rules = const [],
}) async {
  database = Database(NativeDatabase.memory());
  addTearDown(database.close);
  await tester.runAsync(() async {
    await database.profilesDao.putAll([
      const Profile(
        id: _profileId,
        autoUpdateDuration: Duration.zero,
      ).toCompanion(),
    ]);
    for (final rule in rules) {
      await database.rulesDao.putRule(rule, profileId: _profileId);
    }
  });
  SharedPreferences.setMockInitialValues({
    'proxy_chains_$_profileId': jsonEncode([
      for (final chain in chains) chain.toJson(),
    ]),
  });
  final profile = Profile.normal().copyWith(
    id: _profileId,
    matchTarget: matchTarget,
  );
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(
        () => _Profiles([profile], failWrites: failProfileWrites),
      ),
      proxyChainGraphProvider(_profileId).overrideWith((_) async => _graph),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(child: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<List<ProxyChain>> _stored() async {
  final preferences = await SharedPreferences.getInstance();
  final raw = preferences.getString('proxy_chains_$_profileId');
  return [
    for (final item in jsonDecode(raw ?? '[]') as List)
      ProxyChain.fromJson(item)!,
  ];
}

void main() {
  testWidgets('the section lists chains with their hops and issues', (
    tester,
  ) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
      chains: [_working, _broken],
    );
    final l = currentAppLocalizations;

    expect(find.text(l.proxyChainsTitle), findsOneWidget);
    expect(find.text(l.beta), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text(l.proxyChainMissingHop('Moscow')), findsOneWidget);
  });

  testWidgets('switching a chain off is saved', (tester) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
      chains: [_working],
    );

    await tester.tap(find.byType(CommonSwitch));
    await tester.pumpAndSettle();

    expect((await _stored()).single.enabled, isFalse);
  });

  testWidgets('an empty section offers to add a chain', (tester) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
    );

    expect(find.text(currentAppLocalizations.addProxyChain), findsOneWidget);
  });

  testWidgets('the editor adds and removes the middle hop', (tester) async {
    await _pump(tester, const ProxyChainForm(profileId: _profileId));
    final l = currentAppLocalizations;

    expect(find.text(l.proxyChainMiddle), findsNothing);
    await tester.tap(find.text(l.addProxyChainHop));
    await tester.pumpAndSettle();
    expect(find.text(l.proxyChainMiddle), findsWidgets);
    expect(find.text(l.addProxyChainHop), findsNothing);

    await tester.tap(find.byTooltip(l.remove));
    await tester.pumpAndSettle();
    expect(find.text(l.proxyChainMiddle), findsNothing);
  });

  testWidgets('saving an unfinished chain says what is missing', (
    tester,
  ) async {
    await _pump(tester, const ProxyChainForm(profileId: _profileId));

    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await tester.pumpAndSettle();

    expect(
      find.text(currentAppLocalizations.proxyChainIncomplete),
      findsOneWidget,
    );
    expect(await _stored(), isEmpty);
  });

  testWidgets('a chain may not take a name the profile already has', (
    tester,
  ) async {
    await _pump(
      tester,
      ProxyChainForm(
        profileId: _profileId,
        chain: _working.copyWith(name: 'Auto'),
      ),
      chains: [_working],
    );

    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await tester.pumpAndSettle();

    expect(
      find.text(currentAppLocalizations.proxyChainNameTaken('Auto')),
      findsOneWidget,
    );
    expect((await _stored()).single.name, 'Telegram');
  });

  testWidgets('a group can be picked as the exit, a direct proxy cannot', (
    tester,
  ) async {
    await _pump(tester, const ProxyChainForm(profileId: _profileId));
    final l = currentAppLocalizations;
    Future<void> pick(String hop, String name) async {
      await tester.tap(find.widgetWithText(FormRow, hop));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FormRow, l.proxyChainExit));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Bypass'), findsNothing);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    await pick(l.proxyChainEntry, 'DE');
    await tester.enterText(find.byType(TextFormField), 'Via DE');
    await tester.tap(find.byTooltip(l.save));
    await tester.pumpAndSettle();

    expect((await _stored()).single.hops, ['DE', 'Auto']);
  });

  testWidgets('the MATCH target chain cannot be switched off', (tester) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
      chains: [_working],
      matchTarget: 'Telegram',
    );

    await tester.tap(find.byType(CommonSwitch));
    await tester.pumpAndSettle();

    expect(
      find.text(currentAppLocalizations.proxyChainIsMatchTarget('Telegram')),
      findsOneWidget,
    );
    expect((await _stored()).single.enabled, isTrue);
  });

  testWidgets('a chain an added rule points at cannot be switched off', (
    tester,
  ) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
      chains: [_working],
      rules: [_telegramRule],
    );

    await tester.tap(find.byType(CommonSwitch));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(
      find.text(currentAppLocalizations.proxyChainIsRuleTarget('Telegram')),
      findsOneWidget,
    );
    expect((await _stored()).single.enabled, isTrue);
  });

  testWidgets('the add button shows once, in the empty row or the header', (
    tester,
  ) async {
    await _pump(
      tester,
      const CustomScrollView(
        slivers: [ProxyChainsSection(profileId: _profileId)],
      ),
    );

    expect(find.byTooltip(currentAppLocalizations.addProxyChain), findsNothing);
  });

  testWidgets('renaming a chain renames the added rules that point at it', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProxyChainForm(profileId: _profileId, chain: _working),
      chains: [_working],
      rules: [_telegramRule],
    );

    await tester.enterText(find.byType(TextFormField), 'Messages');
    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final rules = await tester.runAsync(
      () => database.rulesDao.queryProfileRules(_profileId).get(),
    );
    expect(rules!.single.ruleTarget, 'Messages');
  });

  testWidgets('renaming the MATCH target chain renames the target', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const ProxyChainForm(profileId: _profileId, chain: _working),
      chains: [_working],
      matchTarget: 'Telegram',
    );

    await tester.enterText(find.byType(TextFormField), 'Messages');
    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await tester.pumpAndSettle();

    expect((await _stored()).single.name, 'Messages');
    expect(
      container.read(profileProvider(_profileId))?.matchTarget,
      'Messages',
    );
  });

  testWidgets('a rename the MATCH target cannot follow is rolled back', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const ProxyChainForm(profileId: _profileId, chain: _working),
      chains: [_working],
      matchTarget: 'Telegram',
      failProfileWrites: true,
    );

    await tester.enterText(find.byType(TextFormField), 'Messages');
    await tester.tap(find.byTooltip(currentAppLocalizations.save));
    await tester.pumpAndSettle();

    expect((await _stored()).single.name, 'Telegram');
    expect(
      container.read(profileProvider(_profileId))?.matchTarget,
      'Telegram',
    );
    expect(
      find.text(currentAppLocalizations.databaseWriteFailedTip),
      findsOneWidget,
    );
    expect(find.byType(ProxyChainForm), findsOneWidget);
  });

  for (final failProfileWrites in [false, true]) {
    testWidgets('a rename finishes or undoes after the editor is gone '
        '(profile write fails: $failProfileWrites)', (tester) async {
      final write = ProxyChainsNotifier.write;
      addTearDown(() => ProxyChainsNotifier.write = write);
      final container = await _pump(
        tester,
        const ProxyChainForm(profileId: _profileId, chain: _working),
        chains: [_working],
        matchTarget: 'Telegram',
        failProfileWrites: failProfileWrites,
      );
      final gate = Completer<void>();
      ProxyChainsNotifier.write = (key, value) async {
        await gate.future;
        return write(key, value);
      };

      await tester.enterText(find.byType(TextFormField), 'Messages');
      await tester.tap(find.byTooltip(currentAppLocalizations.save));
      await tester.pump();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox(),
        ),
      );
      gate.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final chains = await container.read(
        proxyChainsProvider(_profileId).future,
      );

      final kept = failProfileWrites ? 'Telegram' : 'Messages';
      expect(chains.single.name, kept);
      expect(container.read(profileProvider(_profileId))?.matchTarget, kept);
    });
  }
}
