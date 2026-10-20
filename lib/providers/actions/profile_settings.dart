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
    if (id == null ||
        source.type == ProfileType.custom ||
        source.extendType == ExtendType.script) {
      ref.read(managedClashKeysProvider.notifier).set(const {});
      return;
    }
    final generation = ++_generation;
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
    final owned = ref.read(appSettingProvider).ownedSettings;
    ref
        .read(managedClashKeysProvider.notifier)
        .set(managedClashKeysOf(base.present));
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => keepOwnedSettings(
            state,
            syncProfileSettings(state, base.config, base.present, modes: modes),
            owned,
          ),
        );
  }
}
