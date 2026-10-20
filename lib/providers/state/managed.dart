part of '../state.dart';

@Riverpod(keepAlive: true)
class ManagedClashKeys extends _$ManagedClashKeys {
  @override
  Set<String> build() => const {};

  void set(Set<String> keys) {
    if (!const SetEquality<String>().equals(keys, state)) {
      state = keys;
    }
  }
}

/// Every setting the current subscription speaks for.
@riverpod
Set<String> managedSettings(Ref ref) {
  final switches = ref.watch(
    currentProfileProvider.select((profile) => profile?.headers.appSwitches),
  );
  final view = ref.watch(
    currentProfileProvider.select((profile) => profile?.headers.view),
  );
  return {
    if (switches != null) ...appSwitchSettings.values,
    ...managedViewKeysOf(view),
    ...ref.watch(managedClashKeysProvider),
  };
}

@riverpod
bool settingOwned(Ref ref, String key) => ref.watch(
  appSettingProvider.select((state) => state.ownedSettings.contains(key)),
);

@riverpod
bool settingLocked(Ref ref, String key) =>
    ref.watch(managedSettingsProvider.select((keys) => keys.contains(key))) &&
    !ref.watch(settingOwnedProvider(key));

@riverpod
bool settingReleasable(Ref ref, String key) =>
    ref.watch(managedSettingsProvider.select((keys) => keys.contains(key))) &&
    ref.watch(settingOwnedProvider(key));
