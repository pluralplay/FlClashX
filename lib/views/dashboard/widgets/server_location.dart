import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'current_outbound.dart';
import 'proxy_groups.dart';

const _flagSize = 52.0;

/// The status card of a `providermode` dashboard: the pick of the panel's
/// server group, or of the first group with one, with its flag, the exit
/// address while running and its delay. The whole card opens the picker;
/// the flag alone checks the location again.
class ServerLocationCard extends ConsumerStatefulWidget {
  const ServerLocationCard({super.key});

  @override
  ConsumerState<ServerLocationCard> createState() => _ServerLocationCardState();
}

class _ServerLocationCardState extends ConsumerState<ServerLocationCard> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final groups = ref.watch(currentGroupsStateProvider).value;
    final picked = groups.panelServerGroup(
      ref.watch(
        currentProfileProvider.select((state) => state?.headers.serverGroup),
      ),
    );
    final groupName = picked?.name;
    final selected = groupName == null
        ? null
        : ref.watch(selectedProxyNameProvider(groupName));
    final leaf = selected == null || selected.isEmpty
        ? null
        : ref.watch(realSelectedProxyStateProvider(selected));
    final serverName = selected ?? '';
    final delay = serverName.isEmpty
        ? null
        : ref.watch(
            delayProvider(
              proxyName: serverName,
              testUrl: leaf?.testUrl ?? picked?.testUrl,
            ),
          );
    final isStart = ref.watch(isStartProvider);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final ipInfo = entry.value;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final code = picked == null || serverName.isEmpty
        ? null
        : serverFlagCode(picked, serverName, leaf);
    final others = picked == null
        ? const <String>[]
        : ref
              .watch(groupFlagsProvider(picked.name))
              .where((other) => other != code)
              .toList();
    final otherCount = others.isNotEmpty
        ? others.length
        : picked == null
        ? 0
        : (picked.all.length - 1).clamp(0, 999);
    final title = serverName.isEmpty
        ? appLocalizations.changeServer
        : serverName.withoutLeadingFlag;
    final ipStyle = DashboardText.label(context);
    final Widget? ip = !isStart || serverName.isEmpty || hideIp
        ? null
        : ipInfo != null
        ? Text(
            ipInfo.ip,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ipStyle,
          )
        : entry.isLoading
        ? SkeletonText(width: 110, style: ipStyle)
        : null;
    final recheck = isStart && !entry.isLoading
        ? () => ref.read(outboundIpProbeProvider.notifier).refresh(const [
            routedOutbound,
          ])
        : null;
    return DashboardCard(
      semanticLabel: appLocalizations.changeServer,
      onTap: groups.isEmpty
          ? null
          : () => showProxiesSheet(context, groupName: groupName),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        spacing: 12,
        children: [
          _FlagBadge(
            code: code,
            count: otherCount,
            active: isStart,
            checking: entry.isLoading,
            onRefresh: recheck ?? () {},
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Flexible(
                      child: EmojiText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (hideIp
                                    ? AppTextStyle.title3
                                    : AppTextStyle.headline)
                                .of(context, emphasized: true),
                      ),
                    ),
                    if (groups.isNotEmpty)
                      GlyphIcon(
                        AppGlyphs.swap,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
                if (ip != null) ...[const SizedBox(height: 2), ip],
              ],
            ),
          ),
          if (serverName.isNotEmpty)
            SizedBox(
              width: 52,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SignalBars(delay: delay),
                  if (delay != null && delay > 0)
                    Text(
                      '$delay ms',
                      maxLines: 1,
                      style: DashboardText.figure(
                        context,
                        AppTextStyle.caption1,
                        color: colorScheme.delayColor(delay) ?? colors.thumb,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The server's flag in a circle and a count of the group's other
/// countries.
class _FlagBadge extends StatelessWidget {
  const _FlagBadge({
    required this.code,
    required this.count,
    required this.active,
    required this.checking,
    required this.onRefresh,
  });

  final String? code;
  final int count;
  final bool active;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    return SizedBox.square(
      dimension: _flagSize + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: CountryBadge(
              countryCode: code,
              size: _flagSize,
              active: active,
              checking: checking,
              onRefresh: onRefresh,
            ),
          ),
          if (count > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: ShapeDecoration(
                  color: colorScheme.primary,
                  shape: AppShape.full.copyWith(
                    side: BorderSide(color: colors.card, width: 1.5),
                  ),
                ),
                child: Text(
                  '+$count',
                  style: DashboardText.figure(
                    context,
                    AppTextStyle.caption2,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Four bars, as a phone shows its signal, lit by how low the delay is.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.delay});

  static const _heights = [8.0, 12.0, 16.0, 20.0];

  final int? delay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dim = colorScheme.onSurfaceVariant.withValues(alpha: 0.25);
    final delay = this.delay;
    final level = switch (delay) {
      null || 0 => 0,
      < 0 => 0,
      < 150 => 4,
      < 300 => 3,
      < 600 => 2,
      _ => 1,
    };
    final lit = colorScheme.delayColor(delay) ?? dim;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 3,
      children: [
        for (final (index, height) in _heights.indexed)
          Container(
            width: 4,
            height: height,
            decoration: ShapeDecoration(
              color: index < level ? lit : dim,
              shape: AppShape.full,
            ),
          ),
      ],
    );
  }
}
