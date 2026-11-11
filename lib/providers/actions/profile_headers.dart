part of '../action.dart';

typedef ProfileHeaderSettings = ({
  ViewRequest? view,
  List<DashboardWidget>? widgets,
  Set<String>? switches,
  bool globalModeAllowed,
  bool hideIp,
});

ProfileHeaderSettings profileHeaderSettingsOf(Profile? profile) {
  final headers = profile?.headers;
  return (
    view: headers?.view,
    widgets: headers?.dashboardWidgets,
    switches: headers?.appSwitches,
    globalModeAllowed: headers?.globalModeAllowed ?? true,
    hideIp: headers?.hideIp ?? false,
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
          .update((state) => state.copyWith(dashboardWidgets: widgets));
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
    if (settings.hideIp && !owned.contains(hideIpSetting)) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(hideIp: true));
    }
    if (!settings.globalModeAllowed &&
        ref.read(patchClashConfigProvider).mode == Mode.global) {
      ref.read(setupActionProvider.notifier).changeMode(Mode.rule);
    }
  }
}
