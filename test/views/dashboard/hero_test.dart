import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/views/views.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/hero.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_paths.dart';
import '../../helpers/glyph_finders.dart';
import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

const _ip = '203.0.113.9';

class _RecordingSetupAction extends SetupAction {
  final requests = <bool>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) {
    requests.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value(true);
  }
}

class _Ips extends OutboundIpProbe {
  final refreshed = <String>[];

  @override
  void refresh(Iterable<String> targets) {
    refreshed.addAll(targets);
  }

  @override
  RoutedProbeState<String, IpInfo> build() => const RoutedProbeState({
    routedOutbound: ProbeEntry(
      phase: ProbePhase.fresh,
      value: IpInfo(ip: _ip, countryCode: 'GB'),
    ),
  });

  @override
  void watch(String target) {}

  @override
  void unwatch(String target) {}
}

Profile _profile({Map<String, String> headers = const {}}) => Profile(
  id: 1,
  type: ProfileType.url,
  url: 'https://sub.example.com/abc',
  label: 'P1',
  autoUpdateDuration: Duration.zero,
  providerHeaders: headers,
);

Group _group(String name, List<String> proxies, {String? now}) => Group(
  type: GroupType.Selector,
  name: name,
  hidden: false,
  now: now,
  all: [for (final proxy in proxies) Proxy(name: proxy, type: 'ss')],
);

