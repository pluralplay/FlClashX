part of '../action.dart';

typedef ProfileHeaderSettings = ({
  ViewRequest? view,
  List<DashboardWidget>? widgets,
  bool widgetsDenied,
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
    widgetsDenied: headers?.widgetEditingDenied ?? false,
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

  /// A header holds a setting only while the selected profile sends it; the
  /// user's own value waits in [AppSettingProps.headerBackup] meanwhile.
  void apply(ProfileHeaderSettings settings) {
    final owned = ref.read(appSettingProvider).ownedSettings;
    final backup = {...ref.read(appSettingProvider).headerBackup};
    T pick<T>(String field, String key, T? said, T current, _Codec<T> codec) {
      final saved = codec.decode(backup[field]);
      if (saved == null || owned.contains(key)) {
        backup.remove(field);
      }
      if (owned.contains(key)) {
        return current;
      }
      if (said != null) {
        if (saved == null) {
          backup[field] = codec.encode(current);
        }
        return said;
      }
      if (saved != null) {
        backup.remove(field);
        return saved.$1;
      }
      return current;
    }

    final view = settings.view;
    ref
        .read(proxiesStyleSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            type: pick(
              'proxies.type',
              'view.proxies.type',
              view?.type,
              state.type,
              _Codec.of(ProxiesType.values),
            ),
            sortType: pick(
              'proxies.sort',
              'view.proxies.sort',
              view?.sort,
              state.sortType,
              _Codec.of(ProxiesSortType.values),
            ),
            layout: pick(
              'proxies.layout',
              'view.proxies.layout',
              view?.layout,
              state.layout,
              _Codec.of(ProxiesLayout.values),
            ),
            iconStyle: pick(
              'proxies.icon',
              'view.proxies.icon',
              view?.icon,
              state.iconStyle,
              _Codec.of(ProxiesIconStyle.values),
            ),
            cardType: pick(
              'proxies.card',
              'view.proxies.card',
              view?.card,
              state.cardType,
              _Codec.of(ProxyCardType.values),
            ),
            hideTimeoutProxies: pick(
              'proxies.hidetimeout',
              'view.proxies.hidetimeout',
              view?.hideTimeout,
              state.hideTimeoutProxies,
              _Codec.value(),
            ),
          ),
        );
    final colorOwned = owned.contains('view.app.color');
    ref
        .read(themeSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            themeMode: pick(
              'theme.mode',
              'view.app.theme',
              view?.themeMode,
              state.themeMode,
              _Codec.of(ThemeMode.values),
            ),
            liquidGlass: pick(
              'theme.glass',
              'view.app.glass',
              view?.liquidGlass,
              state.liquidGlass,
              _Codec.of(LiquidGlassMode.values),
            ),
            primaryColor: pick<int?>(
              'theme.color',
              'view.app.color',
              view?.color,
              state.primaryColor,
              _Codec.value(),
            ),
            primaryColors: _swatchesFor(
              backup,
              state.primaryColors,
              colorOwned ? null : view?.color,
              keep: colorOwned,
            ),
            colorStyle: pick(
              'theme.style',
              'view.app.color',
              view?.colorStyle,
              state.colorStyle,
              _Codec.of(ColorStyle.values),
            ),
            pureBlack: pick(
              'theme.black',
              'view.app.black',
              view?.pureBlack,
              state.pureBlack,
              _Codec.value(),
            ),
          ),
        );
    final switches = settings.switches;
    final widgets = settings.widgets;
    ref.read(appSettingProvider.notifier).update((state) {
      bool flag(String name, bool current) => pick(
        'switch.$name',
        appSwitchSettings[name]!,
        switches?.contains(name),
        current,
        _Codec.value(),
      );
      _Cards cards = (state.dashboardWidgets, state.dashboardWidgetsChosen);
      if (settings.widgetsDenied && widgets != null) {
        if (_cardsCodec.decode(backup[_cardsField]) == null) {
          backup[_cardsField] = _cardsCodec.encode(cards);
        }
        backup[_cardsForcedField] = true;
        cards = (widgets, true);
      } else {
        // Cards denywidgets forced on come back even when the user owns them.
        if (backup.remove(_cardsForcedField) == true) {
          cards = _cardsCodec.decode(backup.remove(_cardsField))?.$1 ?? cards;
        }
        cards = pick<_Cards>(
          _cardsField,
          dashboardWidgetsSetting,
          widgets == null ? null : (widgets, true),
          cards,
          _cardsCodec,
        );
      }
      var next = state.copyWith(
        floatingNavigationBar: pick(
          'app.navbar',
          'view.app.navbar',
          view?.floatingNavigationBar,
          state.floatingNavigationBar,
          _Codec.value(),
        ),
        tabAnimation: pick(
          'app.tabs',
          'view.app.tabs',
          view?.tabAnimation,
          state.tabAnimation,
          _Codec.of(TabAnimation.values),
        ),
        dashboardWidgets: cards.$1,
        dashboardWidgetsChosen: cards.$2,
        minimizeOnExit: flag('minimize', state.minimizeOnExit),
        autoLaunch: flag('autorun', state.autoLaunch),
        silentLaunch: flag('shadowstart', state.silentLaunch),
        autoRun: flag('autostart', state.autoRun),
        autoCheckUpdate: flag('autoupdate', state.autoCheckUpdate),
        openLogs: flag('openlogs', state.openLogs),
        closeConnections: flag('closeconnections', state.closeConnections),
      );
      next = _special(
        next,
        hideIpSetting,
        said: settings.hideIp,
        owned: owned,
        backup: backup,
        on: true,
        read: (state) => state.hideIp,
        write: (state, value) => state.copyWith(hideIp: value),
      );
      next = _special(
        next,
        vibrationSetting,
        said: settings.noVibration,
        owned: owned,
        backup: backup,
        on: false,
        read: (state) => state.vibration,
        write: (state, value) => state.copyWith(vibration: value),
      );
      return next.copyWith(headerBackup: backup);
    });
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

  /// A special flag holds [on] while the panel sends it. A flag recorded in
  /// [AppSettingProps.panelSetSettings] before the user's value was kept
  /// falls back to the opposite of [on].
  AppSettingProps _special(
    AppSettingProps state,
    String key, {
    required bool said,
    required Set<String> owned,
    required Map<String, Object?> backup,
    required bool on,
    required bool Function(AppSettingProps state) read,
    required AppSettingProps Function(AppSettingProps state, bool value) write,
  }) {
    final field = 'special.$key';
    final panelSet = state.panelSetSettings;
    if (backup[field] is! bool) {
      backup.remove(field);
    }
    if (owned.contains(key)) {
      backup.remove(field);
      if (said || !panelSet.contains(key)) {
        return state;
      }
      return state.copyWith(panelSetSettings: {...panelSet}..remove(key));
    }
    if (said) {
      // A flag marked before backups existed was the panel's, not the user's.
      backup.putIfAbsent(
        field,
        () => panelSet.contains(key) ? !on : read(state),
      );
      return write(state, on).copyWith(panelSetSettings: {...panelSet, key});
    }
    if (!panelSet.contains(key) && !backup.containsKey(field)) {
      return state;
    }
    final saved = backup.remove(field);
    return write(
      state.copyWith(panelSetSettings: {...panelSet}..remove(key)),
      saved is bool ? saved : !on,
    );
  }
}

