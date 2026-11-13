part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  /// The cycling hotkey, which has nowhere to ask before taking the mode
  /// over from the subscription.
  void updateMode() {
    ref
        .read(managedSettingsActionProvider.notifier)
        .takeOverIfLocked('clash.mode');
    final modes = ref.read(availableModesProvider);
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = modes.indexWhere((item) => item == state.mode);
      final nextIndex = index + 1 > modes.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: modes[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  /// The provider's update manifest for this channel, when its header names
  /// one; it then stands in for GitHub as the update source.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    final headers = ref.read(currentProfileProvider)?.headers;
    final manifestUrl = globalState.isPre
        ? headers?.preUpdateManifestUrl
        : headers?.updateManifestUrl;
    if (manifestUrl == null) {
      return request.checkForUpdate();
    }
    try {
      return await fetchManifestUpdate(
        request.dio,
        Uri.parse(manifestUrl),
        currentVersion: globalState.packageInfo.displayVersion,
        pre: globalState.isPre,
      );
    } catch (error) {
      commonPrint.log(
        'update manifest failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await checkForUpdate();
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  Future<UpdatePlatform> _updatePlatform() async {
    try {
      return await resolveUpdatePlatform(
        exitApp: () => ref.read(systemActionProvider.notifier).handleExit(),
      );
    } catch (error) {
      commonPrint.log(
        'Update platform unresolved: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return const ManualUpdatePlatform();
    }
  }

  UpdateErrorKind? _updateInstallBlocker() {
    if (ref.read(safeModeProvider)) {
      return UpdateErrorKind.safeMode;
    }
    if (ref.read(setupActionProvider.notifier).isChangingRun) {
      return UpdateErrorKind.busy;
    }
    return null;
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final context = globalState.navigatorKey.currentContext!;
      final notes = _releaseSpan(
        context,
        data['tag_name'] as String,
        data['body'] as String?,
      );
      final platform = await _updatePlatform();
      final downloader = UpdateDownloader(
        root: () async =>
            Directory(join((await appPath.cacheDir.future).path, 'update')),
      );
      await dialogs.showCommonDialog<void>(
        child: UpdateDialog(
          notes: notes,
          onOpenReleasePage: () =>
              unawaited(launchUrl(releasePageOf(data, repository: repository))),
          onStopReminding: isUser
              ? null
              : () => ref
                    .read(appSettingProvider.notifier)
                    .update((state) => state.copyWith(autoCheckUpdate: false)),
          createController: () {
            final controller = UpdateController(
              release: data,
              platform: platform,
              downloader: downloader,
              repository: repository,
              pre: globalState.isPre,
              manifest: data['_isManifest'] == true,
              installBlocker: _updateInstallBlocker,
            );
            app?.onPackageInstallStatus = controller.onInstallStatus;
            return controller;
          },
        ),
      );
    } else if (isUser) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
