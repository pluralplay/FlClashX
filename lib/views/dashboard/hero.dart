import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart' show routedOutbound;
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';
import 'widgets/card.dart';
import 'widgets/widgets.dart';

const heroMaxWidth = 520.0;

const _logoSize = 96.0;
const _flagSize = 52.0;
const _connectHeight = 56.0;
const _gap = 12.0;

/// The hero home page: the service's logo and name over the plan, the
/// server and one connect button, the way the fork drew it.
class HeroDashboard extends ConsumerStatefulWidget {
  const HeroDashboard({super.key});

  @override
  ConsumerState<HeroDashboard> createState() => _HeroDashboardState();
}

class _HeroDashboardState extends ConsumerState<HeroDashboard> {
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
    final profile = ref.watch(currentProfileProvider);
    final padding = EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 8,
      16,
      16 + BottomInsetScope.of(context),
    );
    if (profile == null) {
      return Padding(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: heroMaxWidth),
            child: const _EmptyHero(),
          ),
        ),
      );
    }
    final headers = profile.headers;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: heroMaxWidth),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: padding.copyWith(bottom: _gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ServiceLogo(url: headers.serviceLogo),
                    const SizedBox(height: 14),
                    Center(
                      child: EmojiText(
                        headers.serviceName ?? appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.title2.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const AnnouncementCard(),
                    if (ref.watch(announcementProvider) != null)
                      const SizedBox(height: _gap),
                    _ServerPanel(group: headers.serverGroup),
                    const SizedBox(height: _gap),
                    const ProfilesCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: padding.copyWith(top: 0),
              child: const _ConnectButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero();

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ServiceLogo(),
        const SizedBox(height: 14),
        Text(
          appName,
          textAlign: TextAlign.center,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: _connectHeight,
          child: FilledButton.icon(
            onPressed: () => showAddProfilePage(context),
            icon: const GlyphIcon(AppGlyphs.add, fill: 1),
            label: Text(appLocalizations.addProfile),
          ),
        ),
      ],
    );
  }
}

