import 'package:dynamic_color/dynamic_color.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';

part 'generated/state.g.dart';

@riverpod
Config configState(Ref ref) {
  final themeProps = ref.watch(themeSettingProvider);
  final patchClashConfig = ref.watch(patchClashConfigProvider);
  final appSetting = ref.watch(appSettingProvider);
  final profiles = ref.watch(profilesProvider);
  final currentProfileId = ref.watch(currentProfileIdProvider);
  final overrideDns = ref.watch(overrideDnsProvider);
  final networkProps = ref.watch(networkSettingProvider);
  final vpnProps = ref.watch(vpnSettingProvider);
  final proxiesStyle = ref.watch(proxiesStyleSettingProvider);
  final scriptProps = ref.watch(scriptStateProvider);
  final hotKeyActions = ref.watch(hotKeyActionsProvider);
  final dav = ref.watch(appDAVSettingProvider);
  final windowProps = ref.watch(windowSettingProvider);
  return Config(
    dav: dav,
    windowProps: windowProps,
    hotKeyActions: hotKeyActions,
    scriptProps: scriptProps,
    proxiesStyle: proxiesStyle,
    vpnProps: vpnProps,
    networkProps: networkProps,
    overrideDns: overrideDns,
    currentProfileId: currentProfileId,
    profiles: profiles,
    appSetting: appSetting,
    themeProps: themeProps,
    patchClashConfig: patchClashConfig,
  );
}

@riverpod
GroupsState currentGroupsState(Ref ref) {
  final mode =
      ref.watch(patchClashConfigProvider.select((state) => state.mode));
  final groups = ref.watch(groupsProvider);
  return GroupsState(
    value: switch (mode) {
      Mode.direct => [],
      // With `flclashx-override` on GLOBAL, global mode has a single selector —
      // show only GLOBAL (service groups belong to rule mode). Otherwise keep
      // the original behaviour: every group.
      Mode.global => globalState.globalOverrideEnabled.value
          ? groups.where((item) => item.name == GroupName.GLOBAL.name).toList()
          : groups.toList(),
      Mode.rule => groups
          .where((item) => item.hidden == false)
          .where((element) => element.name != GroupName.GLOBAL.name)
          .toList(),
    },
  );
}

@riverpod
NavigationItemsState navigationsState(Ref ref) {
  final openLogs = ref.watch(appSettingProvider).openLogs;
  final hasProxies = ref.watch(
      currentGroupsStateProvider.select((state) => state.value.isNotEmpty));
  return NavigationItemsState(
    value: navigation.getItems(
      openLogs: openLogs,
      hasProxies: hasProxies,
    ),
  );
}

@riverpod
NavigationItemsState currentNavigationsState(Ref ref) {
  final viewWidth = ref.watch(viewWidthProvider);
  final navigationItemsState = ref.watch(navigationsStateProvider);
  final navigationItemMode = switch (viewWidth <= maxMobileWidth) {
    true => NavigationItemMode.mobile,
    false => NavigationItemMode.desktop,
  };
  return NavigationItemsState(
    value: navigationItemsState.value
        .where(
          (element) => element.modes.contains(navigationItemMode),
        )
        .toList(),
  );
}

@riverpod
CoreState coreState(Ref ref) {
  var vpnProps = ref.watch(vpnSettingProvider);
  final mixedPort = ref.watch(
    patchClashConfigProvider.select((state) => state.mixedPort),
  );
  // With mixed-port disabled there is no HTTP proxy to advertise to the OS.
  // Force VpnProps.systemProxy off so FlClashVpnService doesn't register a
  // ProxyInfo pointing at 127.0.0.1:0 via setHttpProxy. Traffic is still
  // routed through the VPN/TUN, just without the HTTP-proxy hint.
  if (mixedPort == 0 && vpnProps.systemProxy) {
    vpnProps = vpnProps.copyWith(systemProxy: false);
  }
  final currentProfile = ref.watch(currentProfileProvider);
  return CoreState(
    vpnProps: vpnProps,
    onlyStatisticsProxy: false,
    currentProfileName: currentProfile?.label ?? currentProfile?.id ?? "",
  );
}

