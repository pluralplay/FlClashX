import 'dart:convert';

import 'package:fl_clash/common/common.dart';
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

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  List<ProxyChain> chains = const [],
  String? matchTarget,
}) async {
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
      profilesProvider.overrideWith(() => TestProfiles([profile])),
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
}