/// The panel's logo, png or svg, else the app's own icon.
class _ServiceLogo extends StatelessWidget {
  const _ServiceLogo({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final fallback = Image.asset(
      'assets/images/icon.png',
      width: _logoSize,
      height: _logoSize,
      fit: BoxFit.cover,
    );
    final Widget logo = url == null
        ? fallback
        : url.toLowerCase().endsWith('.svg')
        ? SvgPicture.network(
            url,
            width: _logoSize,
            height: _logoSize,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => fallback,
          )
        : Image.network(
            url,
            width: _logoSize,
            height: _logoSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return Center(
      child: ClipRSuperellipse(
        borderRadius: AppRadius.xxl,
        child: SizedBox.square(dimension: _logoSize, child: logo),
      ),
    );
  }
}

/// The selection the panel's group, or the first group with one, is on,
/// with its flag, the exit address while running and its delay; a tap
/// opens the picker.
class _ServerPanel extends ConsumerWidget {
  const _ServerPanel({required this.group});

  /// The group the panel named, else the first with a live pick.
  final String? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final groups = ref.watch(currentGroupsStateProvider).value;
    final picked = _pickedGroupOf(groups, group);
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
    final allGroups = ref.watch(groupsProvider);
    final server = picked?.all.firstWhereOrNull(
      (proxy) => proxy.name == serverName,
    );
    final nameCode =
        serverName.flagCountryCode ??
        server?.serverDescription?.flagCountryCode ??
        leaf?.proxyName.flagCountryCode;
    final code = nameCode ?? (isStart ? ipInfo?.countryCode : null);
    final others = picked == null
        ? const <String>[]
        : _groupFlagsOf(
            allGroups,
            picked,
          ).where((other) => other != nameCode).toList();
    final otherCount = others.isNotEmpty
        ? others.length
        : picked == null
        ? 0
        : (picked.all.length - 1).clamp(0, 999);
    final title = serverName.isEmpty
        ? appLocalizations.changeServer
        : serverName.withoutLeadingFlag;
    final ipStyle = DashboardText.label(context);
    final Widget? ip = !isStart || serverName.isEmpty
        ? null
        : ipInfo != null
        ? Tooltip(
            message: appLocalizations.details(appLocalizations.outboundIp),
            child: InkWell(
              mouseCursor: clickableCursor,
              onTap: () => showIpQualitySheet(context, ip: ipInfo.ip),
              customBorder: AppShape.xs,
              child: Text(
                hideIp ? ipMask : ipInfo.ip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ipStyle,
              ),
            ),
          )
        : entry.isLoading
        ? SkeletonText(width: 110, style: ipStyle)
        : null;
    final recheck = isStart && !entry.isLoading
        ? () => ref.read(outboundIpProbeProvider.notifier).refresh(const [
            routedOutbound,
          ])
        : null;
    final swap = groups.isEmpty
        ? null
        : SizedBox(
            height: AppTextStyle.headline.leading,
            child: DashboardIconButton(
              glyph: AppGlyphs.swap,
              tooltip: appLocalizations.changeServer,
              onPressed: () => showProxiesSheet(context, groupName: groupName),
            ),
          );
    return DashboardCard(
      semanticLabel: appLocalizations.changeServer,
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
                  children: [
                    Flexible(
                      child: EmojiText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.headline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    ?swap,
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

Group? _pickedGroupOf(List<Group> groups, String? name) {
  if (name != null) {
    final named = groups.getGroup(name);
    if (named != null) {
      return named;
    }
  }
  for (final group in groups) {
    if (group.realNow.isNotEmpty && !isBuiltinOutbound(group.realNow)) {
      return group;
    }
  }
  return groups.firstOrNull;
}

/// The distinct flags in [group]'s proxy names, nested groups four deep.
List<String> _groupFlagsOf(List<Group> groups, Group group) {
  final codes = <String>{};
  void walk(Group group, int depth) {
    if (depth > 4) {
      return;
    }
    for (final proxy in group.all) {
      final code = proxy.name.flagCountryCode;
      if (code != null) {
        codes.add(code);
      } else if (groups.getGroup(proxy.name) case final nested?) {
        walk(nested, depth + 1);
      }
    }
  }

  walk(group, 0);
  return codes.toList();
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

/// Full width: filled with a play glyph while stopped, easing into an
/// outline in the primary color with a stop glyph and the run time while
/// running.
class _ConnectButton extends ConsumerWidget {
  const _ConnectButton();

  static const _duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final runTime = ref.watch(runTimeProvider);
    final label = suspended
        ? appLocalizations.suspended
        : isStart
        ? appLocalizations.stop
        : appLocalizations.start;
    final duration = context.motionDuration(_duration);
    void toggle() => ref.read(commonActionProvider.notifier).toggleRunning();
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: double.infinity,
          height: _connectHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: isStart ? 1 : 0),
            duration: duration,
            curve: Curves.easeInOut,
            builder: (context, progress, _) {
              final ink = Color.lerp(
                colorScheme.onPrimary,
                colorScheme.primary,
                progress,
              )!;
              final content = suspended
                  ? const GlyphIcon(AppGlyphs.wifiOff, size: 26, fill: 1)
                  : isStart
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 10,
                      children: [
                        const GlyphIcon(AppGlyphs.stop, size: 22, fill: 1),
                        Text(
                          getTimeText(runTime),
                          style: DashboardText.figure(
                            context,
                            AppTextStyle.headline,
                            color: ink,
                          ),
                        ),
                      ],
                    )
                  : GlyphIcon(AppGlyphs.playPause(0), size: 28, fill: 1);
              return FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary.withValues(
                    alpha: 1 - progress,
                  ),
                  foregroundColor: ink,
                  side: BorderSide(
                    color: colorScheme.primary.withValues(alpha: progress),
                    width: 1.5,
                  ),
                ),
                onPressed: toggle,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  child: KeyedSubtree(
                    key: ValueKey((isStart, suspended)),
                    child: content,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
