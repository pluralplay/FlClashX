// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../action.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CommonAction)
final commonActionProvider = CommonActionProvider._();

final class CommonActionProvider extends $NotifierProvider<CommonAction, void> {
  CommonActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commonActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commonActionHash();

  @$internal
  @override
  CommonAction create() => CommonAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$commonActionHash() => r'05946f3026407a5fcf12644605937f6e88681536';

abstract class _$CommonAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ManagedSettingsAction)
final managedSettingsActionProvider = ManagedSettingsActionProvider._();

final class ManagedSettingsActionProvider
    extends $NotifierProvider<ManagedSettingsAction, void> {
  ManagedSettingsActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'managedSettingsActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$managedSettingsActionHash();

  @$internal
  @override
  ManagedSettingsAction create() => ManagedSettingsAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$managedSettingsActionHash() =>
    r'276a17ac316848bd3b1f6762c1bb8136f401eca0';

abstract class _$ManagedSettingsAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Lands once per update of, or switch to, a profile; edits in between stay.

@ProviderFor(ProfileHeadersAction)
final profileHeadersActionProvider = ProfileHeadersActionProvider._();

/// Lands once per update of, or switch to, a profile; edits in between stay.
final class ProfileHeadersActionProvider
    extends $NotifierProvider<ProfileHeadersAction, void> {
  /// Lands once per update of, or switch to, a profile; edits in between stay.
  ProfileHeadersActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileHeadersActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileHeadersActionHash();

  @$internal
  @override
  ProfileHeadersAction create() => ProfileHeadersAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$profileHeadersActionHash() =>
    r'6de99f935c02a1a096e700353a496bedc4ad716f';

/// Lands once per update of, or switch to, a profile; edits in between stay.

abstract class _$ProfileHeadersAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The current subscription's or file's config keys become the app's
/// settings on every update and switch (see [syncProfileSettings]); a custom
/// profile has no file and a scripted one may rewrite the keys, so both skip.

@ProviderFor(ProfileSettingsAction)
final profileSettingsActionProvider = ProfileSettingsActionProvider._();

/// The current subscription's or file's config keys become the app's
/// settings on every update and switch (see [syncProfileSettings]); a custom
/// profile has no file and a scripted one may rewrite the keys, so both skip.
final class ProfileSettingsActionProvider
    extends $NotifierProvider<ProfileSettingsAction, void> {
  /// The current subscription's or file's config keys become the app's
  /// settings on every update and switch (see [syncProfileSettings]); a custom
  /// profile has no file and a scripted one may rewrite the keys, so both skip.
  ProfileSettingsActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileSettingsActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileSettingsActionHash();

  @$internal
  @override
  ProfileSettingsAction create() => ProfileSettingsAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$profileSettingsActionHash() =>
    r'4b184684e26874e785fadeb1b3408f3016a07b89';

/// The current subscription's or file's config keys become the app's
/// settings on every update and switch (see [syncProfileSettings]); a custom
/// profile has no file and a scripted one may rewrite the keys, so both skip.

abstract class _$ProfileSettingsAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(SetupAction)
final setupActionProvider = SetupActionProvider._();

final class SetupActionProvider extends $NotifierProvider<SetupAction, void> {
  SetupActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setupActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setupActionHash();

  @$internal
  @override
  SetupAction create() => SetupAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$setupActionHash() => r'572ac3daf36bd909c58126b257efad8fca3ea6e8';

abstract class _$SetupAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(BackupAction)
final backupActionProvider = BackupActionProvider._();

final class BackupActionProvider extends $NotifierProvider<BackupAction, void> {
  BackupActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupActionHash();

  @$internal
  @override
  BackupAction create() => BackupAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$backupActionHash() => r'c0c2cd46ec5b246076902a297c356fde2ece3577';

abstract class _$BackupAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(CoreAction)
final coreActionProvider = CoreActionProvider._();

final class CoreActionProvider extends $NotifierProvider<CoreAction, void> {
  CoreActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coreActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coreActionHash();

  @$internal
  @override
  CoreAction create() => CoreAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$coreActionHash() => r'8b11b297dabd4dc087d9466fa02381424170781c';

abstract class _$CoreAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(SystemAction)
final systemActionProvider = SystemActionProvider._();

final class SystemActionProvider extends $NotifierProvider<SystemAction, void> {
  SystemActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'systemActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$systemActionHash();

  @$internal
  @override
  SystemAction create() => SystemAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$systemActionHash() => r'fa818fa8e84de54ed89609febe147feded618ca9';

abstract class _$SystemAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(StoreAction)
final storeActionProvider = StoreActionProvider._();

final class StoreActionProvider extends $NotifierProvider<StoreAction, void> {
  StoreActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storeActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storeActionHash();

  @$internal
  @override
  StoreAction create() => StoreAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$storeActionHash() => r'a41384264ecb60ae26a4169e565c8623bcdf2767';

abstract class _$StoreAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ThemeAction)
final themeActionProvider = ThemeActionProvider._();

final class ThemeActionProvider extends $NotifierProvider<ThemeAction, void> {
  ThemeActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeActionHash();

  @$internal
  @override
  ThemeAction create() => ThemeAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$themeActionHash() => r'f33484cafdb1c8dec472f86f03ed4136c12770a0';

abstract class _$ThemeAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ProxiesAction)
final proxiesActionProvider = ProxiesActionProvider._();

final class ProxiesActionProvider
    extends $NotifierProvider<ProxiesAction, void> {
  ProxiesActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proxiesActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proxiesActionHash();

  @$internal
  @override
  ProxiesAction create() => ProxiesAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$proxiesActionHash() => r'a3bbe3ff08fba96f24d8e1ba3df18a1ee8153b78';

abstract class _$ProxiesAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ProfilesAction)
final profilesActionProvider = ProfilesActionProvider._();

final class ProfilesActionProvider
    extends $NotifierProvider<ProfilesAction, void> {
  ProfilesActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profilesActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profilesActionHash();

  @$internal
  @override
  ProfilesAction create() => ProfilesAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$profilesActionHash() => r'6d03963624aca0d3ce3649231195507486136d3c';

abstract class _$ProfilesAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ScriptsAction)
final scriptsActionProvider = ScriptsActionProvider._();

final class ScriptsActionProvider
    extends $NotifierProvider<ScriptsAction, void> {
  ScriptsActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scriptsActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scriptsActionHash();

  @$internal
  @override
  ScriptsAction create() => ScriptsAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$scriptsActionHash() => r'f4ec8e120ae8163e4b7bb78636c30d75264de87d';

abstract class _$ScriptsAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ClashProvidersAction)
final clashProvidersActionProvider = ClashProvidersActionProvider._();

final class ClashProvidersActionProvider
    extends $NotifierProvider<ClashProvidersAction, void> {
  ClashProvidersActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clashProvidersActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clashProvidersActionHash();

  @$internal
  @override
  ClashProvidersAction create() => ClashProvidersAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$clashProvidersActionHash() =>
    r'f0d06cb220c213d16a84f78d8eaab7c98794919b';

abstract class _$ClashProvidersAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(IconSetsAction)
final iconSetsActionProvider = IconSetsActionProvider._();

final class IconSetsActionProvider
    extends $NotifierProvider<IconSetsAction, void> {
  IconSetsActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'iconSetsActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$iconSetsActionHash();

  @$internal
  @override
  IconSetsAction create() => IconSetsAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$iconSetsActionHash() => r'2568fa51c9ac71e3f0b5c990db458ddc7337ee88';

abstract class _$IconSetsAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(GeoResourceAction)
final geoResourceActionProvider = GeoResourceActionProvider._();

final class GeoResourceActionProvider
    extends $NotifierProvider<GeoResourceAction, void> {
  GeoResourceActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'geoResourceActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$geoResourceActionHash();

  @$internal
  @override
  GeoResourceAction create() => GeoResourceAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$geoResourceActionHash() => r'0c51366685262ad99f7965bc998aee87690ee1b6';

abstract class _$GeoResourceAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ResourcesAction)
final resourcesActionProvider = ResourcesActionProvider._();

final class ResourcesActionProvider
    extends $NotifierProvider<ResourcesAction, void> {
  ResourcesActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resourcesActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resourcesActionHash();

  @$internal
  @override
  ResourcesAction create() => ResourcesAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$resourcesActionHash() => r'4789f340b60eadbbc3bc124f296bbeaa35121ba6';

abstract class _$ResourcesAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(UpdatingAction)
final updatingActionProvider = UpdatingActionProvider._();

final class UpdatingActionProvider
    extends $NotifierProvider<UpdatingAction, void> {
  UpdatingActionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updatingActionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updatingActionHash();

  @$internal
  @override
  UpdatingAction create() => UpdatingAction();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$updatingActionHash() => r'f98e26e80cc700f84e880393d0b280a08c37789b';

abstract class _$UpdatingAction extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
