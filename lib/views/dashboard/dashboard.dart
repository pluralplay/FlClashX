import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit.dart';
import 'hero.dart';
import 'layout.dart';
import 'style.dart';
import 'widget_registry.dart';
import 'widgets/core_status_button.dart';
import 'widgets/widgets.dart';

// Narrower columns leave the service grid's cells too tight for a status, so
// the grid takes the memory card's column instead.
const _memoryColumnMin = 290.0;

const _maxColumnWidth = 440.0;

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.platform});

  /// The host's platform when null.
  final SupportPlatform? platform;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  var _editing = false;
  final _cardKeys = <DashboardWidget, GlobalKey>{};

  void _setEditing(bool editing) {
    setState(() => _editing = editing);
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final viewSize = ref.watch(viewSizeProvider);
    final sideWidth = ref.watch(sideWidthProvider);
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final size = Size(viewSize.width - sideWidth, viewSize.height) / scale;
    final hero = ref.watch(
      themeSettingProvider.select(
        (state) => state.style == ThemeStyle.enhanced,
      ),
    );
    final mode = hero
        ? ref.watch(patchClashConfigProvider.select((state) => state.mode))
        : null;
    final editable =
        !hero &&
        !DashboardDensity.of(size).isDesktop &&
        !ref.watch(widgetEditingDeniedProvider);
    if (!editable) {
      _editing = false;
    }
    final editing = _editing;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: editing
          ? appLocalizations.editDashboard
          : appLocalizations.dashboard,
      backAction: editing ? () => _setEditing(false) : null,
      actions: [if (!editing) const CoreStatusButton()],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false),
            )
          : null,
      iconActions: [
        if (mode != null && ref.watch(globalModeAllowedProvider))
          IconButtonData(
            glyph: mode == Mode.global ? AppGlyphs.proxies : AppGlyphs.rules,
            tooltip:
                '${appLocalizations.outboundMode}: '
                '${mode == Mode.global ? appLocalizations.global : appLocalizations.rule}',
            onPressed: () => ref
                .read(setupActionProvider.notifier)
                .changeMode(mode == Mode.global ? Mode.rule : Mode.global),
          ),
        if (editable && !editing)
          IconButtonData(
            glyph: AppGlyphs.edit,
            tooltip: appLocalizations.editDashboard,
            onPressed: () => _setEditing(true),
          ),
      ],
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          final layout = DashboardDensity.of(room);
          if (hero) {
            return DashboardDensityScope(
              density: DashboardDensity.mobile,
              scale: scale,
              child: const HeroDashboard(),
            );
          }
          return DashboardDensityScope(
            density: layout,
            scale: scale,
            child: layout.isDesktop
                ? _DesktopDashboard(
                    platform: platform,
                    columns: dashboardColumnsOf(room.width),
                    gap: gap,
                  )
                : _MobileDashboard(
                    platform: platform,
                    gap: gap,
                    editing: editing,
                    cardKeyOf: _cardKeyOf,
                    onDone: () => _setEditing(false),
                  ),
          );
        },
      ),
    );
  }
}

/// Four columns fill the window, the tables taking what the rows above them
/// leave. A window too short for the tables, and every two column one, gets
/// the summary cards instead, so no list scrolls inside a page that scrolls.
class _DesktopDashboard extends ConsumerWidget {
  const _DesktopDashboard({
    required this.platform,
    required this.columns,
    required this.gap,
  });

