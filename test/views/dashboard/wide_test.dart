import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/views/dashboard/wide.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<DashboardWidget>> _rows(List<DashboardWidget> cards, int columns) => [
  for (final row in wideRowsOf(cards, columns)) row.cards,
];

void main() {
  test('the full arrangement lays out the grid it always had', () {
    final cards = [
      DashboardWidget.announcement,
      ...wideDashboardWidgetsOf(SupportPlatform.MacOS),
    ];

    expect(_rows(cards, 4), [
      [DashboardWidget.announcement],
      [DashboardWidget.currentOutbound, DashboardWidget.networkSpeed],
      [DashboardWidget.outboundMode, DashboardWidget.networkTakeover],
      [
        DashboardWidget.intranetIp,
        DashboardWidget.profiles,
        DashboardWidget.serviceStatus,
        DashboardWidget.memoryInfo,
      ],
      [DashboardWidget.connectionStats, DashboardWidget.proxyGroups],
    ]);
    expect(_rows(cards, 2), [
      [DashboardWidget.announcement],
      [DashboardWidget.currentOutbound],
      [DashboardWidget.networkSpeed],
      [DashboardWidget.outboundMode],
      [DashboardWidget.networkTakeover],
      [DashboardWidget.intranetIp, DashboardWidget.profiles],
      [DashboardWidget.serviceStatus, DashboardWidget.memoryInfo],
      [DashboardWidget.connectionStats, DashboardWidget.proxyGroups],
    ]);
  });

  test('the arrangement holds the switches each platform has', () {
    expect(
      wideDashboardWidgetsOf(SupportPlatform.Android),
      contains(DashboardWidget.vpnButton),
    );
    expect(
      wideDashboardWidgetsOf(SupportPlatform.Android),
      isNot(contains(DashboardWidget.networkTakeover)),
    );
    expect(
      wideDashboardWidgetsOf(SupportPlatform.Windows),
      isNot(contains(DashboardWidget.vpnButton)),
    );
  });

  test('a card starts a new row when its kind changes or the row is full', () {
    expect(
      _rows(const [
        DashboardWidget.memoryInfo,
        DashboardWidget.currentOutbound,
        DashboardWidget.profiles,
        DashboardWidget.intranetIp,
        DashboardWidget.serviceStatus,
        DashboardWidget.memoryInfo,
        DashboardWidget.intranetIp,
      ], 4),
      [
        [DashboardWidget.memoryInfo],
        [DashboardWidget.currentOutbound],
        [
          DashboardWidget.profiles,
          DashboardWidget.intranetIp,
          DashboardWidget.serviceStatus,
          DashboardWidget.memoryInfo,
        ],
        [DashboardWidget.intranetIp],
      ],
    );
  });
}