void main() {
  late ProviderContainer container;

  setUpAll(() async {
    final home = Directory.systemTemp.createTempSync('hero_test');
    addTearDown(() => home.deleteSync(recursive: true));
    await useAppPaths(home);
  });

  void setUp_({
    List<Profile> profiles = const [],
    List<Group> groups = const [],
    bool running = false,
  }) {
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        outboundIpProbeProvider.overrideWith(_Ips.new),
        ipQualityProvider.overrideWith(
          (_, ip) async => IpQuality(
            ip: ip,
            source: IpQualitySource.ipInfo,
            type: IpType.residential,
            organization: 'Example',
            asn: 64500,
          ),
        ),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
        suspendProvider.overrideWithValue(false),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(450, 900)),
      ],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    container.listen(currentProfileIdProvider, (_, _) {});
    container.read(currentProfileIdProvider.notifier).value =
        profiles.firstOrNull?.id;
    container.listen(groupsProvider, (_, _) {});
    container.read(groupsProvider.notifier).value = groups;
    if (running) {
      container.read(runTimeProvider.notifier).value = 1;
    }
  }

  Future<void> pump(WidgetTester tester, {Widget? child}) async {
    tester.view.physicalSize = const Size(450, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: child ?? const Scaffold(body: HeroDashboard()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('offers to add a profile when there is none', (tester) async {
    setUp_();
    await pump(tester);

    expect(find.text('Add profile'), findsOneWidget);
    expect(find.text(appName), findsOneWidget);
    expect(find.byType(ProfilesCard), findsNothing);
    expect(find.byTooltip('Start'), findsNothing);
  });

  testWidgets('names the service, its support page and the plan', (
    tester,
  ) async {
    setUp_(
      profiles: [
        _profile(
          headers: const {
            'flclashx-servicename': 'Proxeyed',
            'support-url': 'https://help.example.com',
          },
        ),
      ],
      groups: [
        _group('Auto', [
          '🇳🇱 Amsterdam',
          '🇩🇪 Berlin',
        ], now: '🇳🇱 Amsterdam'),
      ],
    );
    await pump(tester);

    expect(find.text('Proxeyed'), findsOneWidget);
    expect(find.text(appName), findsNothing);
    expect(find.byTooltip('Support'), findsOneWidget);
    expect(find.byTooltip('Update'), findsOneWidget);
    expect(find.byType(ProfilesCard), findsOneWidget);
    expect(find.text('Amsterdam', findRichText: true), findsOneWidget);
    expect(find.text(_ip), findsNothing);
    expect(
      tester.widget<CountryFlag>(find.byType(CountryFlag)).countryCode,
      'NL',
    );
    expect(find.text('+1'), findsOneWidget);
    expect(find.byTooltip('Start'), findsOneWidget);
    expect(tester.getSize(find.byType(FilledButton).last).width, 450 - 32);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a flag in the node description stands in for one in its name', (
    tester,
  ) async {
    setUp_(
      profiles: [_profile()],
      groups: [
        const Group(
          type: GroupType.Selector,
          name: 'Auto',
          hidden: false,
          now: 'Fast',
          all: [
            Proxy(name: 'Fast', type: 'ss', serverDescription: '🇩🇪 Berlin'),
          ],
        ),
      ],
    );
    await pump(tester);

    expect(
      tester.widget<CountryFlag>(find.byType(CountryFlag)).countryCode,
      'DE',
    );
    expect(find.text('Fast', findRichText: true), findsOneWidget);
  });

  testWidgets('a nested group shows its own name, with the flag of its pick', (
    tester,
  ) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['Netherlands'], now: 'Netherlands'),
        _group('Netherlands', [
          '🇳🇱 Amsterdam',
          '🇳🇱 Rotterdam',
        ], now: '🇳🇱 Amsterdam'),
      ],
    );
    await pump(tester);

    expect(find.text('Netherlands', findRichText: true), findsOneWidget);
    expect(find.text('Amsterdam', findRichText: true), findsNothing);
    expect(
      tester.widget<CountryFlag>(find.byType(CountryFlag)).countryCode,
      'NL',
    );
  });

  testWidgets('the app name stands in and the support button stays away', (
    tester,
  ) async {
    setUp_(profiles: [_profile()]);
    await pump(tester);

    expect(find.text(appName), findsOneWidget);
    expect(find.byTooltip('Support'), findsNothing);
    expect(find.text('Change server'), findsOneWidget);
  });

  testWidgets('shows the exit address and run time while running', (
    tester,
  ) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['🇳🇱 Amsterdam'], now: '🇳🇱 Amsterdam'),
      ],
      running: true,
    );
    await pump(tester);

    expect(find.text(_ip), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.text(getTimeText(1)), findsOneWidget);
  });

  testWidgets('the flag rechecks the exit address while running', (
    tester,
  ) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['🇳🇱 Amsterdam'], now: '🇳🇱 Amsterdam'),
      ],
      running: true,
    );
    await pump(tester);
    final ips = container.read(outboundIpProbeProvider.notifier) as _Ips;

    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();

    expect(ips.refreshed, [routedOutbound]);
    expect(find.byGlyph(AppGlyphs.chevronForward), findsNothing);
  });

  testWidgets('the address opens the same details as the standard card', (
    tester,
  ) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['🇳🇱 Amsterdam'], now: '🇳🇱 Amsterdam'),
      ],
      running: true,
    );
    await pump(tester);

    await tester.tap(find.text(_ip));
    await tester.pumpAndSettle();

    expect(find.text(currentAppLocalizations.outboundIp), findsOneWidget);
  });

  testWidgets('a hidden IP is masked on the server card too', (tester) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['🇳🇱 Amsterdam'], now: '🇳🇱 Amsterdam'),
      ],
      running: true,
    );
    container.listen(appSettingProvider, (_, _) {});
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(hideIp: true));
    await pump(tester);

    expect(find.text(_ip), findsNothing);
    expect(find.text(ipMask), findsOneWidget);
  });

  testWidgets('the swap button opens the server picker', (tester) async {
    setUp_(
      profiles: [
        _profile(headers: const {'flclashx-serverinfo': 'Auto'}),
      ],
      groups: [
        _group('Auto', ['🇳🇱 Amsterdam'], now: '🇳🇱 Amsterdam'),
      ],
    );
    await pump(tester);

    await tester.tap(find.byTooltip('Change server'));
    await tester.pumpAndSettle();

    expect(find.byType(ProxiesView), findsOneWidget);
  });

  testWidgets('the connect button toggles the shared running state', (
    tester,
  ) async {
    setUp_(profiles: [_profile()]);
    await pump(tester);
    final action =
        container.read(setupActionProvider.notifier) as _RecordingSetupAction;

    await tester.tap(find.byTooltip('Start'));
    await tester.pumpAndSettle();
    expect(action.requests, [true]);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(action.requests, [true, false]);
    expect(find.byTooltip('Start'), findsOneWidget);
  });

  testWidgets('the bar holds the mode button, flipping rule and global', (
    tester,
  ) async {
    setUp_(profiles: [_profile()]);
    container.listen(themeSettingProvider, (_, _) {});
    container
        .read(themeSettingProvider.notifier)
        .update((state) => state.copyWith(style: ThemeStyle.enhanced));
    await pump(tester, child: const DashboardView());
    await tester.pump();

    await tester.tap(find.byTooltip('Outbound mode: Rule'));
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
    expect(find.byTooltip('Outbound mode: Global'), findsOneWidget);
    expect(find.byGlyph(AppGlyphs.proxies), findsWidgets);
  });

  testWidgets('the dashboard swaps its grid for the hero in enhanced style', (
    tester,
  ) async {
    setUp_(profiles: [_profile()]);
    container.listen(themeSettingProvider, (_, _) {});
    container
        .read(themeSettingProvider.notifier)
        .update((state) => state.copyWith(style: ThemeStyle.enhanced));
    await pump(tester, child: const DashboardView());
    await tester.pump();

    expect(find.byType(HeroDashboard), findsOneWidget);
    expect(find.byType(CurrentOutboundCard), findsNothing);
    expect(find.byTooltip('Edit dashboard'), findsNothing);

    container
        .read(themeSettingProvider.notifier)
        .update((state) => state.copyWith(style: ThemeStyle.original));
    await tester.pump();
    await tester.pump();

    expect(find.byType(HeroDashboard), findsNothing);
    expect(find.byType(CurrentOutboundCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
