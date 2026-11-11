import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _serviceVpnDemanded() => service?.vpnDemandedBySystem ?? false;

class VpnManager extends ConsumerStatefulWidget {
  final Widget child;
  final bool Function() isVpnDemandedBySystem;

  const VpnManager({
    super.key,
    this.isVpnDemandedBySystem = _serviceVpnDemanded,
    required this.child,
  });

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(vpnOptionsProvider.select((state) => state.value), (
      prev,
      next,
    ) {
      final demanded = widget.isVpnDemandedBySystem();
      VpnOptions? effective(VpnOptions? options) =>
          options?.effectiveWhen(vpnDemandedBySystem: demanded);
      final wanted = effective(next);
      final running = effective(ref.read(runningVpnOptionsProvider));
      if (wanted != null &&
          effective(prev) != wanted &&
          running != null &&
          running != wanted) {
        _showRestartTip();
      }
    });
  }

  void _showRestartTip() {
    dialogs.showNotifier(
      currentAppLocalizations.vpnConfigChangeDetected,
      level: MessageLevel.warning,
      actionState: MessageActionState(
        actionText: currentAppLocalizations.restart,
        action: () async {
          await ref.read(setupActionProvider.notifier).restartVpn();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
