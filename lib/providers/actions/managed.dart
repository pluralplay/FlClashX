part of '../action.dart';

@Riverpod(keepAlive: true)
class ManagedSettingsAction extends _$ManagedSettingsAction {
  @override
  void build() {}

  void takeOver(String key) {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(ownedSettings: {...state.ownedSettings, key}),
        );
  }

  void release(String key) {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            ownedSettings: {...state.ownedSettings}..remove(key),
          ),
        );
    _reapply();
  }

  void releaseAll() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(ownedSettings: const {}));
    _reapply();
  }

  void _reapply() {
    final profile = ref.read(currentProfileProvider);
    ref
        .read(profileHeadersActionProvider.notifier)
        .apply(profileHeaderSettingsOf(profile));
    unawaited(
      ref
          .read(profileSettingsActionProvider.notifier)
          .apply(profileSettingsSourceOf(profile)),
    );
  }
}
