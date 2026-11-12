part of '../action.dart';

typedef ProfileHeaderSettings = ({
  ViewRequest? view,
  List<DashboardWidget>? widgets,
  Set<String>? switches,
  bool globalModeAllowed,
  bool hideIp,
  bool noVibration,
});

ProfileHeaderSettings profileHeaderSettingsOf(Profile? profile) {
  final headers = profile?.headers;
  return (
    view: headers?.view,
    widgets: headers?.dashboardWidgets,
    switches: headers?.appSwitches,
    globalModeAllowed: headers?.globalModeAllowed ?? true,
    hideIp: headers?.hideIp ?? false,
    noVibration: headers?.noVibration ?? false,
  );
}

String? profileHeadersUpdateOf(Profile? profile) => switch (profile) {
  null => null,
  final profile =>
    '${profile.id}@${profile.fileRevision.lastUpdateSeconds}'
        '#${_headersDigest(profile.providerHeaders)}',
};

String _headersDigest(Map<String, String> headers) => json.encode([
  for (final name in headers.keys.toList()..sort()) [name, headers[name]],
]).toMd5();

/// Lands once per update of, or switch to, a profile; edits in between stay.
@Riverpod(keepAlive: true)
class ProfileHeadersAction extends _$ProfileHeadersAction {
  int _generation = 0;

  @override
  void build() {
    ref.listen(
      currentProfileProvider.select(profileHeadersUpdateOf),
      (_, _) => _applyLater(),
    );
    _applyLater();
  }

  /// Settings may not change inside the flush that reported the profile, so
  /// the latest request is applied once that flush has ended.
  void _applyLater() {
    final generation = ++_generation;
    scheduleMicrotask(() {
      if (generation != _generation || !ref.mounted) {
        return;
      }
      final profile = ref.read(currentProfileProvider);
      final update = profileHeadersUpdateOf(profile);
      if (update == ref.read(appSettingProvider).appliedHeadersUpdate) {
        _adoptPanelSet(profileHeaderSettingsOf(profile));
        return;
      }
      apply(profileHeaderSettingsOf(profile));
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(appliedHeadersUpdate: update));
    });
  }

  void apply(ProfileHeaderSettings settings) {
    final owned = ref.read(appSettingProvider).ownedSettings;
    T? asked<T>(String key, T? value) => owned.contains(key) ? null : value;
    if (settings.view case final view?) {
      ref
          .read(proxiesStyleSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              type: asked('view.proxies.type', view.type) ?? state.type,
              sortType: asked('view.proxies.sort', view.sort) ?? state.sortType,
              layout: asked('view.proxies.layout', view.layout) ?? state.layout,
              iconStyle:
                  asked('view.proxies.icon', view.icon) ?? state.iconStyle,
              cardType: asked('view.proxies.card', view.card) ?? state.cardType,
            ),
          );
      if (view.touchesTheme) {
        final color = asked('view.app.color', view.color);
        ref
            .read(themeSettingProvider.notifier)
            .update(
              (state) => state.copyWith(
                style: asked('view.app.board', view.board) ?? state.style,
                themeMode:
                    asked('view.app.theme', view.themeMode) ?? state.themeMode,
                liquidGlass:
                    asked('view.app.glass', view.liquidGlass) ??
                    state.liquidGlass,
                primaryColor: color ?? state.primaryColor,
                primaryColors:
                    color == null || state.primaryColors.contains(color)
                    ? state.primaryColors
                    : [...state.primaryColors, color],
                colorStyle:
                    asked('view.app.color', view.colorStyle) ??
                    state.colorStyle,
                pureBlack:
                    asked('view.app.black', view.pureBlack) ?? state.pureBlack,
              ),
            );
      }
      if (view.touchesApp) {
        ref
            .read(appSettingProvider.notifier)
            .update(
              (state) => state.copyWith(
                floatingNavigationBar:
                    asked('view.app.navbar', view.floatingNavigationBar) ??
                    state.floatingNavigationBar,
                tabAnimation:
                    asked('view.app.tabs', view.tabAnimation) ??
                    state.tabAnimation,
              ),
            );
      }
    }
    if (settings.widgets case final widgets?) {
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              dashboardWidgets: widgets,
              dashboardWidgetsChosen: true,
            ),
          );
    }
    if (settings.switches case final switches?) {
      bool? said(String flag) => owned.contains(appSwitchSettings[flag])
          ? null
          : switches.contains(flag);
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              minimizeOnExit: said('minimize') ?? state.minimizeOnExit,
              autoLaunch: said('autorun') ?? state.autoLaunch,
              silentLaunch: said('shadowstart') ?? state.silentLaunch,
              autoRun: said('autostart') ?? state.autoRun,
              autoCheckUpdate: said('autoupdate') ?? state.autoCheckUpdate,
              openLogs: said('openlogs') ?? state.openLogs,
              closeConnections:
                  said('closeconnections') ?? state.closeConnections,
            ),
          );
    }
    _applySpecial(
      hideIpSetting,
      said: settings.hideIp,
      owned: owned,
      set: (state, on) => state.copyWith(hideIp: on),
    );
    _applySpecial(
      vibrationSetting,
      said: settings.noVibration,
      owned: owned,
      set: (state, on) => state.copyWith(vibration: !on),
    );
    if (!settings.globalModeAllowed &&
        ref.read(patchClashConfigProvider).mode == Mode.global) {
      ref.read(setupActionProvider.notifier).changeMode(Mode.rule);
    }
  }

  /// Settings saved before the panel's flags and cards were tracked: what the
  /// panel still sends, and the settings still read as it set, came from it.
  void _adoptPanelSet(ProfileHeaderSettings settings) {
    ref.read(appSettingProvider.notifier).update((state) {
      final adopted = {
        if (settings.hideIp && state.hideIp) hideIpSetting,
        if (settings.noVibration && !state.vibration) vibrationSetting,
      }.difference(state.ownedSettings);
      final widgets = settings.widgets;
      final cardsPicked =
          !state.dashboardWidgetsChosen &&
          widgets != null &&
          listEquals(state.dashboardWidgets, widgets);
      if (state.panelSetSettings.containsAll(adopted) && !cardsPicked) {
        return state;
      }
      return state.copyWith(
        panelSetSettings: {...state.panelSetSettings, ...adopted},
        dashboardWidgetsChosen: state.dashboardWidgetsChosen || cardsPicked,
      );
    });
  }

  /// A special flag sets its setting while the panel sends it, and puts the
  /// default back once the panel drops it, unless the user took it over.
  void _applySpecial(
    String key, {
    required bool said,
    required Set<String> owned,
    required AppSettingProps Function(AppSettingProps state, bool on) set,
  }) {
    ref.read(appSettingProvider.notifier).update((state) {
      final panelSet = state.panelSetSettings;
      if (said && !owned.contains(key)) {
        return set(state, true).copyWith(panelSetSettings: {...panelSet, key});
      }
      if (said || !panelSet.contains(key)) {
        return state;
      }
      final cleared = state.copyWith(
        panelSetSettings: {...panelSet}..remove(key),
      );
      return owned.contains(key) ? cleared : set(cleared, false);
    });
  }
}
