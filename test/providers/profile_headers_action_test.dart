import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_profiles.dart';

Profile _profile(
  int id, {
  String? view,
  String? widgets,
  String? special,
  String? settings,
  DateTime? updatedAt,
}) => Profile(
  id: id,
  autoUpdateDuration: Duration.zero,
  lastUpdateDate: updatedAt,
  providerHeaders: {
    'flclashx-view': ?view,
    'flclashx-widgets': ?widgets,
    'flclashx-special': ?special,
    'flclashx-settings': ?settings,
  },
);

void main() {
  late ProviderContainer container;

  ThemeMode themeMode() => container.read(themeSettingProvider).themeMode;

  void setThemeMode(ThemeMode mode) => container
      .read(themeSettingProvider.notifier)
      .update((state) => state.copyWith(themeMode: mode));

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(() => TestProfiles([]))],
    );
    globalState.container = container;
    addTearDown(container.dispose);
    container.listen(currentProfileIdProvider, (_, _) {});
    container.listen(themeSettingProvider, (_, _) {});
    container.listen(proxiesStyleSettingProvider, (_, _) {});
    container.listen(appSettingProvider, (_, _) {});
    container.listen(patchClashConfigProvider, (_, _) {});
    container.listen(profileHeadersActionProvider, (_, _) {});
  });

  /// The listeners hear a change on the next microtask.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> select(Profile profile) async {
    container.read(profilesProvider.notifier).put(profile);
    container.read(currentProfileIdProvider.notifier).value = profile.id;
    await settle();
  }

  Future<void> put(Profile profile) async {
    container.read(profilesProvider.notifier).put(profile);
    await settle();
  }

  test('a header lands after the flush that reported the profile', () async {
    container.listen(navigationItemsStateProvider, (_, _) {});
    container.listen(configProvider, (_, _) {});

    await select(_profile(1, view: 'app.navbar:floating;app.theme:dark'));

    expect(container.read(appSettingProvider).floatingNavigationBar, isTrue);
    expect(themeMode(), ThemeMode.dark);
    expect(() => container.read(navigationItemsStateProvider), returnsNormally);
    expect(() => container.read(configProvider), returnsNormally);
  });

  test(
    'the settings header turns the named switches on and the rest off',
    () async {
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoRun: true, openLogs: true));

      await select(_profile(1, settings: 'minimize,autoupdate'));

      final setting = container.read(appSettingProvider);
      expect(setting.minimizeOnExit, isTrue);
      expect(setting.autoCheckUpdate, isTrue);
      expect(setting.autoRun, isFalse);
      expect(setting.openLogs, isFalse);

      await select(_profile(2));
      final own = container.read(appSettingProvider);
      expect(own.minimizeOnExit, isFalse);
      expect(own.autoCheckUpdate, isFalse);
      expect(own.autoRun, isTrue);
      expect(own.openLogs, isTrue);
    },
  );

  test('the view header hides the proxies that timed out', () async {
    await select(_profile(1, view: 'proxies.hidetimeout:true'));
    expect(
      container.read(proxiesStyleSettingProvider).hideTimeoutProxies,
      isTrue,
    );

    container
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(ownedSettings: {'view.proxies.hidetimeout'}),
        );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => state.copyWith(hideTimeoutProxies: false));
    await select(_profile(2, view: 'proxies.hidetimeout:true'));
    expect(
      container.read(proxiesStyleSettingProvider).hideTimeoutProxies,
      isFalse,
    );
  });

  test('a view key the user took over is left to the user', () async {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(ownedSettings: {'view.app.theme'}));

    await select(_profile(1, view: 'app.theme:dark;proxies.type:tab'));

    expect(themeMode(), ThemeMode.system);
    expect(container.read(proxiesStyleSettingProvider).type, ProxiesType.tab);
  });

  test(
    'the theme key sets the appearance unless the user took it over',
    () async {
      await select(_profile(1, view: 'app.theme:dark'));
      expect(container.read(themeSettingProvider).themeMode, ThemeMode.dark);

      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(ownedSettings: {'view.app.theme'}));
      container
          .read(themeSettingProvider.notifier)
          .update((state) => state.copyWith(themeMode: ThemeMode.system));
      await select(_profile(2, view: 'app.theme:light'));
      expect(container.read(themeSettingProvider).themeMode, ThemeMode.system);
    },
  );

  test('a switch the user took over is left to the user', () async {
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(ownedSettings: {'app.minimizeOnExit'}),
        );

    await select(_profile(1, settings: 'minimize,autoupdate'));

    final setting = container.read(appSettingProvider);
    expect(setting.minimizeOnExit, isFalse);
    expect(setting.autoCheckUpdate, isTrue);
  });

  test('the hideip special hides the IP and locks its switch', () async {
    await select(_profile(1, special: 'hideip'));

    expect(container.read(appSettingProvider).hideIp, isTrue);
    expect(container.read(settingLockedProvider(hideIpSetting)), isTrue);
  });

  test('an IP switch the user took over is left to the user', () async {
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(hideIp: false, ownedSettings: {hideIpSetting}),
        );

    await select(_profile(1, special: 'hideip'));

    expect(container.read(appSettingProvider).hideIp, isFalse);
    expect(container.read(settingLockedProvider(hideIpSetting)), isFalse);
    expect(container.read(settingReleasableProvider(hideIpSetting)), isTrue);
  });

  test('without the hideip special the IP switch stays the user\'s', () async {
    await select(_profile(1, special: 'noglobal'));

    expect(container.read(appSettingProvider).hideIp, isFalse);
    expect(
      container.read(managedSettingsProvider),
      isNot(contains(hideIpSetting)),
    );
  });

  test('the onlytun special turns the system proxy off and locks it', () async {
    container.listen(networkSettingProvider, (_, _) {});
    container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));

    await select(_profile(1, special: 'onlytun'));

    expect(container.read(networkSettingProvider).systemProxy, isFalse);
    expect(container.read(systemProxyAllowedProvider), isFalse);
    container.read(systemActionProvider.notifier).updateSystemProxy();
    expect(container.read(networkSettingProvider).systemProxy, isFalse);
    expect(container.read(proxyStateProvider).systemProxy, isFalse);
  });

  test('the system proxy onlytun took comes back with a profile without '
      'it', () async {
    container.listen(networkSettingProvider, (_, _) {});
    container.listen(vpnSettingProvider, (_, _) {});
    container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));
    container
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));

    await select(_profile(1, special: 'onlytun'));
    await select(_profile(2, special: 'onlytun'));
    expect(container.read(networkSettingProvider).systemProxy, isFalse);
    expect(container.read(vpnSettingProvider).systemProxy, isFalse);

    await select(_profile(3));
    expect(container.read(networkSettingProvider).systemProxy, isTrue);
    expect(container.read(vpnSettingProvider).systemProxy, isTrue);
  });

  test(
    'a panel that drops onlytun leaves an unused system proxy off',
    () async {
      container.listen(networkSettingProvider, (_, _) {});
      container
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(systemProxy: false));

      await select(_profile(1, special: 'onlytun'));
      await put(_profile(1));

      expect(container.read(networkSettingProvider).systemProxy, isFalse);
    },
  );

  test('the novibrate special turns vibration off and locks it', () async {
    await select(_profile(1, special: 'novibrate'));

    expect(container.read(appSettingProvider).vibration, isFalse);
    expect(container.read(settingLockedProvider(vibrationSetting)), isTrue);
  });

  test('vibration the user took over is left to the user', () async {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(ownedSettings: {vibrationSetting}));

    await select(_profile(1, special: 'novibrate'));

    expect(container.read(appSettingProvider).vibration, isTrue);
    expect(container.read(settingReleasableProvider(vibrationSetting)), isTrue);
  });

  test('a panel that drops hideip and novibrate puts both back', () async {
    await select(_profile(1, special: 'hideip,novibrate'));
    expect(container.read(appSettingProvider).hideIp, isTrue);
    expect(container.read(appSettingProvider).vibration, isFalse);

    await put(_profile(1, special: 'noglobal'));

    final setting = container.read(appSettingProvider);
    expect(setting.hideIp, isFalse);
    expect(setting.vibration, isTrue);
    expect(setting.panelSetSettings, isEmpty);
  });

  test('a hidden IP the user chose survives a panel without hideip', () async {
    await select(_profile(1, special: 'noglobal'));
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(hideIp: true));

    await put(_profile(1));

    expect(container.read(appSettingProvider).hideIp, isTrue);
  });

  test(
    'a special the user took over keeps the user\'s value once dropped',
    () async {
      await select(_profile(1, special: 'hideip'));
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(ownedSettings: {hideIpSetting}));

      await put(_profile(1));

      final setting = container.read(appSettingProvider);
      expect(setting.hideIp, isTrue);
      expect(setting.panelSetSettings, isEmpty);
    },
  );

  test(
    'settings from before the tracking still let a dropped hideip go',
    () async {
      final profile = _profile(1, special: 'hideip');
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              hideIp: true,
              appliedHeadersUpdate: profileHeadersUpdateOf(profile),
            ),
          );
      await select(profile);
      expect(
        container.read(appSettingProvider).panelSetSettings,
        contains(hideIpSetting),
      );

      await put(_profile(1));

      expect(container.read(appSettingProvider).hideIp, isFalse);
    },
  );

  test('cards a panel picked before the flag count as picked', () async {
    final profile = _profile(1, widgets: 'currentOutbound,profiles');
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            dashboardWidgets: const [
              DashboardWidget.currentOutbound,
              DashboardWidget.profiles,
            ],
            appliedHeadersUpdate: profileHeadersUpdateOf(profile),
            floatingNavigationBar: false,
          ),
        );
    await select(profile);

    final setting = container.read(appSettingProvider);
    expect(setting.dashboardWidgetsChosen, isTrue);
    expect(setting.floatingNavigationBar, isFalse);
  });

  test('without the novibrate special vibration stays the user\'s', () async {
    await select(_profile(1, special: 'hideip'));

    expect(container.read(appSettingProvider).vibration, isTrue);
    expect(
      container.read(managedSettingsProvider),
      isNot(contains(vibrationSetting)),
    );
  });

  test('the header picks the theme when its profile is switched to', () async {
    await select(_profile(1, view: 'app.theme:dark'));
    expect(themeMode(), ThemeMode.dark);

    await select(_profile(2, view: 'app.theme:light'));
    expect(themeMode(), ThemeMode.light);
  });

  test('a profile without the header leaves the choice alone', () async {
    setThemeMode(ThemeMode.dark);
    await select(_profile(1));
    expect(themeMode(), ThemeMode.dark);
  });

  test('every update of the profile applies the header again', () async {
    final first = DateTime(2026, 10, 19, 10);
    await select(_profile(1, view: 'app.theme:dark', updatedAt: first));
    expect(themeMode(), ThemeMode.dark);

    setThemeMode(ThemeMode.light);
    await put(_profile(1, view: 'app.theme:dark', updatedAt: first));
    expect(themeMode(), ThemeMode.light);

    await put(
      _profile(
        1,
        view: 'app.theme:dark',
        updatedAt: first.add(const Duration(hours: 1)),
      ),
    );
    expect(themeMode(), ThemeMode.dark);
  });

  test('a change between updates leaves the edited dashboard alone', () async {
    final first = DateTime(2026, 10, 19, 10);
    final profile = _profile(
      1,
      widgets: 'announcement,outboundMode',
      updatedAt: first,
    );
    await select(profile);
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(dashboardWidgets: [DashboardWidget.outboundMode]),
        );

    await put(profile.copyWith(currentGroupName: GroupName.GLOBAL.name));
    expect(container.read(appSettingProvider).dashboardWidgets, [
      DashboardWidget.outboundMode,
    ]);

    await put(
      profile.copyWith(lastUpdateDate: first.add(const Duration(hours: 1))),
    );
    expect(container.read(appSettingProvider).dashboardWidgets, [
      DashboardWidget.announcement,
      DashboardWidget.outboundMode,
    ]);
  });

  group('cards the user arranged', () {
    final first = DateTime(2026, 10, 19, 10);

    Future<void> arrange() async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              dashboardWidgets: [DashboardWidget.outboundMode],
              ownedSettings: {...state.ownedSettings, dashboardWidgetsSetting},
            ),
          );
      await settle();
    }

    test('survive the next update without denywidgets', () async {
      final profile = _profile(
        1,
        widgets: 'announcement,outboundMode',
        updatedAt: first,
      );
      await select(profile);
      await arrange();

      await put(
        profile.copyWith(lastUpdateDate: first.add(const Duration(hours: 1))),
      );

      expect(container.read(appSettingProvider).dashboardWidgets, [
        DashboardWidget.outboundMode,
      ]);
    });

    test('give way to the panel under denywidgets', () async {
      final profile = _profile(
        1,
        widgets: 'announcement,outboundMode',
        special: 'denywidgets',
        updatedAt: first,
      );
      await select(profile);
      await arrange();

      await put(
        profile.copyWith(lastUpdateDate: first.add(const Duration(hours: 1))),
      );

      expect(container.read(appSettingProvider).dashboardWidgets, [
        DashboardWidget.announcement,
        DashboardWidget.outboundMode,
      ]);
    });
  });

  test('an update applied before a restart is not applied again', () async {
    final updatedAt = DateTime(2026, 10, 19, 10, 0, 0, 750);
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            appliedHeadersUpdate: profileHeadersUpdateOf(
              _profile(1, view: 'app.theme:dark', updatedAt: updatedAt),
            ),
          ),
        );

    await select(
      _profile(
        1,
        view: 'app.theme:dark',
        updatedAt: DateTime(2026, 10, 19, 10),
      ),
    );

    expect(themeMode(), ThemeMode.system);
  });

  test('a second update within the same second applies its headers', () async {
    final updatedAt = DateTime(2026, 10, 19, 10);
    await select(_profile(1, view: 'app.theme:dark', updatedAt: updatedAt));
    expect(container.read(themeSettingProvider).themeMode, ThemeMode.dark);

    await put(
      _profile(
        1,
        view: 'app.theme:light',
        updatedAt: updatedAt.add(const Duration(milliseconds: 400)),
      ),
    );

    expect(container.read(themeSettingProvider).themeMode, ThemeMode.light);
  });

  test('a profile restored after the last was deleted applies again', () async {
    final profile = _profile(
      1,
      view: 'app.theme:dark',
      updatedAt: DateTime(2026, 10, 19, 10),
    );
    await select(profile);
    container.read(currentProfileIdProvider.notifier).value = null;
    await settle();
    setThemeMode(ThemeMode.light);

    await select(profile);

    expect(themeMode(), ThemeMode.dark);
  });

  test(
    'the colour keys paint the theme and keeps the colour on offer',
    () async {
      await select(
        _profile(
          1,
          view: 'app.color:FF5733;app.style:monochrome;app.black:true',
        ),
      );

      final theme = container.read(themeSettingProvider);
      expect(theme.primaryColor, 0xFFFF5733);
      expect(theme.primaryColors, contains(0xFFFF5733));
      expect(theme.colorStyle, ColorStyle.monochrome);
      expect(theme.pureBlack, isTrue);

      await select(_profile(2, view: 'app.color:3366CC;app.black:false'));
      final next = container.read(themeSettingProvider);
      expect(next.primaryColor, 0xFF3366CC);
      expect(next.colorStyle, ColorStyle.vivid);
      expect(next.pureBlack, isFalse);
      expect(next.primaryColors.where((c) => c == 0xFF3366CC), hasLength(1));
      expect(next.primaryColors, isNot(contains(0xFFFF5733)));

      await select(_profile(3));
      final own = container.read(themeSettingProvider);
      expect(own.primaryColor, isNull);
      expect(own.primaryColors, const ThemeProps().primaryColors);
      expect(own.pureBlack, isFalse);
    },
  );

  test(
    'the view header sets only the parts of the proxies page it names',
    () async {
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(layout: ProxiesLayout.loose));

      await select(
        _profile(
          1,
          view: 'proxies.type:tab;proxies.sort:name;proxies.card:compact',
        ),
      );

      final style = container.read(proxiesStyleSettingProvider);
      expect(style.type, ProxiesType.tab);
      expect(style.sortType, ProxiesSortType.name);
      expect(style.cardType, ProxyCardType.compact);
      expect(style.layout, ProxiesLayout.loose);
    },
  );

  test('the view header also sets the bar, the tabs and the glass', () async {
    await select(
      _profile(1, view: 'app.navbar:docked;app.tabs:fade;app.glass:standard'),
    );

    final app = container.read(appSettingProvider);
    expect(app.floatingNavigationBar, isFalse);
    expect(app.tabAnimation, TabAnimation.fade);
    expect(
      container.read(themeSettingProvider).liquidGlass,
      LiquidGlassMode.standard,
    );

    await select(_profile(2, view: 'proxies.type:tab'));
    expect(container.read(appSettingProvider).floatingNavigationBar, isTrue);
    expect(container.read(appSettingProvider).tabAnimation, TabAnimation.fade);
    expect(
      container.read(themeSettingProvider).liquidGlass,
      LiquidGlassMode.none,
    );
  });

  test(
    'a panel without global mode moves a global profile back to rule',
    () async {
      container.listen(availableModesProvider, (_, _) {});
      container.read(setupActionProvider.notifier).changeMode(Mode.global);
      expect(container.read(patchClashConfigProvider).mode, Mode.global);

      await select(_profile(1, special: 'noglobal'));

      expect(container.read(patchClashConfigProvider).mode, Mode.rule);
      expect(container.read(availableModesProvider), [Mode.rule, Mode.direct]);
      container.read(setupActionProvider.notifier).changeMode(Mode.global);
      expect(container.read(patchClashConfigProvider).mode, Mode.rule);

      await select(_profile(2));
      expect(container.read(availableModesProvider), Mode.values);
      expect(container.read(patchClashConfigProvider).mode, Mode.global);
    },
  );

  test('a mode picked under noglobal stays once the flag goes', () async {
    final setup = container.read(setupActionProvider.notifier);
    setup.changeMode(Mode.global);
    await select(_profile(1, special: 'noglobal'));
    await setup.pickMode(Mode.direct, ask: false);
    await setup.pickMode(Mode.rule, ask: false);

    await put(_profile(1));

    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  test('a mode cycled under noglobal stays once the flag goes', () async {
    container.read(setupActionProvider.notifier).changeMode(Mode.global);
    await select(_profile(1, special: 'noglobal'));
    final common = container.read(commonActionProvider.notifier);
    common.updateMode();
    common.updateMode();
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);

    await put(_profile(1));

    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  test('the widgets header lays out the standard dashboard', () async {
    final own = container.read(appSettingProvider).dashboardWidgets;
    await select(_profile(1, widgets: 'memoryInfo,proxyGroups,networkSpeed'));

    expect(container.read(appSettingProvider).dashboardWidgets, [
      DashboardWidget.memoryInfo,
      DashboardWidget.proxyGroups,
      DashboardWidget.networkSpeed,
    ]);

    await select(_profile(2, widgets: 'nothing-known'));
    expect(container.read(appSettingProvider).dashboardWidgets, own);
    expect(container.read(appSettingProvider).dashboardWidgetsChosen, isFalse);
  });

  group('settings a profile holds go back to the user\'s', () {
    test('when switching to a profile without the headers', () async {
      setThemeMode(ThemeMode.light);
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((state) => state.copyWith(layout: ProxiesLayout.loose));

      await select(
        _profile(
          1,
          view: 'app.theme:dark;proxies.layout:tight;proxies.type:tab',
        ),
      );
      expect(themeMode(), ThemeMode.dark);
      expect(
        container.read(proxiesStyleSettingProvider).layout,
        ProxiesLayout.tight,
      );

      await select(_profile(2));
      final style = container.read(proxiesStyleSettingProvider);
      expect(themeMode(), ThemeMode.light);
      expect(style.layout, ProxiesLayout.loose);
      expect(style.type, ProxiesType.list);
      expect(container.read(appSettingProvider).headerBackup, isEmpty);
    });

    test('through two panels that both set them', () async {
      setThemeMode(ThemeMode.light);

      await select(_profile(1, view: 'app.theme:dark'));
      await select(_profile(2, view: 'app.theme:auto'));
      expect(themeMode(), ThemeMode.system);

      await select(_profile(3));
      expect(themeMode(), ThemeMode.light);
    });

    test('when an update drops the key', () async {
      setThemeMode(ThemeMode.light);
      final first = DateTime(2026, 11, 16, 10);
      await select(_profile(1, view: 'app.theme:dark', updatedAt: first));
      expect(themeMode(), ThemeMode.dark);

      await put(
        _profile(
          1,
          view: 'proxies.type:tab',
          updatedAt: first.add(const Duration(minutes: 1)),
        ),
      );
      expect(themeMode(), ThemeMode.light);
    });

    test('unless the user took the setting over', () async {
      setThemeMode(ThemeMode.light);
      await select(_profile(1, view: 'app.theme:dark'));

      container
          .read(managedSettingsActionProvider.notifier)
          .takeOver('view.app.theme');
      setThemeMode(ThemeMode.system);

      await select(_profile(2));
      expect(themeMode(), ThemeMode.system);
      expect(container.read(appSettingProvider).headerBackup, isEmpty);
    });

    test('for the switches and the cards', () async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              openLogs: true,
              dashboardWidgets: const [DashboardWidget.profiles],
              dashboardWidgetsChosen: true,
            ),
          );

      await select(
        _profile(1, settings: 'minimize', widgets: 'memoryInfo,networkSpeed'),
      );
      var setting = container.read(appSettingProvider);
      expect(setting.openLogs, isFalse);
      expect(setting.minimizeOnExit, isTrue);
      expect(setting.dashboardWidgets, [
        DashboardWidget.memoryInfo,
        DashboardWidget.networkSpeed,
      ]);

      await select(_profile(2));
      setting = container.read(appSettingProvider);
      expect(setting.openLogs, isTrue);
      expect(setting.minimizeOnExit, isFalse);
      expect(setting.dashboardWidgets, [DashboardWidget.profiles]);
      expect(setting.dashboardWidgetsChosen, isTrue);
    });

    test('for hideip and novibrate', () async {
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(hideIp: true, vibration: false));

      await select(_profile(1, special: 'hideip,novibrate'));
      expect(container.read(appSettingProvider).hideIp, isTrue);

      await select(_profile(2));
      final setting = container.read(appSettingProvider);
      expect(setting.hideIp, isTrue);
      expect(setting.vibration, isFalse);
      expect(setting.panelSetSettings, isEmpty);
    });

    test('as the user chose while they held it, once handed back', () async {
      setThemeMode(ThemeMode.light);
      await select(_profile(1, view: 'app.theme:dark'));

      final managed = container.read(managedSettingsActionProvider.notifier);
      managed.takeOver('view.app.theme');
      setThemeMode(ThemeMode.system);
      // What release does for the headers, without the profile file read.
      managed.disown('view.app.theme');
      container
          .read(profileHeadersActionProvider.notifier)
          .apply(
            profileHeaderSettingsOf(container.read(currentProfileProvider)),
          );
      expect(themeMode(), ThemeMode.dark);

      await select(_profile(2));
      expect(themeMode(), ThemeMode.system);
    });

    test('for cards denywidgets forced over the user\'s own', () async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              dashboardWidgets: const [DashboardWidget.profiles],
              dashboardWidgetsChosen: true,
              ownedSettings: {dashboardWidgetsSetting},
            ),
          );

      await select(
        _profile(1, special: 'denywidgets', widgets: 'networkSpeed'),
      );
      expect(container.read(appSettingProvider).dashboardWidgets, [
        DashboardWidget.networkSpeed,
      ]);

      await select(_profile(2));
      expect(container.read(appSettingProvider).dashboardWidgets, [
        DashboardWidget.profiles,
      ]);
    });

    test('a flag the panel set before backups stays the panel\'s', () async {
      final first = DateTime(2026, 11, 16, 10);
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(hideIp: true, panelSetSettings: {hideIpSetting}),
          );

      await select(_profile(1, special: 'hideip', updatedAt: first));
      expect(container.read(appSettingProvider).hideIp, isTrue);

      await put(_profile(1, updatedAt: first.add(const Duration(minutes: 1))));
      expect(container.read(appSettingProvider).hideIp, isFalse);
    });

    test('past a backup entry it cannot read', () async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              headerBackup: {'theme.swatches': 'bad', 'theme.mode': 42},
            ),
          );
      setThemeMode(ThemeMode.light);

      await select(_profile(1, view: 'app.theme:dark;app.color:3366CC'));
      expect(themeMode(), ThemeMode.dark);
      expect(container.read(themeSettingProvider).primaryColor, 0xFF3366CC);

      await select(_profile(2));
      expect(themeMode(), ThemeMode.light);
      expect(container.read(themeSettingProvider).primaryColor, isNull);
      expect(container.read(appSettingProvider).headerBackup, isEmpty);
    });

    test('a flag set before the backup existed falls back to off', () async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) =>
                state.copyWith(hideIp: true, panelSetSettings: {hideIpSetting}),
          );

      await select(_profile(1));
      expect(container.read(appSettingProvider).hideIp, isFalse);
    });
  });
}
