import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

extension DashboardWidgetView on DashboardWidget {
  Widget get card => switch (this) {
    DashboardWidget.currentOutbound => const CurrentOutboundCard(),
    DashboardWidget.announcement => const AnnouncementCard(),
    DashboardWidget.networkSpeed => const NetworkSpeedCard(),
    DashboardWidget.outboundMode => const OutboundModeCard(),
    DashboardWidget.vpnButton => const VpnCard(),
    DashboardWidget.networkTakeover => const NetworkTakeoverCard(),
    DashboardWidget.serviceStatus => const ServiceStatusCard(),
    DashboardWidget.profiles => const ProfilesCard(),
    DashboardWidget.proxyGroups => const ProxyGroupsCard(),
    DashboardWidget.connectionStats => const ConnectionStatsCard(),
    DashboardWidget.intranetIp => const IntranetIpCard(),
    DashboardWidget.memoryInfo => const MemoryInfo(),
  };

  Glyph get glyph => switch (this) {
    DashboardWidget.currentOutbound => AppGlyphs.status,
    DashboardWidget.announcement => AppGlyphs.info,
    DashboardWidget.networkSpeed => AppGlyphs.speed,
    DashboardWidget.outboundMode => AppGlyphs.split,
    DashboardWidget.vpnButton => AppGlyphs.vpn,
    DashboardWidget.networkTakeover => AppGlyphs.shuffle,
    DashboardWidget.serviceStatus => AppGlyphs.verified,
    DashboardWidget.profiles => AppGlyphs.profiles,
    DashboardWidget.proxyGroups => AppGlyphs.layers,
    DashboardWidget.connectionStats => AppGlyphs.connections,
    DashboardWidget.intranetIp => AppGlyphs.devices,
    DashboardWidget.memoryInfo => AppGlyphs.memory,
  };

  String label(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return switch (this) {
      DashboardWidget.currentOutbound => appLocalizations.status,
      DashboardWidget.announcement => appLocalizations.announcement,
      DashboardWidget.networkSpeed => appLocalizations.networkSpeed,
      DashboardWidget.outboundMode => appLocalizations.outboundMode,
      DashboardWidget.vpnButton => 'VPN',
      DashboardWidget.networkTakeover => appLocalizations.networkTakeover,
      DashboardWidget.serviceStatus => appLocalizations.serviceStatus,
      DashboardWidget.profiles => appLocalizations.profile,
      DashboardWidget.proxyGroups => appLocalizations.proxyGroup,
      DashboardWidget.connectionStats => appLocalizations.connectionStats,
      DashboardWidget.intranetIp => appLocalizations.intranetIP,
      DashboardWidget.memoryInfo => appLocalizations.memoryInfo,
    };
  }

  String? description(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return switch (this) {
      DashboardWidget.currentOutbound => appLocalizations.currentOutboundDesc,
      DashboardWidget.connectionStats => appLocalizations.connectionStatsDesc,
      DashboardWidget.memoryInfo => appLocalizations.memoryInfoDesc,
      _ => null,
    };
  }

  /// The status card holds the start button, which has nowhere else to go,
  /// and the announcement comes and goes with the subscription.
  bool get pinned =>
      this == DashboardWidget.currentOutbound ||
      this == DashboardWidget.announcement;

  bool get removable => !pinned;
}

/// The pinned cards in their fixed order ahead of the saved ones, the
/// announcement only while the subscription sends one.
List<DashboardWidget> pinnedFirst(
  Iterable<DashboardWidget> saved, {
  required bool announcement,
}) {
  return [
    if (announcement) DashboardWidget.announcement,
    DashboardWidget.currentOutbound,
    for (final card in saved)
      if (!card.pinned) card,
  ];
}
