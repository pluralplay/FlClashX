part of '../action.dart';

typedef ProfileSettingsSource = ({
  int? id,
  DateTime? updatedAt,
  ProfileType? type,
  ExtendType? extendType,
});

ProfileSettingsSource profileSettingsSourceOf(Profile? profile) => (
  id: profile?.id,
  updatedAt: profile?.lastUpdateDate,
  type: profile?.type,
  extendType: profile?.extendType,
);

/// The current subscription's or file's config keys become the app's
/// settings on every update and switch (see [syncProfileSettings]); a custom
/// profile has no file and a scripted one may rewrite the keys, so both skip.
@Riverpod(keepAlive: true)
class ProfileSettingsAction extends _$ProfileSettingsAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  int _generation = 0;

  /// What the last synced file named: only those keys fall back to the app
  /// default when the next file leaves them out, so a value the user set
  /// for a key no file names stays.
  Set<String> _named = const {};

  @override
  void build() {
    ref.listen(
      currentProfileProvider.select(profileSettingsSourceOf),
      (_, next) => scheduleMicrotask(() => unawaited(apply(next))),
    );
    scheduleMicrotask(
      () => unawaited(
        apply(profileSettingsSourceOf(ref.read(currentProfileProvider))),
      ),
    );
  }

  Future<void> apply(ProfileSettingsSource source) async {
    final id = source.id;
    final generation = ++_generation;
    if (id == null ||
        source.type == ProfileType.custom ||
        source.extendType == ExtendType.script) {
      _named = const {};
      ref.read(managedClashKeysProvider.notifier).set(const {});
      ref.read(globalOverrideProvider.notifier).value = false;
      return;
    }
    final ProfileBase base;
    try {
      base = (await _core.getProfileBase(id)).base;
    } catch (error) {
      commonPrint.log(
        'profile $id settings not read: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return;
    }
    if (generation != _generation) {
      return;
    }
    final modes = ref.read(availableModesProvider);
    final named = base.present.toSet();
    final kept = {
      ...ref.read(appSettingProvider).ownedSettings,
      for (final key in managedClashKeys)
        if (!named.contains(key) && !_named.contains(key)) clashSettingKey(key),
    };
    _named = named;
    ref
        .read(managedClashKeysProvider.notifier)
        .set(managedClashKeysOf(base.present));
    ref.read(globalOverrideProvider.notifier).value = base.globalOverride;
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => keepOwnedSettings(
            state,
            syncProfileSettings(state, base.config, base.present, modes: modes),
            kept,
          ),
        );
    if (!kept.contains(clashSettingKey('authentication'))) {
      ref
          .read(networkSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              authentication: authenticationFrom(base.config['authentication']),
            ),
          );
    }
  }
}