  final SupportPlatform platform;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcement = ref.watch(announcementProvider) != null;
    final offers = ref.watch(
      profileOffersProvider.select((offers) => offers.isNotEmpty),
    );
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      MediaQuery.paddingOf(context).top,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    );
    final announcementHeight = (compact ? 100 : 112) * scale;
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    // The profile card's offer buttons need a taller middle row.
    final middleHeight = ((compact ? 152 : 176) + (offers ? 44 : 0)) * scale;
    final tablesHeight = connectionsTableMinHeight(density, scale);
    final summaryHeight = (compact ? 112 : 120) * scale;
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
        double span(int columns) => column * columns + gap * (columns - 1);
        Widget row(List<(int, Widget)> cards) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: [
            for (final (columns, card) in cards)
              SizedBox(
                width: span(columns),
                child: RepaintBoundary(child: card),
              ),
          ],
        );
        Widget sized(double height, Widget child) =>
            SizedBox(height: height, child: child);
        final switches =
            DashboardWidget.networkTakeover.platforms.contains(platform)
            ? const [
                (1, NetworkTakeoverTile(TakeoverSwitch.systemProxy)),
                (1, NetworkTakeoverTile(TakeoverSwitch.tun)),
              ]
            : const [(2, VpnTile())];
        final half = columns ~/ 2;
        final summaries = row([
          (half, const ConnectionStatsCard()),
          (half, const ProxyGroupsSummaryCard()),
        ]);
        if (columns == 2) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: Column(
              spacing: gap,
              children: [
                if (announcement)
                  sized(
                    announcementHeight,
                    const RepaintBoundary(child: AnnouncementCard()),
                  ),
                sized(
                  topHeight,
                  const RepaintBoundary(child: CurrentOutboundCard()),
                ),
                sized(
                  topHeight,
                  row(const [
                    (1, SpeedCard(direction: TrafficDirection.upload)),
                    (1, SpeedCard(direction: TrafficDirection.download)),
                  ]),
                ),
                sized(
                  controlHeight,
                  const RepaintBoundary(child: OutboundModeBar()),
                ),
                sized(controlHeight, row(switches)),
                sized(
                  middleHeight,
                  row(const [(1, IntranetIpCard()), (1, ProfilesCard())]),
                ),
                sized(
                  middleHeight,
                  row(const [(1, ServiceStatusCard()), (1, MemoryInfo())]),
                ),
                sized(summaryHeight, summaries),
              ],
            ),
          );
        }
        final rows = [
          if (announcement)
            sized(
              announcementHeight,
              const RepaintBoundary(child: AnnouncementCard()),
            ),
          sized(
            topHeight,
            row(const [
              (2, CurrentOutboundCard()),
              (1, SpeedCard(direction: TrafficDirection.upload)),
              (1, SpeedCard(direction: TrafficDirection.download)),
            ]),
          ),
          sized(
            controlHeight,
            row([(2, const OutboundModeBar()), ...switches]),
          ),
          sized(
            middleHeight,
            row([
              (1, const IntranetIpCard()),
              (1, const ProfilesCard()),
              if (column >= _memoryColumnMin * scale) ...[
                (1, const ServiceStatusCard()),
                (1, const MemoryInfo()),
              ] else
                (2, const ServiceStatusCard()),
            ]),
          ),
        ];
        final rowsHeight =
            padding.vertical +
            (announcement ? announcementHeight + gap : 0) +
            topHeight +
            controlHeight +
            middleHeight +
            gap * 3;
        final tablesFit = constraints.maxHeight >= rowsHeight + tablesHeight;
        final fills = constraints.maxHeight >= rowsHeight + summaryHeight;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: fills ? constraints.maxHeight : null,
            child: Padding(
              padding: padding,
              child: Column(
                spacing: gap,
                children: [
                  ...rows,
                  if (tablesFit)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: gap,
                        children: const [
                          Expanded(
                            flex: 3,
                            child: RepaintBoundary(
                              child: ConnectionsTableCard(),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: RepaintBoundary(child: ProxyGroupsCard()),
                          ),
                        ],
                      ),
                    )
                  else if (fills)
                    Expanded(child: summaries)
                  else
                    sized(summaryHeight, summaries),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.platform,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    final announcement = ref.watch(announcementProvider) != null;
    final top = MediaQuery.paddingOf(context).top + 4;
    final bottom = 16 + BottomInsetScope.of(context);
    return CustomScrollView(
      // A viewport per card lays them all out and holds the scroll end still.
      scrollCacheExtent: editing
          ? ScrollCacheExtent.viewport(DashboardWidget.values.length.toDouble())
          : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = dashboardMobileSideOf(constraints.crossAxisExtent);
            final widgets = pinnedFirst([
              for (final widget in saved)
                if (widget.platforms.contains(platform)) widget,
            ], announcement: announcement);
            if (editing) {
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              // A lazy list estimates the cards it has not laid out from the
              // ones it has; cards this uneven move the scroll end as it goes.
              sliver: SliverToBoxAdapter(
                child: Column(
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      RepaintBoundary(
                        key: cardKeyOf(widget),
                        child: widget.card,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
