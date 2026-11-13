part of '../state.dart';

@riverpod
ProfilesState profilesState(Ref ref) {
  final currentProfileId = ref.watch(currentProfileIdProvider);
  final profiles = ref.watch(profilesProvider);
  return ProfilesState(profiles: profiles, currentProfileId: currentProfileId);
}

@riverpod
Profile? currentProfile(Ref ref) {
  final profileId = ref.watch(currentProfileIdProvider);
  return ref.watch(
    profilesProvider.select((state) => state.getProfile(profileId)),
  );
}

@riverpod
List<ProfileOffer> profileOffers(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  final now = DateTime.now();
  if (nextOfferChange(profile, now) case final at?) {
    // A second past the threshold, where the day count has dropped to it.
    final timer = Timer(
      at.difference(now) + const Duration(seconds: 1),
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
  }
  return visibleOffersOf(profile, now: now);
}

@riverpod
bool globalModeAllowed(Ref ref) {
  return ref.watch(
    currentProfileProvider.select(
      (profile) => profile?.headers.globalModeAllowed ?? true,
    ),
  );
}

@riverpod
bool androidSecure(Ref ref) {
  return system.isAndroid &&
      ref.watch(
        currentProfileProvider.select(
          (profile) => profile?.headers.androidSecure ?? false,
        ),
      );
}

@riverpod
PanelBackground? panelBackground(Ref ref) {
  return ref.watch(
    currentProfileProvider.select((profile) => profile?.headers.background),
  );
}

/// The backdrop picture from the disk cache, fetched once per url and
/// served from there afterwards, offline included. A fetch that fails, as one
/// does while a profile switch restarts the Core's listener, is retried.
@riverpod
Future<PanelBackdropImage?> panelBackdropImage(Ref ref) async {
  final background = ref.watch(panelBackgroundProvider);
  if (background == null) {
    return null;
  }
  try {
    final file = await DefaultCacheManager().getSingleFile(background.url);
    final side = _screenSide();
    final ImageProvider image = side == null
        ? FileImage(file)
        : ResizeImage(
            FileImage(file),
            width: side,
            height: side,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          );
    return (image: image, animated: await _isAnimated(file.path));
  } catch (error) {
    commonPrint.log('backdrop ${background.url} unavailable: $error');
    rethrow;
  }
}

typedef PanelBackdropImage = ({ImageProvider image, bool animated});

/// A backdrop covering the window never needs more than the screen's long side.
int? _screenSide() {
  final side = ui
      .PlatformDispatcher
      .instance
      .implicitView
      ?.display
      .size
      .longestSide
      .ceil();
  return side == null || side <= 0 ? null : side;
}

Future<bool> _isAnimated(String path) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final animated = codec.frameCount > 1;
    codec.dispose();
    return animated;
  } catch (_) {
    return false;
  }
}

/// Where the panel's logo lies on disk, kept as its backdrop is so it shows
/// at launch without the network.
@riverpod
Future<String?> panelLogoPath(Ref ref, String url) async {
  try {
    return (await DefaultCacheManager().getSingleFile(url)).path;
  } catch (error) {
    commonPrint.log('logo $url unavailable: $error');
    rethrow;
  }
}

@riverpod
bool widgetEditingDenied(Ref ref) {
  return ref.watch(
    currentProfileProvider.select(
      (profile) => profile?.headers.widgetEditingDenied ?? false,
    ),
  );
}

/// The outbound modes the current panel leaves on offer.
@riverpod
List<Mode> availableModes(Ref ref) {
  final globalAllowed = ref.watch(globalModeAllowedProvider);
  return [
    for (final mode in Mode.values)
      if (globalAllowed || mode != Mode.global) mode,
  ];
}

@riverpod
String? announcement(Ref ref) {
  return ref.watch(
    currentProfileProvider.select((profile) => profile?.announcement),
  );
}

@riverpod
Profile? profile(Ref ref, int? profileId) {
  return ref.watch(
    profilesProvider.select((state) => state.getProfile(profileId)),
  );
}

