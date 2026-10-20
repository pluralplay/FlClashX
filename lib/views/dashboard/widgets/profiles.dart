import 'dart:async';

import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/custom/custom.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'profile_detail.dart';

typedef _Usage = ({int used, int total, double share});

_Usage? _usageOf(Profile? profile) {
  final info = profile?.subscriptionInfo;
  if (info == null || info.total <= 0) {
    return null;
  }
  final used = info.upload + info.download;
  return (
    used: used,
    total: info.total,
    share: (used / info.total).clamp(0.0, 1.0).toDouble(),
  );
}

DateTime? _expiryOf(Profile? profile) {
  final expire = profile?.subscriptionInfo?.expire ?? 0;
  return expire > 0 ? DateTime.fromMillisecondsSinceEpoch(expire * 1000) : null;
}

/// Counts down in days, then hours, then minutes, never reaching zero
/// before the plan actually ends.
String _timeLeftText(BuildContext context, Duration left) {
  final appLocalizations = context.appLocalizations;
  if (left.inDays >= 1) {
    return appLocalizations.profileDaysFigure(left.inDays);
  }
  if (left.inHours >= 1) {
    return appLocalizations.profileHoursFigure(left.inHours);
  }
  return appLocalizations.profileMinutesFigure(math.max(1, left.inMinutes));
}

void _openProfile(BuildContext context, Profile? profile) {
  switch (profile) {
    case null:
      showAddProfilePage(context);
    case Profile(type: ProfileType.custom, :final id):
      showCustomProfileSheet(context, id);
    case _:
      showProfileDetailSheet(context);
  }
}

const _nearlyUsedShare = 0.9;

/// The name row already carries the way to other profiles, so the header
/// keeps only the panel's two actions and gives them the room it saves.
const _actionGlyphSize = 22.0;

const _soonDays = 7;

class ProfilesCard extends ConsumerWidget {
  const ProfilesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = DashboardDensityScope.of(context);
    final mobile = !density.isDesktop;
    final compact = density.isCompact;
    final appLocalizations = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    final offers = ref.watch(profileOffersProvider);
    final switchable = ref.watch(
      profilesProvider.select((profiles) => profiles.length > 1),
    );
    final usage = _usageOf(profile);
    final expiry = _expiryOf(profile);
    final figure = mobile
        ? AppTextStyle.title3
        : (compact ? AppTextStyle.callout : AppTextStyle.headline);
    final name = mobile || !compact
        ? AppTextStyle.headline
        : AppTextStyle.callout;
    final sync = profile != null && profile.type == ProfileType.url
        ? _SyncButton(profile: profile)
        : null;
    final webPageUrl = profile?.headers.webPageUrl;
    final webPage = webPageUrl == null
        ? null
        : DashboardIconButton(
            glyph: AppGlyphs.globe,
            tooltip: appLocalizations.website,
            iconSize: _actionGlyphSize,
            onPressed: () => dialogs.openUrl(webPageUrl),
          );
    final supportUrl = profile?.headers.supportUrl;
    final support = supportUrl == null
        ? null
        : DashboardIconButton(
            glyph: AppGlyphs.support,
            tooltip: appLocalizations.support,
            iconSize: _actionGlyphSize,
            onPressed: () => dialogs.openUrl(supportUrl),
          );
    final nameRow = Row(
      children: [
        Flexible(
          child: EmojiText(
            profile?.realLabel ?? appLocalizations.addProfile,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: name.of(context, emphasized: true),
          ),
        ),
        if (profile != null && switchable)
          SizedBox(
            height: name.leading,
            child: DashboardIconButton(
              glyph: AppGlyphs.swap,
              tooltip: appLocalizations.switchProfile,
              onPressed: () => showProfilesSheet(context),
            ),
          ),
      ],
    );
    return DashboardCard(
      semanticLabel: appLocalizations.profile,
      onTap: mobile || profile == null
          ? () => _openProfile(context, profile)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.profiles,
            title: appLocalizations.profile,
            trailing: [?webPage, ?support, ?sync],
          ),
          SizedBox(height: mobile ? 12 : 10),
          nameRow,
          if (profile != null &&
              (expiry != null || usage != null || offers.isNotEmpty)) ...[
            if (mobile) const SizedBox(height: 14) else const Spacer(),
            _PlanFigures(
              expiry: expiry,
              usage: usage,
              offers: offers,
              figure: figure,
              gap: mobile ? 8 : 6,
            ),
          ],
        ],
      ),
    );
  }
}

const _rowGap = 12.0;

/// Spins while the update runs and shows a green check for a moment once
/// it went through.
class _SyncButton extends ConsumerStatefulWidget {
  const _SyncButton({required this.profile});

