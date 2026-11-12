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

  ThemeStyle style() => container.read(themeSettingProvider).style;

  void setStyle(ThemeStyle style) => container
      .read(themeSettingProvider.notifier)
      .update((state) => state.copyWith(style: style));

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

    await select(_profile(1, view: 'app.navbar:floating;app.board:extended'));

    expect(container.read(appSettingProvider).floatingNavigationBar, isTrue);
    expect(style(), ThemeStyle.enhanced);
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
      expect(container.read(appSettingProvider).minimizeOnExit, isTrue);
    },
  );

  test('a view key the user took over is left to the user', () async {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(ownedSettings: {'view.app.board'}));

    await select(_profile(1, view: 'app.board:extended;proxies.type:tab'));

    expect(style(), ThemeStyle.original);
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

  test('without the novibrate special vibration stays the user\'s', () async {
    await select(_profile(1, special: 'hideip'));

    expect(container.read(appSettingProvider).vibration, isTrue);
    expect(
      container.read(managedSettingsProvider),
      isNot(contains(vibrationSetting)),
    );
  });

  test('the header picks the style when its profile is switched to', () async {
    await select(_profile(1, view: 'app.board:extended'));
    expect(style(), ThemeStyle.enhanced);

    await select(_profile(2, view: 'app.board:standard'));
    expect(style(), ThemeStyle.original);
  });

  test('a profile without the header leaves the choice alone', () async {
    setStyle(ThemeStyle.enhanced);
    await select(_profile(1));
    expect(style(), ThemeStyle.enhanced);
  });

  test('every update of the profile applies the header again', () async {
    final first = DateTime(2026, 10, 19, 10);
    await select(_profile(1, view: 'app.board:extended', updatedAt: first));
    expect(style(), ThemeStyle.enhanced);

    setStyle(ThemeStyle.original);
    await put(_profile(1, view: 'app.board:extended', updatedAt: first));
    expect(style(), ThemeStyle.original);

    await put(
      _profile(
        1,
        view: 'app.board:extended',
        updatedAt: first.add(const Duration(hours: 1)),
      ),
    );
    expect(style(), ThemeStyle.enhanced);
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

  test('an update applied before a restart is not applied again', () async {
    final updatedAt = DateTime(2026, 10, 19, 10, 0, 0, 750);
    container
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            appliedHeadersUpdate: profileHeadersUpdateOf(
              _profile(1, view: 'app.board:extended', updatedAt: updatedAt),
            ),
          ),
        );

    await select(
      _profile(
        1,
        view: 'app.board:extended',
        updatedAt: DateTime(2026, 10, 19, 10),
      ),
    );

    expect(style(), ThemeStyle.original);
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
      view: 'app.board:extended',
      updatedAt: DateTime(2026, 10, 19, 10),
    );
    await select(profile);
    container.read(currentProfileIdProvider.notifier).value = null;
    await settle();
    setStyle(ThemeStyle.original);

    await select(profile);

    expect(style(), ThemeStyle.enhanced);
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
      expect(next.colorStyle, ColorStyle.monochrome);
      expect(next.pureBlack, isFalse);
      expect(next.primaryColors.where((c) => c == 0xFF3366CC), hasLength(1));
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
    expect(container.read(appSettingProvider).floatingNavigationBar, isFalse);
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
    },
  );

  test('the widgets header lays out the standard dashboard', () async {
    await select(_profile(1, widgets: 'memoryInfo,proxyGroups,networkSpeed'));

    expect(container.read(appSettingProvider).dashboardWidgets, [
      DashboardWidget.memoryInfo,
      DashboardWidget.proxyGroups,
      DashboardWidget.networkSpeed,
    ]);

    await select(_profile(2, widgets: 'nothing-known'));
    expect(container.read(appSettingProvider).dashboardWidgets, [
      DashboardWidget.memoryInfo,
      DashboardWidget.proxyGroups,
      DashboardWidget.networkSpeed,
    ]);
  });
}
