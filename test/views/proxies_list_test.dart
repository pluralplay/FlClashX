import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart' show TonalButtonGroup;
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/views/views.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  proxiesBarTests();
  proxyDescriptionTests();
  testWidgets('a folded group shows its description, never its type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(
      currentGroupName: 'Auto',
      unfoldSet: {'Auto'},
    );
    final groups = [
      const Group(
        name: 'Auto',
        type: GroupType.URLTest,
        hidden: false,
        now: 'Proxy 1',
        serverDescription: 'Fastest',
        all: [Proxy(name: 'Proxy 1', type: 'ss')],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pumpAndSettle();
    expect(find.text('Fastest'), findsNothing);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();

    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text(GroupType.URLTest.name), findsNothing);
  });

  testWidgets('the list scrolls its rows under the bar, pinning the header '
      'at its foot', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(
      currentGroupName: 'Selector',
      selectedMap: {'Selector': 'Proxy 1'},
      unfoldSet: {'Selector'},
    );
    final group = Group(
      name: 'Selector',
      type: GroupType.Selector,
      hidden: false,
      now: 'Proxy 1',
      all: List.generate(
        160,
        (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        groupsProvider.overrideWithValue([group]),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(tester.getRect(find.byType(ListHeader)).top, barBottom + 8);

    await tester.drag(find.byType(ProxyCard).first, const Offset(0, -300));
    await tester.pump();

    expect(tester.getRect(find.byType(ListHeader)).top, barBottom + 8);
    expect(
      find
          .byType(ProxyCard)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget))),
      contains(
        predicate<Rect>(
          (rect) => rect.top < barBottom && rect.bottom > 0,
          'a card under the bar',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds only the headers near the view and pins a far one '
      'once its rows reach the bar', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = Profile.normal().copyWith(unfoldSet: {'Far'});
    final groups = [
      for (var index = 0; index < 40; index++)
        Group(name: 'G$index', type: GroupType.Selector, hidden: false),
      Group(
        name: 'Far',
        type: GroupType.Selector,
        hidden: false,
        all: List.generate(
          160,
          (index) => Proxy(name: 'Proxy $index', type: 'Direct'),
        ),
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    expect(
      find.byType(ListHeader, skipOffstage: false).evaluate().length,
      lessThan(groups.length ~/ 2),
    );

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent - 1000);
    await tester.pump();

    final barBottom = tester.getRect(find.byType(AppBar)).bottom;
    final far = find.ancestor(
      of: find.text('Far'),
      matching: find.byType(ListHeader),
    );
    expect(tester.getRect(far).top, barBottom + 8);
    expect(find.text('G0', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _MockCore extends Mock implements CoreHandlerInterface {}

void proxyDescriptionTests() {
  testWidgets('a node shows its profile description in place of the type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = Profile.normal().copyWith(
      currentGroupName: 'Selector',
      unfoldSet: {'Selector'},
    );
    const nodes = [
      Proxy(name: 'P1', type: 'ss', serverDescription: 'Amsterdam, 10 Gbit'),
      Proxy(name: 'P2', type: 'ss'),
    ];
    final groups = [
      const Group(
        name: 'Selector',
        type: GroupType.Selector,
        hidden: false,
        now: 'P1',
        all: nodes,
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    expect(find.text('Amsterdam, 10 Gbit', findRichText: true), findsOneWidget);
    expect(find.text('ss', findRichText: true), findsOneWidget);
  });
}

void proxiesBarTests() {
  testWidgets('the bar switches the mode and tests every node once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = _MockCore();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (invocation) async => Delay(
        url: invocation.positionalArguments[0] as String,
        name: invocation.positionalArguments[1] as String,
        value: 42,
      ),
    );
    final profile = Profile.normal().copyWith(currentGroupName: 'Selector');
    const nodes = [
      Proxy(name: 'P1', type: 'ss'),
      Proxy(name: 'P2', type: 'ss'),
    ];
    final groups = [
      const Group(
        name: 'Selector',
        type: GroupType.Selector,
        hidden: false,
        now: 'P1',
        all: nodes,
      ),
      Group(
        name: 'Auto',
        type: GroupType.URLTest,
        hidden: false,
        now: 'P1',
        all: [nodes.first],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pump();

    expect(find.byTooltip('Outbound mode: Rule'), findsOneWidget);
    await tester.tap(find.byTooltip('Outbound mode: Rule'));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
    expect(find.byTooltip('Outbound mode: Global'), findsOneWidget);
    await tester.tap(find.byTooltip('Outbound mode: Global'));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);

    await tester.tap(find.byTooltip('Test every delay'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    verify(() => core.asyncTestDelay(any(), 'P1')).called(1);
    verify(() => core.asyncTestDelay(any(), 'P2')).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one bar button unfolds every shown group and folds them back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = Profile.normal().copyWith(unfoldSet: {'Hidden'});
    const node = Proxy(name: 'P1', type: 'ss');
    final groups = [
      const Group(
        name: 'Selector',
        type: GroupType.Selector,
        hidden: false,
        now: 'P1',
        all: [node],
      ),
      const Group(
        name: 'Auto',
        type: GroupType.URLTest,
        hidden: false,
        now: 'P1',
        all: [node],
      ),
      const Group(
        name: 'Hidden',
        type: GroupType.Selector,
        hidden: true,
        now: 'P1',
        all: [node],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        groupsProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(500, 1000));
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(type: ProxiesType.list));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: ProxiesView()),
      ),
    );
    await tester.pump();

    expect(find.byType(TonalButtonGroup), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand all groups'));
    await tester.pumpAndSettle();
    expect(container.read(unfoldSetProvider), {'Hidden', 'Selector', 'Auto'});

    await tester.tap(find.byTooltip('Collapse all groups'));
    await tester.pumpAndSettle();
    expect(container.read(unfoldSetProvider), {'Hidden'});
  });
}
