part of '../action.dart';

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  static const crashRestartLimit = 2;
  static const crashRestartWindow = Duration(seconds: 5);

  int _requestedRestartRevision = 0;
  Future<bool>? _restartOperation;
  int _failedRestarts = 0;
  DateTime? _crashRestartedAt;
  bool _restartingAfterCrash = false;
  String? _unansweredCrash;
  bool _answeringCrashes = false;

  @override
  void build() {}

  @protected
  DateTime currentTime() => DateTime.now();

  Future<void> initCore() async {
    final isInit = await _core.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      final res = await _core.init(version);
      commonPrint.log('init result: $res');
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      await ref.read(providersProvider.notifier).syncProviders();
    }
    _core.setHostActive(ref.read(appVisibleProvider));
    try {
      globalState.coreVersion = await _core.getCoreVersion();
    } catch (_) {}
  }

  Future<void> startCore() async {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    try {
      final result = await startLifecycle();
      await _applyLifecycleResult(result);
    } catch (error) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      dialogs.showNotifier(error.toString(), level: MessageLevel.error);
    }
  }

  @protected
  Future<CoreLifecycleResult> startLifecycle() {
    return _core.start();
  }

  @protected
  Future<CoreLifecycleResult> restartLifecycle() {
    return _core.restart();
  }

  // Nothing in lib/ calls CoreController.stop(); only close() (app exit)
  // supersedes a start/restart. statusFirst lets onCrash catch a crash
  // during initCore itself (it early-returns unless status is connected).
  Future<bool> _applyLifecycleResult(
    CoreLifecycleResult result, {
    bool statusFirst = false,
  }) async {
    if (result.outcome == CoreLifecycleOutcome.superseded) {
      return false;
    }
    if (statusFirst) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await initCore();
    } else {
      await initCore();
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    }
    return true;
  }

  Future<void> clearDnsCacheOnNetworkChange() async {
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    try {
      await _core.clearDnsCache();
    } catch (error) {
      commonPrint.log(
        'clearDnsCache error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<void> crash() async {
    await _core.crash();
  }

  /// Restarting a Core that keeps falling would only hide why it falls.
  Future<void> restartAfterCrash(String reason) async {
    final restartedAt = _crashRestartedAt;
    final restartFailed =
        _restartingAfterCrash ||
        (restartedAt != null &&
            currentTime().difference(restartedAt) < crashRestartWindow);
    _failedRestarts = restartFailed ? _failedRestarts + 1 : 0;
    _unansweredCrash = reason;
    if (_answeringCrashes) {
      return;
    }
    _answeringCrashes = true;
    try {
      for (
        var crash = _unansweredCrash;
        crash != null;
        crash = _unansweredCrash
      ) {
        _unansweredCrash = null;
        if (_failedRestarts >= crashRestartLimit) {
          commonPrint.log(
            '$crashRestartLimit restarts in a row did not keep the Core up for '
            '${crashRestartWindow.inSeconds}s, leaving it down: $crash',
            logLevel: LogLevel.error,
          );
          return;
        }
        commonPrint.log(
          'Core is down, restarting it: $crash',
          logLevel: LogLevel.warning,
        );
        // restartCore() joins a restart under way instead of relaunching.
        await _restartOperation?.catchError((_) => false);
        final running = ref.read(setupActionProvider.notifier).requestedRunning;
        _restartingAfterCrash = true;
        try {
          await restartCore(running: running);
          _crashRestartedAt = currentTime();
        } catch (error) {
          if (error case DesktopCoreFailure(phase: DesktopCorePhase.closed)) {
            return;
          }
          if (_unansweredCrash == null) {
            _failedRestarts++;
            _unansweredCrash = compactError(error);
          }
        } finally {
          _restartingAfterCrash = false;
        }
      }
    } finally {
      _answeringCrashes = false;
    }
  }

  /// [running] stands in for a run that a crash rolled back.
  Future<bool> restartCore({bool? running}) {
    _requestedRestartRevision++;
    final activeOperation = _restartOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    final operation = _runRestartWorker(running: running);
    _restartOperation = operation;
    return operation;
  }

  /// An in-process core (Android) cannot be relaunched, so a restart stops
  /// the tunnel, shuts mihomo down inside the process and initializes again.
  @protected
  bool get coreIsEmbedded => coreLib != null;

  Future<bool> _runRestartWorker({bool? running}) async {
    final setupAction = ref.read(setupActionProvider.notifier);
    final bool wasRunning = running ?? ref.read(isStartProvider);
    try {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      final stopping = coreIsEmbedded && wasRunning
          ? setupAction.setRunning(false)
          : null;
      final runIntent = setupAction.runIntent;
      if (coreIsEmbedded) {
        await stopping;
        await _core.shutdown();
      }
      final result = await restartLifecycle();
      if (!await _applyLifecycleResult(result, statusFirst: true)) {
        return false;
      }

      var appliedRevision = 0;
      var applied = true;
      while (appliedRevision < _requestedRestartRevision) {
        final revision = _requestedRestartRevision;
        applied = await _restoreRunning(
          setupAction,
          wasRunning: wasRunning,
          runRequested: running,
          observedIntent: runIntent,
        );
        appliedRevision = revision;
      }
      return applied;
    } catch (_) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      rethrow;
    } finally {
      _restartOperation = null;
    }
  }

  /// A request made mid-restart hit a dead process; the latest intent wins.
  Future<bool> _restoreRunning(
    SetupAction setupAction, {
    required bool wasRunning,
    required bool? runRequested,
    required Object? observedIntent,
  }) async {
    final intentChanged = !identical(setupAction.runIntent, observedIntent);
    final running = intentChanged
        ? setupAction.requestedRunning == true
        : runRequested ?? (wasRunning || ref.read(isStartProvider));
    if (running) {
      return setupAction.setRunning(true, initialize: true);
    }
    if (ref.read(isStartProvider)) {
      await globalState.safeRun(() => setupAction.setRunning(false));
    }
    return setupAction.applyProfile(force: true);
  }
}
