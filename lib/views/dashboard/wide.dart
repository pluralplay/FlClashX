import 'dart:math' as math;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'layout.dart';
import 'widget_registry.dart';
import 'widgets/widgets.dart';

// Narrower columns leave a pair of service cells too tight for a status, so
// the grid stacks them in one.
const _servicePairColumnMin = 290.0;

const _maxColumnWidth = 440.0;

/// The rows of the wide dashboard; cards share a row only with their kind.
enum WideRowKind { announcement, top, control, middle, bottom }

class WideRow {
  const WideRow(this.kind, this.cards);

  final WideRowKind kind;
  final List<DashboardWidget> cards;
}

extension DashboardWidgetWide on DashboardWidget {
  WideRowKind get wideRowKind => switch (this) {
    DashboardWidget.announcement => WideRowKind.announcement,
    DashboardWidget.currentOutbound ||
    DashboardWidget.networkSpeed => WideRowKind.top,
    DashboardWidget.outboundMode ||
    DashboardWidget.vpnButton ||
    DashboardWidget.networkTakeover => WideRowKind.control,
    DashboardWidget.intranetIp ||
    DashboardWidget.profiles ||
    DashboardWidget.serviceStatus ||
    DashboardWidget.memoryInfo => WideRowKind.middle,
    DashboardWidget.connectionStats ||
    DashboardWidget.proxyGroups => WideRowKind.bottom,
  };

  int wideSpan(int columns) => switch (wideRowKind) {
    WideRowKind.announcement => columns,
    WideRowKind.bottom => columns ~/ 2,
    WideRowKind.middle => 1,
    WideRowKind.top || WideRowKind.control => math.min(2, columns),
  };
}

/// The cards in order, a row taking the next ones of its kind while they fit.
List<WideRow> wideRowsOf(List<DashboardWidget> cards, int columns) {
  final rows = <WideRow>[];
  var used = 0;
  for (final card in cards) {
    final span = card.wideSpan(columns);
    final last = rows.lastOrNull;
    if (last != null &&
        last.kind == card.wideRowKind &&
        used + span <= columns) {
      last.cards.add(card);
      used += span;
    } else {
      rows.add(WideRow(card.wideRowKind, [card]));
      used = span;
    }
  }
  return rows;
}

/// The arrangement the wide dashboard keeps until someone picks the cards.
List<DashboardWidget> wideDashboardWidgetsOf(SupportPlatform platform) => [
  for (final card in const [
    DashboardWidget.currentOutbound,
    DashboardWidget.networkSpeed,
    DashboardWidget.outboundMode,
    DashboardWidget.networkTakeover,
    DashboardWidget.vpnButton,
    DashboardWidget.intranetIp,
    DashboardWidget.profiles,
    DashboardWidget.serviceStatus,
    DashboardWidget.memoryInfo,
    DashboardWidget.connectionStats,
    DashboardWidget.proxyGroups,
  ])
    if (card.platforms.contains(platform)) card,
];

/// Four columns fill the window, the tables taking what the rows above them
/// leave when they come last. A window too short for the tables, and every two
/// column one, gets the summary cards instead, so no list scrolls inside a page
/// that scrolls.
class WideDashboard extends ConsumerWidget {
  const WideDashboard({
    super.key,
    required this.cards,
    required this.columns,
    required this.gap,
  });

  final List<DashboardWidget> cards;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = ref.watch(
      profileOffersProvider.select((offers) => offers.isNotEmpty),
    );
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      context.contentTopPadding,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    );
    // The profile card's offer buttons need a taller middle row.
    double heightOf(WideRowKind kind) =>
        switch (kind) {
          WideRowKind.announcement => compact ? 100 : 112,
          WideRowKind.top => compact ? 176 : 208,
          WideRowKind.control => compact ? 56 : 64,
          WideRowKind.middle => (compact ? 152 : 176) + (offers ? 44 : 0),
          WideRowKind.bottom => compact ? 112 : 120,
        } *
        scale;
    final tablesHeight = connectionsTableMinHeight(density, scale);
    final rows = wideRowsOf(cards, columns);
    final last = rows.lastOrNull;
    final bottomLast = last?.kind == WideRowKind.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth - base.horizontal - gap * (columns - 1);
        final column = math.min(room / columns, _maxColumnWidth * scale);
        final inset = (room - column * columns) / 2;
        final padding = base.copyWith(
          start: base.start + inset,
          end: base.end + inset,
        );
        final rowsHeight =
            padding.vertical +
            gap * (rows.length - 1) +
            rows
                .where((row) => !bottomLast || row != last)
                .fold(0.0, (sum, row) => sum + heightOf(row.kind));
        final tablesFit =
            columns == 4 &&
            bottomLast &&
            constraints.maxHeight >= rowsHeight + tablesHeight;
        final fills =
            columns == 4 &&
            bottomLast &&
            constraints.maxHeight >= rowsHeight + heightOf(WideRowKind.bottom);
        Widget rowOf(WideRow row) {
          final tables = tablesFit && row == last;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              for (final card in row.cards)
                Expanded(
                  flex: tables
                      ? (card == DashboardWidget.connectionStats ? 3 : 2)
                      : card.wideSpan(columns),
                  child: RepaintBoundary(
                    child: _WideCard(
                      card: card,
                      tables: tables,
                      gap: gap,
                      serviceColumns: (width) =>
                          width >= _servicePairColumnMin * scale ? 2 : 1,
                    ),
                  ),
                ),
            ],
          );
          if (row == last && fills) {
            return Expanded(child: content);
          }
          return SizedBox(height: heightOf(row.kind), child: content);
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: fills ? constraints.maxHeight : null,
            child: Padding(
              padding: padding,
              child: Column(
                spacing: gap,
                children: [for (final row in rows) rowOf(row)],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WideCard extends StatelessWidget {
  const _WideCard({
    required this.card,
    required this.tables,
    required this.gap,
    required this.serviceColumns,
  });

  final DashboardWidget card;
  final bool tables;
  final double gap;
  final int Function(double width) serviceColumns;

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget first, Widget second) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        Expanded(child: first),
        Expanded(child: second),
      ],
    );
    return switch (card) {
      DashboardWidget.networkSpeed => pair(
        const SpeedCard(direction: TrafficDirection.upload),
        const SpeedCard(direction: TrafficDirection.download),
      ),
      DashboardWidget.outboundMode => const OutboundModeBar(),
      DashboardWidget.networkTakeover => pair(
        const NetworkTakeoverTile(TakeoverSwitch.systemProxy),
        const NetworkTakeoverTile(TakeoverSwitch.tun),
      ),
      DashboardWidget.vpnButton => const VpnTile(),
      DashboardWidget.serviceStatus => LayoutBuilder(
        builder: (context, constraints) =>
            ServiceStatusCard(columns: serviceColumns(constraints.maxWidth)),
      ),
      DashboardWidget.connectionStats =>
        tables ? const ConnectionsTableCard() : const ConnectionStatsCard(),
      DashboardWidget.proxyGroups =>
        tables ? const ProxyGroupsCard() : const ProxyGroupsSummaryCard(),
      _ => card.card,
    };
  }
}
