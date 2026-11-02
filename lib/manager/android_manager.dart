import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A consent refused without asking is undone only in the system VPN settings,
/// where another app's always-on VPN is turned off.
Future<void> explainVpnRefusal(
  VpnRefusal refusal, {
  Future<void> Function()? openVpnSettings,
}) async {
  final appLocalizations = currentAppLocalizations;
  switch (refusal) {
    case VpnRefusal.cancelled:
      dialogs.showNotifier(
        appLocalizations.vpnPermissionNotGranted(appName),
        level: MessageLevel.warning,
      );
    case VpnRefusal.restricted:
      dialogs.showNotifier(
        appLocalizations.vpnRestrictedByAdministrator,
        level: MessageLevel.warning,
      );
    case VpnRefusal.otherAlwaysOn:
      final open = await dialogs.showMessage(
        title: appLocalizations.vpnBlockedByAnotherApp,
        message: TextSpan(text: appLocalizations.vpnBlockedByAnotherAppTip),
        confirmText: appLocalizations.openVpnSettings,
      );
      if (open == true) {
        await (openVpnSettings ?? () async => app?.openVpnSettings())();
      }
  }
}

class AndroidManager extends ConsumerStatefulWidget {
  final Widget child;

  const AndroidManager({super.key, required this.child});

  @override
  ConsumerState<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends ConsumerState<AndroidManager>
    with ServiceListener {
  @override
  void initState() {
    super.initState();
    ref.listenManual(appSettingProvider.select((state) => state.hidden), (
      prev,
      next,
    ) {
      app?.updateExcludeFromRecents(next);
    }, fireImmediately: true);
    ref.listenManual(loadedLocaleProvider, (prev, next) {
      if (prev != null && prev != next && !safeModeBuild) {
        app?.initShortcuts();
      }
    });
    ref.listenManual(sharedStateProvider, (prev, next) {
      if (prev != next) {
        debouncer.call(FunctionTag.saveSharedFile, () async {
          await preferences.saveShareState(next);
        }, duration: const Duration(seconds: 1));
        if (prev?.needSyncSharedState != next.needSyncSharedState) {
          service?.syncState(next.needSyncSharedState);
        }
      }
    });
    service?.addListener(this);
    app?.onPackagesChanged = _reloadPackages;
    app?.onVpnPermissionDenied = explainVpnRefusal;
  }

  /// A reload reads every installed app's label, and a round of store updates
  /// reports each app on its own.
  void _reloadPackages() {
    if (ref.read(packagesProvider).isEmpty) {
      return;
    }
    debouncer.call(FunctionTag.reloadPackages, () async {
      if (mounted) {
        await ref.read(systemActionProvider.notifier).getPackages();
      }
    }, duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    debouncer.cancel(FunctionTag.reloadPackages);
    if (app?.onPackagesChanged == _reloadPackages) {
      app?.onPackagesChanged = null;
    }
    if (app?.onVpnPermissionDenied == explainVpnRefusal) {
      app?.onVpnPermissionDenied = null;
    }
    service?.removeListener(this);
    super.dispose();
  }

  @override
  void onServiceEvent(CoreEvent event) {
    coreEventManager.sendEvent(event);
    super.onServiceEvent(event);
  }

  @override
  void onServiceStopped() {
    unawaited(ref.read(setupActionProvider.notifier).setRunning(false));
    super.onServiceStopped();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