/// The swatch a panel's colour adds stays on offer only while that colour
/// does: the ones it added are recorded so a switch away takes them back.
List<int> _swatchesFor(
  Map<String, Object?> backup,
  List<int> swatches,
  int? color, {
  required bool keep,
}) {
  const field = 'theme.swatches';
  final saved = backup[field];
  final added = saved is List ? saved.whereType<int>().toList() : <int>[];
  if (keep) {
    backup.remove(field);
    return swatches;
  }
  final next = [
    for (final swatch in swatches)
      if (swatch == color || !added.contains(swatch)) swatch,
  ];
  final ours =
      color != null && (added.contains(color) || !next.contains(color));
  if (color != null && !next.contains(color)) {
    next.add(color);
  }
  if (ours) {
    backup[field] = [color];
  } else {
    backup.remove(field);
  }
  return next;
}

typedef _Cards = (List<DashboardWidget>, bool);

const _cardsField = 'app.widgets';
const _cardsForcedField = 'app.widgets.forced';

final _cardsCodec = _Codec<_Cards>(
  (cards) => {
    'cards': [for (final card in cards.$1) card.name],
    'chosen': cards.$2,
  },
  (saved) => switch (saved) {
    {'cards': final List<Object?> names, 'chosen': final bool chosen} => (
      (
        [for (final name in names) ?DashboardWidget.values.asNameMap()[name]],
        chosen,
      ),
    ),
    _ => null,
  },
);

/// How a setting's value is kept in [AppSettingProps.headerBackup]; a saved
/// entry it cannot read decodes to null and counts as absent.
class _Codec<T> {
  const _Codec(this.encode, this.decode);

  factory _Codec.value() =>
      _Codec<T>((value) => value, (saved) => saved is T ? (saved,) : null);

  factory _Codec.of(List<T> values) {
    final byName = {for (final value in values) (value as Enum).name: value};
    return _Codec<T>(
      (value) => (value as Enum).name,
      (saved) => switch (byName[saved]) {
        final value? => (value,),
        null => null,
      },
    );
  }

  final Object? Function(T value) encode;
  final (T,)? Function(Object? saved) decode;
}

/// The backup fields the managed [key] speaks for.
Set<String> _backupFieldsOf(String key) => switch (key) {
  'view.proxies.type' => {'proxies.type'},
  'view.proxies.sort' => {'proxies.sort'},
  'view.proxies.layout' => {'proxies.layout'},
  'view.proxies.icon' => {'proxies.icon'},
  'view.proxies.card' => {'proxies.card'},
  'view.proxies.hidetimeout' => {'proxies.hidetimeout'},
  'view.app.theme' => {'theme.mode'},
  'view.app.glass' => {'theme.glass'},
  'view.app.color' => {'theme.color', 'theme.style', 'theme.swatches'},
  'view.app.black' => {'theme.black'},
  'view.app.navbar' => {'app.navbar'},
  'view.app.tabs' => {'app.tabs'},
  dashboardWidgetsSetting => {_cardsField},
  hideIpSetting || vibrationSetting => {'special.$key'},
  _ => {
    for (final MapEntry(key: flag, value: setting) in appSwitchSettings.entries)
      if (setting == key) 'switch.$flag',
  },
};

/// [backup] without what it kept for [key], for a setting the user takes
/// over: their choice from then on is theirs, not the one before the panel.
Map<String, Object?> headerBackupWithout(
  Map<String, Object?> backup,
  String key,
) {
  if (key == dashboardWidgetsSetting && backup[_cardsForcedField] == true) {
    return backup;
  }
  final fields = _backupFieldsOf(key);
  return {
    for (final MapEntry(:key, :value) in backup.entries)
      if (!fields.contains(key)) key: value,
  };
}
