part of '../action.dart';

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
  });

  final String proxyName;
  final String testUrl;
  final String key;
}

typedef _DelayTestBatch = ({List<Proxy> proxies, String? testUrl});

/// The switches of one group still waiting on the Core.
class _PendingPicks {
  _PendingPicks(this.confirmed);

  /// The latest pick the Core accepted, in the order they were made.
  String confirmed;
  int confirmedIntent = 0;
  int failedIntent = 0;
  int count = 0;
}

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys, this.timeout) : held = keys.toSet();

  final Set<String> held;
  final Duration timeout;
  final Set<String> startedOnDispatch = {};
  bool cancelled = false;
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  final TaskPool _delayTestPool = TaskPool(maxConcurrentDelayTests);

  /// The Core answers a test within twice its timeout; a null that took this
  /// long is the RPC guard giving up on a Core that went silent.
  @visibleForTesting
  Duration silentCoreAfter = delayTestGuardDuration;

  final List<_DelayTestJob> _delayTestJobs = [];

  final List<Delay> _bufferedDelays = [];

  final List<String> _bufferedStarts = [];

  final List<String> _bufferedFinishes = [];

  final Set<int> _firstGroupToUnfold = {};

  Timer? _delayFlushTimer;

  final Map<(int?, String), String> _pendingSelectedRollback = {};

  /// A failed switch rolls back only while no later pick was made in its group.
  final Map<(int?, String), int> _selectionIntents = {};

  final Map<(int?, String), _PendingPicks> _pendingPicks = {};

  final Map<String, int> _changingGroups = {};

  var _settledChanges = 0;

  var _groupRefreshes = 0;

  @override
  void build() {
    ref.onDispose(() => _delayFlushTimer?.cancel());
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        cancelDelayTests();
      }
    });
  }

  void cancelDelayTests() {
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      job.held.clear();
    }
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    _bufferedDelays.clear();
    _bufferedStarts.clear();
    _bufferedFinishes.clear();
    ref.read(pendingDelayTestsProvider.notifier).clear();
  }

  void _scheduleDelayFlush() {
    _delayFlushTimer ??= Timer(renderThrottleDuration, _flushDelayResults);
  }

  void _flushDelayResults() {
    _delayFlushTimer?.cancel();
    _delayFlushTimer = null;
    if (_bufferedDelays.isNotEmpty) {
      final delays = List.of(_bufferedDelays);
      _bufferedDelays.clear();
      ref.read(delayDataSourceProvider.notifier).setDelays(delays);
    }
    if (_bufferedStarts.isNotEmpty || _bufferedFinishes.isNotEmpty) {
      final started = List.of(_bufferedStarts);
      final finished = List.of(_bufferedFinishes);
      _bufferedStarts.clear();
      _bufferedFinishes.clear();
      ref
          .read(pendingDelayTestsProvider.notifier)
          .apply(started: started, finished: finished);
    }
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    final profileId = ref.read(currentProfileIdProvider);
    _newSelectionIntent(profileId, groupName);
    _pendingSelectedRollback.putIfAbsent((
      profileId,
      groupName,
    ), () => _currentSelectedName(groupName));
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
    debouncer.call((FunctionTag.changeProxy, profileId, groupName), (
      String groupName,
      String proxyName,
    ) async {
      // A switch away applies the profile with this pick already stored.
      if (profileId != ref.read(currentProfileIdProvider)) {
        _pendingSelectedRollback.remove((profileId, groupName));
        return;
      }
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  void _storeSelection(int? profileId, String groupName, String proxyName) {
    if (profileId == null) return;
    ref
        .read(profilesProvider.notifier)
        .updateProfile(
          profileId,
          (profile) => profile.copyWith(
            selectedMap: {...profile.selectedMap, groupName: proxyName},
          ),
        );
  }

  int _newSelectionIntent(int? profileId, String groupName) =>
      _selectionIntents.update(
        (profileId, groupName),
        (intent) => intent + 1,
        ifAbsent: () => 1,
      );

  String _currentSelectedName(String groupName) {
    return ref.read(currentProfileProvider)?.selectedMap[groupName] ?? '';
  }

  Future<void> updateGroups() async {
    var asked = const <String, String>{};
    var settled = _settledChanges;
    final refresh = ++_groupRefreshes;
    final profileId = ref.read(currentProfileIdProvider);
    final pushes = ref.read(setupActionProvider.notifier).pushes;
    try {
      final groups = await retry<List<Group>>(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          asked = selectedMap;
          settled = _settledChanges;
          try {
            return await _core.getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            );
          } catch (e) {
            commonPrint.log(
              'updateGroups error: $e',
              logLevel: coreFailureLogLevel(e),
            );
            return [];
          }
        },
        retryIf: (res) => res.isEmpty,
      );
      // A later refresh, or the apply that follows a profile switch, has the
      // groups to show.
      if (refresh != _groupRefreshes ||
          profileId != ref.read(currentProfileIdProvider)) {
        return;
      }
      ref.read(groupsProvider.notifier).value = groups;
      if (profileId == ref.read(currentProfileIdProvider)) {
        _unfoldFirstGroupOf(profileId);
      }
      await _dropLostPins(
        groups,
        asked,
        settled: settled,
        profileId: profileId,
        pushes: pushes,
      );
    } catch (e) {
      // The Core failure path already runs inside the retry task above; a
      // throw here only means ref.read hit a disposed container or the
      // groupsProvider write itself failed.
      commonPrint.log(
        'updateGroups failed: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  /// mihomo forgets a Fallback pin once its node fails a check. A read that
  /// overlapped a push, a profile switch or a pick of the user's proves nothing.
  Future<void> _dropLostPins(
    List<Group> groups,
    Map<String, String> asked, {
    required int settled,
    required int? profileId,
    required int pushes,
  }) async {
    final setup = ref.read(setupActionProvider.notifier);
    if (!await setup.inputsApplied() ||
        pushes != setup.pushes ||
        settled != _settledChanges ||
        profileId != ref.read(currentProfileIdProvider)) {
      return;
    }
    final profilesAction = ref.read(profilesActionProvider.notifier);
    for (final group in groups) {
      final pin = asked[group.name] ?? '';
      if (!group.type.isComputedSelected ||
          group.fixed != '' ||
          pin.isEmpty ||
          _pendingSelectedRollback.containsKey((profileId, group.name)) ||
          _changingGroups.containsKey(group.name) ||
          _currentSelectedName(group.name) != pin) {
        continue;
      }
      profilesAction.updateCurrentSelectedMap(group.name, '');
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  /// A profile just added opens on its first group; the folds after that
  /// are the user's.
  void unfoldFirstGroupOnce(int profileId) =>
      _firstGroupToUnfold.add(profileId);

  void _unfoldFirstGroupOf(int? profileId) {
    if (!_firstGroupToUnfold.contains(profileId)) return;
    final first = ref.read(visibleGroupsStateProvider).value.firstOrNull;
    if (first == null) return;
    _firstGroupToUnfold.remove(profileId);
    updateCurrentUnfoldSet({...ref.read(unfoldSetProvider), first.name});
  }

  void setShownGroupsUnfolded(bool unfold) {
    final shown = ref
        .read(proxiesListStateProvider)
        .groups
        .map((group) => group.name);
    final current = ref.read(unfoldSetProvider);
    updateCurrentUnfoldSet(
      unfold ? {...current, ...shown} : current.difference(shown.toSet()),
    );
  }

  void setDelay(Delay delay) {
    _bufferedDelays.add(delay);
    _scheduleDelayFlush();
  }

  /// A pick made while an apply ran may have reached the groups it replaced,
  /// or been overwritten by the [applied] selection it carried.
  Future<void> resendPicksSince(Map<String, String> applied) async {
    final profileId = ref.read(currentProfileIdProvider);
    final picks = ref.read(selectedMapProvider);
    await Future.wait([
      for (final MapEntry(key: groupName, value: proxyName) in picks.entries)
        if (applied[groupName] != proxyName)
          _resendPick(profileId, groupName, proxyName),
    ]);
  }

  Future<void> _resendPick(
    int? profileId,
    String groupName,
    String proxyName,
  ) async {
    final key = (profileId, groupName);
    final String? running;
    try {
      running = await _core.groupPick(groupName);
    } catch (error) {
      commonPrint.log(
        'resend $groupName -> $proxyName skipped: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return;
    }
    // Gone from the new config, run already, or picked again since.
    if (running == null ||
        running == proxyName ||
        profileId != ref.read(currentProfileIdProvider) ||
        ref.read(selectedMapProvider)[groupName] != proxyName ||
        _pendingSelectedRollback.containsKey(key)) {
      return;
    }
    _pendingSelectedRollback[key] = running;
    await changeProxy(groupName: groupName, proxyName: proxyName);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final profileId = ref.read(currentProfileIdProvider);
    final key = (profileId, groupName);
    // A pick still in its debounce is older than this one, from the tray say.
    debouncer.cancel((FunctionTag.changeProxy, profileId, groupName));
    final rollbackName =
        _pendingSelectedRollback.remove(key) ?? _currentSelectedName(groupName);
    final intent = _newSelectionIntent(profileId, groupName);
    // Rolling back to the pick before this one would keep a pick the Core
    // may refuse as well.
    final picks = _pendingPicks.putIfAbsent(
      key,
      () => _PendingPicks(rollbackName),
    );
    picks.count++;
    profilesAction.updateCurrentSelectedMap(groupName, proxyName);
    final ChangeProxyResult result;
    _changingGroups.update(groupName, (count) => count + 1, ifAbsent: () => 1);
    try {
      result = await _switchProxy(groupName, proxyName);
      if (result.message.isNotEmpty) {
        throw MessageException(result.message);
      }
      // Before finally, which may hand the confirmed pick to a debounced one.
      if (intent > picks.confirmedIntent) {
        picks
          ..confirmed = proxyName
          ..confirmedIntent = intent;
        // The pick made after this one failed and rolled back past it.
        if (_selectionIntents[key] == picks.failedIntent) {
          _storeSelection(profileId, groupName, proxyName);
        }
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
      if (_selectionIntents[key] != intent) return;
      picks.failedIntent = intent;
      _storeSelection(profileId, groupName, picks.confirmed);
      dialogs.showNotifier(
        currentAppLocalizations.changeProxyFailedTip,
        level: MessageLevel.error,
      );
      return;
    } finally {
      if (--picks.count == 0) {
        _pendingPicks.remove(key);
        // A pick still in its debounce captured this one, not what the Core runs.
        if (_pendingSelectedRollback.containsKey(key)) {
          _pendingSelectedRollback[key] = picks.confirmed;
        }
      }
      if (_changingGroups.update(groupName, (count) => count - 1) == 0) {
        _changingGroups.remove(groupName);
      }
      _settledChanges++;
    }
    if (!result.changed) {
      return;
    }
    try {
      if (ref.read(appSettingProvider).closeConnections) {
        await _core.closeConnections();
      } else {
        await _core.resetConnections();
      }
    } catch (error) {
      commonPrint.log(
        'changeProxy($groupName -> $proxyName) connection reset failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  /// The Core may make a switch and lose the frame carrying its answer, so
  /// an unanswered one asks what the group runs before it counts as failed.
  Future<ChangeProxyResult> _switchProxy(
    String groupName,
    String proxyName,
  ) async {
    try {
      return await _core.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      );
    } on CoreMethodException catch (error) {
      if (error.code != 'no_response') rethrow;
      if (await _core.groupPick(groupName) == proxyName) {
        return const ChangeProxyResult(changed: true);
      }
      rethrow;
    }
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final clashProvidersAction = ref.read(
        clashProvidersActionProvider.notifier,
      );
      final ruleSet = await clashProvidersAction.remoteProviderOf(provider);
      if (ruleSet != null && !await clashProvidersAction.syncRemote(ruleSet)) {
        return '';
      }
      final message = await _core.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<String> sideLoadExternalProvider(
    ExternalProvider provider,
    String data, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final message = await _core.sideLoadExternalProvider(
        providerName: provider.name,
        path: provider.path ?? '',
        type: provider.type,
        data: data,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> addToLocalProxies(String proxyName) async {
    final appLocalizations = currentAppLocalizations;
    final definition = await _core.getProxyDefinition(proxyName);
    if (definition == null) {
      throw MessageException(
        appLocalizations.customIssueMissingProxies(proxyName),
      );
    }
    final (proxies, groupNames) = await (
      database.customProxiesDao.query().get(),
      database.proxyGroupsDao.names().get(),
    ).wait;
    final (:name, :added) = importProxy(
      definition,
      existing: [for (final proxy in proxies) proxy.definition],
      groupNames: groupNames.toSet(),
    );
    if (added == null) {
      dialogs.showNotifier(appLocalizations.alreadyInLocalProxies(name));
      return;
    }
    final order = indexing.generateKeyBetween(
      proxies.map((proxy) => proxy.order).nonNulls.lastOrNull,
      null,
    );
    await database.customProxies.put(
      CustomProxy.fromDefinition(added).copyWith(order: order).toCompanion(),
    );
    dialogs.showNotifier(appLocalizations.addedToLocalProxies(name));
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
    return _runDelayTests([
      (proxies: [proxy], testUrl: testUrl),
    ]);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests([(proxies: proxies, testUrl: testUrl)]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestGroups(List<Group> groups) async {
    await _runDelayTests([
      for (final group in groups) (proxies: group.all, testUrl: group.testUrl),
    ]);
    ref.read(sortNumProvider.notifier).add();
  }

  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null) {
      return;
    }
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    if (!testing.start(groupName)) {
      return;
    }
    try {
      final query = SearchQuery(
        matchSearch ? ref.read(queryProvider(QueryTag.proxies)) : '',
      );
      await delayTest(
        group.all.whereMatches(query, (proxy) => proxy.searchFields).toList(),
        group.testUrl,
      );
    } finally {
      testing.stop(groupName);
    }
  }

  /// A node in several groups is tested once: targets are keyed by node and URL.
  Future<void> delayTestAllGroups() async {
    final testing = ref.read(delayTestingGroupsProvider.notifier);
    final groups = [
      for (final group in ref.read(visibleGroupsStateProvider).value)
        if (testing.start(group.name)) group,
    ];
    if (groups.isEmpty) {
      return;
    }
    try {
      await delayTestGroups(groups);
    } finally {
      for (final group in groups) {
        testing.stop(group.name);
      }
    }
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<_DelayTestBatch> batches,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final batch in batches) {
      final fallbackTestUrl = ref.read(realTestUrlProvider(batch.testUrl));
      for (final proxy in batch.proxies) {
        final state = computeRealSelectedProxyState(
          proxy.name,
          groups: groups,
          selectedMap: selectedMap,
        );
        if (state.proxyName.isEmpty) {
          continue;
        }
        final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
        final key = delayTestKey(currentTestUrl, state.proxyName);
        if (!seen.add(key)) {
          continue;
        }
        targets.add(
          _DelayTestTarget(
            proxyName: state.proxyName,
            testUrl: currentTestUrl,
            key: key,
          ),
        );
      }
    }
    return targets;
  }

  Future<void> _runDelayTests(List<_DelayTestBatch> batches) async {
    final targets = _resolveDelayTestTargets(batches);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(
      targets.map((target) => target.key),
      Duration(milliseconds: ref.read(appSettingProvider).delayTestTimeout),
    );
    _delayTestJobs.add(job);
    // TaskPool.run starts a task synchronously while it has an idle slot.
    job.startedOnDispatch.addAll(
      targets.take(_delayTestPool.idleSlots).map((target) => target.key),
    );
    pending.apply(acquired: job.held, started: job.startedOnDispatch);
    try {
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      _flushDelayResults();
      final abandoned = job.held.toList();
      job.held.clear();
      pending.apply(
        finished: abandoned.where(job.startedOnDispatch.contains),
        released: abandoned.where(
          (key) => !job.startedOnDispatch.contains(key),
        ),
      );
    }
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    if (!job.startedOnDispatch.contains(target.key)) {
      _bufferedStarts.add(target.key);
      _scheduleDelayFlush();
    }
    final asked = Stopwatch()..start();
    try {
      final delay = await _core.getDelay(
        target.testUrl,
        target.proxyName,
        job.timeout,
      );
      if (delay != null && !job.cancelled) {
        setDelay(delay);
      }
      // Each test queued behind would wait out the same guard.
      if (delay == null && asked.elapsed >= silentCoreAfter) {
        job.cancelled = true;
      }
    } catch (error) {
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      if (job.held.remove(target.key)) {
        _bufferedFinishes.add(target.key);
        _scheduleDelayFlush();
      }
    }
  }
}