@riverpod
ExtendType extendType(Ref ref, int? profileId) {
  return ref.watch(
    profileProvider(
      profileId,
    ).select((state) => state?.extendType ?? ExtendType.standard),
  );
}

@riverpod
Future<ClashConfig> clashConfig(Ref ref, int profileId) async {
  final type = ref.read(profileProvider(profileId))?.type;
  if (type == ProfileType.custom) {
    return const ClashConfig();
  }
  final outbounds = await ref
      .read(coreHandlerProvider)
      .getProfileOutbounds(profileId);
  return clashConfigTask(outbounds);
}

@riverpod
Future<SetupState> setupState(Ref ref, int? profileId) async {
  final profile = ref.watch(profileProvider(profileId));
  final scriptId = profile?.scriptId;
  final profileLastUpdateDate = profile?.lastUpdateDate?.millisecondsSinceEpoch;
  final profileType = profile?.type ?? ProfileType.file;
  final extendType = profile?.extendType ?? ExtendType.standard;
  final overrides = profileType == ProfileType.custom
      ? ref.watch(
          patchClashConfigProvider.select(
            (state) => (profile?.overrides ?? const ProfileOverrides())
                .overAppTun(state.tunOverride, state.tunOverrideKeys),
          ),
        )
      : ref.watch(
          patchClashConfigProvider.select(
            (state) => ProfileOverrides(
              dns: state.dns,
              dnsOverrideKeys: state.dnsOverrideKeys.intersection(
                DnsOverrideKey.normalProfileKeys,
              ),
              tun: state.tunOverride,
              tunOverrideKeys: state.tunOverrideKeys,
            ),
          ),
        );
  final allProfileProviders = ref.watch(profileProvidersProvider);
  final proxyChains = profileId == null || profileType == ProfileType.custom
      ? null
      : watchEnabledProxyChains(ref, profileId);
  List<ProxyGroup> proxyGroups = [];
  List<Rule> rules = [];
  List<Rule> addedRules = [];
  List<ClashProvider> clashProviders = [];
  Map<String, int> profileProviders = const {};
  List<CustomProxy> appProxies = [];
  Map<int, String> proxyDialers = const {};
  Script? script;
  if (profileId != null) {
    if (profileType == ProfileType.custom) {
      rules = await database.rulesDao.queryProfileRules(profileId).get();
      proxyGroups = await database.proxyGroupsDao.query(profileId).get();
      clashProviders = await database.clashProvidersDao.query().get();
      profileProviders = allProfileProviders;
      appProxies = await database.customProxiesDao.query().get();
      proxyDialers = {
        for (final dialer
            in await database.proxyDialersDao.query(profileId).get())
          dialer.proxyId: dialer.target,
      };
    } else if (extendType == ExtendType.standard) {
      addedRules = await database.rulesDao.queryAddedRules(profileId).get();
    } else if (extendType == ExtendType.script) {
      script = scriptId == null
          ? null
          : await database.scriptsDao.get(scriptId).getSingleOrNull();
    }
  }
  return SetupState(
    clashProviders: clashProviders,
    profileProviders: profileProviders,
    appProxies: appProxies,
    proxyDialers: proxyDialers,
    rules: rules,
    proxyGroups: proxyGroups,
    profileId: profileId,
    profileLastUpdateDate: profileLastUpdateDate,
    profileType: profileType,
    extendType: extendType,
    addedRules: addedRules,
    script: script,
    overrides: overrides,
    matchTarget:
        profileType != ProfileType.custom && extendType == ExtendType.standard
        ? profile?.matchTarget
        : null,
    proxyChains: await proxyChains ?? const [],
  );
}

/// Subscription profiles double as proxy providers for custom profiles.
@riverpod
Map<String, int> profileProviders(Ref ref) {
  final profiles = ref.watch(profilesProvider);
  return {
    for (final profile in profiles)
      if (profile.type != ProfileType.custom) profile.realLabel: profile.id,
  };
}
