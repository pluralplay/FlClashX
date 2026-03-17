import 'package:flclashx/clash/clash.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/common/file_logger.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClashManager extends ConsumerStatefulWidget {

  const ClashManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<ClashManager> createState() => _ClashContainerState();
}

class _ClashContainerState extends ConsumerState<ClashManager>
    with AppMessageListener {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void initState() {
    super.initState();
    clashMessage.addListener(this);
    ref.listenManual(needSetupProvider, (prev, next) {
      if (prev != next) {
        globalState.appController.handleChangeProfile();
      }
    });
    ref.listenManual(coreStateProvider, (prev, next) async {
      if (prev != next) {
        await clashCore.setState(next);
      }
    });
    ref.listenManual(updateParamsProvider, (prev, next) {
      if (prev != next) {
        globalState.appController.updateClashConfigDebounce();
      }
    });

    ref.listenManual(
      appSettingProvider.select((state) => state.openLogs),
      (prev, next) {
        if (next) {
          clashCore.startLog();
        } else {
          clashCore.stopLog();
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    clashMessage.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onDelay(Delay delay) async {
    super.onDelay(delay);
    final appController = globalState.appController;
    appController.setDelay(delay);
    debouncer.call(
      FunctionTag.updateDelay,
      () async {
        appController.updateGroupsDebounce();
      },
      duration: const Duration(milliseconds: 5000),
    );
  }

  @override
  void onLog(Log log) {
    ref.read(logsProvider.notifier).addLog(log);
    
    // Write core logs to file
    fileLogger.log("[${log.logLevel.name.toUpperCase()}] ${log.payload}");
    
    if (log.logLevel == LogLevel.error) {
      globalState.showNotifier(log.payload);
    }
    super.onLog(log);
  }

  @override
  void onRequest(Connection connection) async {
    ref.read(requestsProvider.notifier).addRequest(connection);
    super.onRequest(connection);
  }

  @override
  Future<void> onLoaded(String providerName) async {
    ref.read(providersProvider.notifier).setProvider(
          await clashCore.getExternalProvider(
            providerName,
          ),
        );
    globalState.appController.updateGroupsDebounce();
    super.onLoaded(providerName);
  }
}