  static const doneDuration = Duration(seconds: 1);
  static const switchDuration = Duration(milliseconds: 150);

  final Profile profile;

  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> {
  Timer? _doneTimer;

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    final done = await syncProfile(ref, widget.profile);
    if (!done || !mounted) {
      return;
    }
    setState(() {
      _doneTimer?.cancel();
      _doneTimer = Timer(_SyncButton.doneDuration, () {
        if (mounted) {
          setState(() => _doneTimer = null);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final isUpdating = ref.watch(
      isUpdatingProvider(widget.profile.updatingKey),
    );
    final done = _doneTimer != null;
    final Widget child = isUpdating
        ? const SizedBox.square(
            key: ValueKey('updating'),
            dimension: 32,
            child: Center(child: CommonCircleLoading(size: 18)),
          )
        : DashboardIconButton(
            key: ValueKey(done),
            glyph: done ? AppGlyphs.check : AppGlyphs.sync,
            tooltip: appLocalizations.update,
            iconSize: _actionGlyphSize,
            color: done ? context.colorScheme.success : null,
            onPressed: _sync,
          );
    return AnimatedSwitcher(
      duration: context.motionDuration(_SyncButton.switchDuration),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: child,
    );
  }
}

/// How long the plan runs and how much of it is left, the traffic on a
/// bar under them.
class _PlanFigures extends StatelessWidget {
  const _PlanFigures({
    required this.expiry,
    required this.usage,
    required this.offers,
    required this.figure,
    required this.gap,
  });

  final DateTime? expiry;
  final _Usage? usage;
  final List<ProfileOffer> offers;
  final AppTextStyle figure;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colors = DashboardColors.of(context);
    final expiry = this.expiry;
    final usage = this.usage;
    final left = expiry?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final soon = left != null && left.inDays <= _soonDays;
    final nearlyUsed = usage != null && usage.share >= _nearlyUsedShare;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expiry != null || usage != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _rowGap,
            children: [
              Expanded(
                child: _Figure(
                  value: left == null
                      ? appLocalizations.profileNoExpiry
                      : expired
                      ? appLocalizations.profileExpired
                      : _timeLeftText(context, left),
                  label: expiry == null
                      ? null
                      : appLocalizations.profileUntil(expiry.showDate),
                  tone: expired || soon ? colors.warn : null,
                  figure: figure,
                ),
              ),
              Expanded(
                child: _Figure(
                  value: usage == null
                      ? appLocalizations.profileTrafficUnlimited
                      : dashboardTraffic(math.max(0, usage.total - usage.used)),
                  label: usage == null
                      ? null
                      : appLocalizations.profileLeftOfTotal(
                          dashboardTraffic(usage.total),
                        ),
                  tone: nearlyUsed ? colors.warn : null,
                  figure: figure,
                  end: true,
                ),
              ),
            ],
          ),
        if (usage != null) ...[
          SizedBox(height: gap),
          _UsageBar(
            value: usage.share,
            active: nearlyUsed ? colors.warn : context.colorScheme.primary,
            track: colors.tone2,
          ),
        ],
        if (offers.isNotEmpty) ...[
          SizedBox(height: gap + 4),
          Row(
            spacing: 8,
            children: [
              for (final offer in offers)
                Expanded(child: _OfferButton(offer: offer)),
            ],
          ),
        ],
      ],
    );
  }
}

/// The panel's link to renew or top up, behind the external link prompt,
/// filled like the start button.
class _OfferButton extends StatelessWidget {
  const _OfferButton({required this.offer});

  final ProfileOffer offer;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final label = switch (offer.kind) {
      ProfileOfferKind.buyPlan => appLocalizations.buyPlan,
      ProfileOfferKind.buyTraffic => appLocalizations.buyTraffic,
    };
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: () => dialogs.openUrl(offer.url),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: AppTextStyle.footnote.of(context, emphasized: true),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.tone,
    required this.figure,
    this.end = false,
  });

  final String value;
  final String? label;
  final Color? tone;
  final AppTextStyle figure;
  final bool end;

  @override
  Widget build(BuildContext context) {
    final alignment = end
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final label = this.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            value,
            maxLines: 1,
            style: DashboardText.figure(
              context,
              figure,
              color: tone,
            ).copyWith(letterSpacing: 0),
          ),
        ),
        if (label != null)
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: DashboardText.label(context),
          ),
      ],
    );
  }
}

/// A pill track with the used share filled from the start.
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.value,
    required this.active,
    required this.track,
  });

  final double value;
  final Color active;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: AppRadius.full,
      child: SizedBox(
        height: 6,
        child: ColoredBox(
          color: track,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0, 1),
              heightFactor: 1,
              child: ClipRSuperellipse(
                borderRadius: AppRadius.full,
                child: ColoredBox(color: active),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