@riverpod
UpdateParams updateParams(Ref ref) {
  final routeMode = ref.watch(
    networkSettingProvider.select(
      (state) => state.routeMode,
    ),
  );
  return ref.watch(
    patchClashConfigProvider.select(
      (state) => UpdateParams(
        tun: state.tun.getRealTun(routeMode),
        allowLan: state.allowLan,
        findProcessMode: state.findProcessMode,
        mode: state.mode,
        logLevel: state.logLevel,
        ipv6: state.ipv6,
        tcpConcurrent: state.tcpConcurrent,
        externalController: state.externalController,
        unifiedDelay: state.unifiedDelay,
        mixedPort: state.mixedPort,
      ),
    ),
  );
}

@riverpod
ProxyState proxyState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final vm2 = ref.watch(networkSettingProvider.select(
    (state) => VM2(
      a: state.systemProxy,
      b: state.bypassDomain,
    ),
  ));
  final mixedPort = ref.watch(
    patchClashConfigProvider.select((state) => state.mixedPort),
  );
  // Mixed-port = 0 means the HTTP proxy inbound is disabled, so there's
  // nothing for the OS-level system proxy to point at. Force it off here so
  // ProxyManager calls stopProxy() instead of startProxy(0, ...).
  final systemProxy = mixedPort == 0 ? false : vm2.a;
  return ProxyState(
    isStart: isStart,
    systemProxy: systemProxy,
    bassDomain: vm2.b,
    port: mixedPort,
  );
}

@riverpod
TrayState trayState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final networkProps = ref.watch(networkSettingProvider);
  final clashConfig = ref.watch(
    patchClashConfigProvider,
  );
  final appSetting = ref.watch(
    appSettingProvider,
  );
  final groups = ref
      .watch(
        currentGroupsStateProvider,
      )
      .value;
  final brightness = ref.watch(
    appBrightnessProvider,
  );

  final selectedMap = ref.watch(selectedMapProvider);
  final globalModeEnabled = ref.watch(globalModeEnabledProvider);

  return TrayState(
    mode: clashConfig.mode,
    port: clashConfig.mixedPort,
    autoLaunch: appSetting.autoLaunch,
    systemProxy: networkProps.systemProxy,
    tunEnable: clashConfig.tun.enable,
    isStart: isStart,
    locale: appSetting.locale,
    brightness: brightness,
    groups: groups,
    selectedMap: selectedMap,
    globalModeEnabled: globalModeEnabled,
  );
}

@riverpod
VpnState vpnState(Ref ref) {
  final vpnProps = ref.watch(vpnSettingProvider);
  final stack = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.stack),
  );

  return VpnState(
    stack: stack,
    vpnProps: vpnProps,
  );
}

@riverpod
HomeState homeState(Ref ref) {
  final pageLabel = ref.watch(currentPageLabelProvider);
  final navigationItems = ref.watch(currentNavigationsStateProvider).value;
  final viewMode = ref.watch(viewModeProvider);
  final locale = ref.watch(appSettingProvider).locale;
  return HomeState(
    pageLabel: pageLabel,
    navigationItems: navigationItems,
    viewMode: viewMode,
    locale: locale,
  );
}

@riverpod
DashboardState dashboardState(Ref ref) {
  final dashboardWidgets =
      ref.watch(appSettingProvider.select((state) => state.dashboardWidgets));
  final viewWidth = ref.watch(viewWidthProvider);
  return DashboardState(
    dashboardWidgets: dashboardWidgets,
    viewWidth: viewWidth,
  );
}

@riverpod
ProxiesActionsState proxiesActionsState(Ref ref) {
  final pageLabel = ref.watch(currentPageLabelProvider);
  final hasProviders = ref.watch(providersProvider.select(
    (state) => state.isNotEmpty,
  ));
  final type = ref.watch(proxiesStyleSettingProvider.select(
    (state) => state.type,
  ));
  return ProxiesActionsState(
    pageLabel: pageLabel,
    hasProviders: hasProviders,
    type: type,
  );
}

