import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'style.dart';

/// The widest the start button grows on a wide dashboard.
const providerConnectMaxWidth = 520.0;

const _logoSize = 56.0;
const _connectHeight = 56.0;

/// The service's logo and name over a `providermode` dashboard: `nologo`
/// leaves the logo out and sets the name a size larger, `noservice` leaves the
/// whole line out.
class ProviderHeader extends ConsumerWidget {
  const ProviderHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(currentProfileProvider)?.headers;
    if (headers == null || headers.noService) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 12,
      children: [
        if (!headers.noLogo) _ServiceLogo(url: headers.serviceLogo),
        Flexible(
          child: EmojiText(
            headers.serviceName ?? appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (headers.noLogo ? AppTextStyle.title1 : AppTextStyle.title2)
                .of(context, emphasized: true),
          ),
        ),
      ],
    );
  }
}

/// The panel's logo, png or svg, else the app's own icon.
class _ServiceLogo extends ConsumerWidget {
  const _ServiceLogo({this.url});

  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = this.url;
    final fallback = Image.asset(
      'assets/images/icon.png',
      width: _logoSize,
      height: _logoSize,
      fit: BoxFit.cover,
    );
    final path = url == null
        ? null
        : ref.watch(panelLogoPathProvider(url)).value;
    final Widget logo = url == null || path == null
        ? fallback
        : url.toLowerCase().endsWith('.svg')
        ? SvgPicture.file(
            File(path),
            width: _logoSize,
            height: _logoSize,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => fallback,
          )
        : Image.file(
            File(path),
            width: _logoSize,
            height: _logoSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return ClipRSuperellipse(
      borderRadius: AppRadius.md,
      child: SizedBox.square(dimension: _logoSize, child: logo),
    );
  }
}

/// The start button at the foot of a `providermode` dashboard: filled with a
/// play glyph while stopped, easing into an outline in the primary color with
/// a stop glyph and the run time while running.
class ProviderConnectButton extends ConsumerWidget {
  const ProviderConnectButton({super.key});

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
        child: RisingHold(
          enabled: system.isAndroid,
          onHeld: toggle,
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
      ),
    );
  }
}