@riverpod
StartButtonSelectorState startButtonSelectorState(Ref ref) {
  final isInit = ref.watch(initProvider);
  final hasProfile =
      ref.watch(profilesProvider.select((state) => state.isNotEmpty));
  final hasProxiesInit =
      ref.watch(groupsProvider.select((state) => state.isNotEmpty));
  return StartButtonSelectorState(
    isInit: isInit,
    hasProfile: hasProfile,
    hasProxiesInit: hasProxiesInit,
  );
}

@riverpod
ProfilesSelectorState profilesSelectorState(Ref ref) {
  final currentProfileId = ref.watch(currentProfileIdProvider);
  final profiles = ref.watch(profilesProvider);
  final columns = ref.watch(
    viewWidthProvider.select(
      utils.getProfilesColumns,
    ),
  );
  return ProfilesSelectorState(
    profiles: profiles,
    currentProfileId: currentProfileId,
    columns: columns,
  );
}

@riverpod
ProxiesListSelectorState proxiesListSelectorState(Ref ref) {
  final groupNames = ref.watch(currentGroupsStateProvider.select((state) => state.value.map((e) => e.name).toList()));
  final currentUnfoldSet = ref.watch(unfoldSetProvider);
  final proxiesStyle = ref.watch(proxiesStyleSettingProvider);
  final sortNum = ref.watch(sortNumProvider);
  final columns = ref.watch(getProxiesColumnsProvider);
  final query = ref.watch(
    proxiesQueryProvider.select(
      (state) => state.toLowerCase(),
    ),
  );
  return ProxiesListSelectorState(
    groupNames: groupNames,
    currentUnfoldSet: currentUnfoldSet,
    proxiesSortType: proxiesStyle.sortType,
    proxyCardType: proxiesStyle.cardType,
    sortNum: sortNum,
    columns: columns,
    query: query,
  );
}

@riverpod
ProxiesSelectorState proxiesSelectorState(Ref ref) {
  final groupNames = ref.watch(
    currentGroupsStateProvider.select(
      (state) => state.value.map((e) => e.name).toList(),
    ),
  );
  final currentGroupName = ref.watch(currentProfileProvider.select(
    (state) => state?.currentGroupName,
  ));
  return ProxiesSelectorState(
    groupNames: groupNames,
    currentGroupName: currentGroupName,
  );
}

@riverpod
GroupNamesState groupNamesState(Ref ref) => GroupNamesState(
    groupNames: ref.watch(
      currentGroupsStateProvider.select(
        (state) => state.value.map((e) => e.name).toList(),
      ),
    ),
  );

@riverpod
ProxyGroupSelectorState proxyGroupSelectorState(Ref ref, String groupName) {
  final proxiesStyle = ref.watch(
    proxiesStyleSettingProvider,
  );
  final group = ref.watch(
    currentGroupsStateProvider.select(
      (state) => state.value.getGroup(groupName),
    ),
  );
  final sortNum = ref.watch(sortNumProvider);
  final columns = ref.watch(getProxiesColumnsProvider);
  final query =
      ref.watch(proxiesQueryProvider.select((state) => state.toLowerCase()));
  final proxies = group?.all.where((item) => item.name.toLowerCase().contains(query)).toList() ??
      [];
  return ProxyGroupSelectorState(
    testUrl: group?.testUrl,
    proxiesSortType: proxiesStyle.sortType,
    proxyCardType: proxiesStyle.cardType,
    sortNum: sortNum,
    groupType: group?.type ?? GroupType.Selector,
    proxies: proxies,
    columns: columns,
  );
}

@riverpod
PackageListSelectorState packageListSelectorState(Ref ref) {
  final packages = ref.watch(packagesProvider);
  final accessControl =
      ref.watch(vpnSettingProvider.select((state) => state.accessControl));
  return PackageListSelectorState(
    packages: packages,
    accessControl: accessControl,
  );
}

@riverpod
MoreToolsSelectorState moreToolsSelectorState(Ref ref) {
  final viewMode = ref.watch(viewModeProvider);
  final navigationItems = ref.watch(navigationsStateProvider.select((state) => state.value.where((element) {
      final isMore = element.modes.contains(NavigationItemMode.more);
      final isDesktop = element.modes.contains(NavigationItemMode.desktop);
      if (isMore && !isDesktop) return true;
      if (viewMode != ViewMode.mobile || !isMore) {
        return false;
      }
      return true;
    }).toList()));

  return MoreToolsSelectorState(navigationItems: navigationItems);
}

@riverpod
bool isCurrentPage(
  Ref ref,
  PageLabel pageLabel, {
  bool Function(PageLabel pageLabel, ViewMode viewMode)? handler,
}) {
  final currentPageLabel = ref.watch(currentPageLabelProvider);
  if (pageLabel == currentPageLabel) {
    return true;
  }
  if (handler != null) {
    final viewMode = ref.watch(viewModeProvider);
    return handler(currentPageLabel, viewMode);
  }
  return false;
}

@riverpod
String getRealTestUrl(Ref ref, [String? testUrl]) {
  final currentTestUrl = ref.watch(appSettingProvider).testUrl;
  return testUrl.getSafeValue(currentTestUrl);
}

@riverpod
int? getDelay(
  Ref ref, {
  required String proxyName,
  String? testUrl,
}) {
  final currentTestUrl = ref.watch(getRealTestUrlProvider(testUrl));
  final proxyCardState = ref.watch(
    getProxyCardStateProvider(
      proxyName,
    ),
  );
  final delay = ref.watch(
    delayDataSourceProvider.select(
      (state) {
        final delayMap =
            state[proxyCardState.testUrl.getSafeValue(currentTestUrl)];
        return delayMap?[proxyCardState.proxyName];
      },
    ),
  );
  return delay;
}

@riverpod
SelectedMap selectedMap(Ref ref) {
  final selectedMap = ref.watch(
    currentProfileProvider.select((state) => state?.selectedMap ?? {}),
  );
  return selectedMap;
}

@riverpod
Set<String> unfoldSet(Ref ref) {
  final unfoldSet = ref.watch(
    currentProfileProvider.select((state) => state?.unfoldSet ?? {}),
  );
  return unfoldSet;
}

@riverpod
HotKeyAction getHotKeyAction(Ref ref, HotAction hotAction) => ref.watch(
    hotKeyActionsProvider.select(
      (state) {
        final index = state.indexWhere((item) => item.action == hotAction);
        return index != -1
            ? state[index]
            : HotKeyAction(
                action: hotAction,
              );
      },
    ),
  );

@riverpod
Profile? currentProfile(Ref ref) {
  final profileId = ref.watch(currentProfileIdProvider);
  return ref
      .watch(profilesProvider.select((state) => state.getProfile(profileId)));
}

@riverpod
bool globalModeEnabled(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  final value = profile?.providerHeaders['flclashx-globalmode'];
  return value?.toLowerCase() != 'false';
}

/// Single source of truth for whether the "new look" (hero) dashboard is shown.
/// Just the `newDashboard` setting — the toggle is never locked. The
/// `flclashx-newboard` header writes this setting via _applyCustomViewSettings under
/// the standard `flclashx-custom` policy (`update` re-applies on every profile apply,
/// `add` only when the subscription is first added), so the provider can switch the
/// board on/off through the normal header pipeline rather than overriding here.
@riverpod
bool newDashboardEnabled(Ref ref) {
  // vnxMATRIX поставляется только с новым видом: старая раскладка — наследие
  // апстрима, у нас она недоступна. Возвращаем константу, а не хранимое
  // значение, чтобы вид не откатился у тех, кто успел переключить тумблер до
  // его удаления, и чтобы заголовок flclashx-newboard не мог его выключить.
  return true;
}

@riverpod
bool hasAnnounceData(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  final value = profile?.providerHeaders['announce'];
  return value != null && value.isNotEmpty;
}

@riverpod
bool hasServiceInfoData(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  final value = profile?.providerHeaders['flclashx-servicename'];
  return value != null && value.isNotEmpty;
}

@riverpod
bool hasServerInfoData(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  final value = profile?.providerHeaders['flclashx-serverinfo'];
  return value != null && value.isNotEmpty;
}

// `flclashx-background` is "<url>" or "<url>,<opacity 1-100>" (opacity = how visible
// the background image is; higher = more visible; absent = the default dimmed look).
String? backgroundUrlFromHeader(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final i = raw.indexOf(',');
  final url = (i >= 0 ? raw.substring(0, i) : raw).trim();
  return url.isEmpty ? null : url;
}

int? backgroundOpacityFromHeader(String? raw) {
  if (raw == null) return null;
  final i = raw.indexOf(',');
  if (i < 0) return null;
  final v = int.tryParse(raw.substring(i + 1).trim());
  return v == null ? null : v.clamp(1, 100);
}

@riverpod
String? backgroundUrl(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  return backgroundUrlFromHeader(profile?.providerHeaders['flclashx-background']);
}

/// Background image opacity (1-100, higher = more visible) parsed from the optional
/// `,<opacity>` suffix of `flclashx-background`. Null = not specified (default look).
@riverpod
int? backgroundOpacity(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  return backgroundOpacityFromHeader(profile?.providerHeaders['flclashx-background']);
}

@riverpod
int getProxiesColumns(Ref ref) {
  final viewWidth = ref.watch(viewWidthProvider);
  final proxiesLayout =
      ref.watch(proxiesStyleSettingProvider.select((state) => state.layout));
  return utils.getProxiesColumns(viewWidth, proxiesLayout);
}

ProxyCardState _getProxyCardState(
  List<Group> groups,
  SelectedMap selectedMap,
  ProxyCardState proxyDelayState, [
  int depth = 0,
]) {
  if (depth > 16) return proxyDelayState;
  if (proxyDelayState.proxyName.isEmpty) return proxyDelayState;
  final index =
      groups.indexWhere((element) => element.name == proxyDelayState.proxyName);
  if (index == -1) return proxyDelayState;
  final group = groups[index];
  final currentSelectedName = group
      .getCurrentSelectedName(selectedMap[proxyDelayState.proxyName] ?? '');
  if (currentSelectedName.isEmpty ||
      currentSelectedName == proxyDelayState.proxyName) {
    return proxyDelayState;
  }
  return _getProxyCardState(
    groups,
    selectedMap,
    proxyDelayState.copyWith(
      proxyName: currentSelectedName,
      testUrl: group.testUrl,
    ),
    depth + 1,
  );
}

@riverpod
ProxyCardState getProxyCardState(Ref ref, String proxyName) {
  final groups = ref.watch(groupsProvider);
  final selectedMap = ref.watch(selectedMapProvider);
  return _getProxyCardState(
      groups, selectedMap, ProxyCardState(proxyName: proxyName));
}

@riverpod
String? getProxyName(Ref ref, String groupName) {
  final proxyName =
      ref.watch(selectedMapProvider.select((state) => state[groupName]));
  return proxyName;
}

@riverpod
String? getSelectedProxyName(Ref ref, String groupName) {
  final proxyName = ref.watch(getProxyNameProvider(groupName));
  final group = ref.watch(
    groupsProvider.select(
      (state) => state.getGroup(groupName),
    ),
  );
  return group?.getCurrentSelectedName(proxyName ?? '');
}

@riverpod
String getProxyDesc(Ref ref, Proxy proxy) {
  final groupTypeNamesList = GroupType.values.map((e) => e.name).toList();
  if (!groupTypeNamesList.contains(proxy.type)) {
    return proxy.serverDescription ?? proxy.type;
  } else {
    final groups = ref.watch(groupsProvider);
    final index = groups.indexWhere((element) => element.name == proxy.name);
    if (index == -1) return proxy.serverDescription ?? proxy.type;
    // Custom description from YAML wins over the group type when present.
    // Otherwise show the currently selected proxy instead of "Type(selection)".
    final customDesc = globalState.groupDescriptions.value[proxy.name];
    if (customDesc != null && customDesc.isNotEmpty) {
      return customDesc;
    }
    final state = ref.watch(getProxyCardStateProvider(proxy.name));
    return state.proxyName.isNotEmpty
        ? state.proxyName
        : (proxy.serverDescription ?? proxy.type);
  }
}

@riverpod
class ProfileOverrideState extends _$ProfileOverrideState {
  @override
  ProfileOverrideStateModel build() => const ProfileOverrideStateModel(
      selectedRules: {},
    );

  void updateState(
    ProfileOverrideStateModel? Function(ProfileOverrideStateModel state)
        builder,
  ) {
    final value = builder(state);
    if (value == null) {
      return;
    }
    state = value;
  }
}

@riverpod
OverrideData? getProfileOverrideData(Ref ref, String profileId) => ref.watch(
    profilesProvider.select(
      (state) => state.getProfile(profileId)?.overrideData,
    ),
  );

@riverpod
VM2? layoutChange(Ref ref) {
  final viewWidth = ref.watch(viewWidthProvider);
  final textScale =
      ref.watch(themeSettingProvider.select((state) => state.textScale));
  return VM2(
    a: viewWidth,
    b: textScale,
  );
}

@riverpod
VM2<int, bool> checkIp(Ref ref) {
  final checkIpNum = ref.watch(checkIpNumProvider);
  final containsDetection = ref.watch(
    dashboardStateProvider.select(
      (state) =>
          state.dashboardWidgets.contains(DashboardWidget.networkDetection),
    ),
  );
  // The "new look" hero also shows the exit IP, so it needs the same re-check on
  // proxy change.
  final newDashboard = ref.watch(newDashboardEnabledProvider);
  return VM2(
    a: checkIpNum,
    b: containsDetection || newDashboard,
  );
}

@riverpod
ColorScheme genColorScheme(
  Ref ref,
  Brightness brightness, {
  Color? color,
  bool ignoreConfig = false,
}) {
  final vm2 = ref.watch(
    themeSettingProvider.select(
      (state) => VM2(
        a: state.primaryColor,
        b: state.schemeVariant,
      ),
    ),
  );
  if (color == null && (ignoreConfig == true || vm2.a == null)) {
    // if (globalState.corePalette != null) {
    //   return globalState.corePalette!.toColorScheme(brightness: brightness);
    // }
    return ColorScheme.fromSeed(
      seedColor: globalState.corePalette
              ?.toColorScheme(brightness: brightness)
              .primary ??
          globalState.accentColor,
      brightness: brightness,
      dynamicSchemeVariant: vm2.b,
    );
  }
  return ColorScheme.fromSeed(
    seedColor: color ?? Color(vm2.a!),
    brightness: brightness,
    dynamicSchemeVariant: vm2.b,
  );
}

@riverpod
VM3<String?, String?, Dns?> needSetup(Ref ref) {
  final profileId = ref.watch(currentProfileIdProvider);
  final content = ref.watch(
      scriptStateProvider.select((state) => state.currentScript?.content));
  final overrideDns = ref.watch(overrideDnsProvider);
  final dns = overrideDns == true
      ? ref.watch(patchClashConfigProvider.select(
          (state) => state.dns,
        ))
      : null;
  return VM3(
    a: profileId,
    b: content,
    c: dns,
  );
}

@riverpod
VM2<bool, bool> autoSetSystemDnsState(Ref ref) {
  final isStart = ref.watch(runTimeProvider.select((state) => state != null));
  final realTunEnable = ref.watch(realTunEnableProvider);
  final autoSetSystemDns = ref.watch(
    networkSettingProvider.select(
      (state) => state.autoSetSystemDns,
    ),
  );
  return VM2(
    a: isStart ? realTunEnable : false,
    b: autoSetSystemDns,
  );
}
