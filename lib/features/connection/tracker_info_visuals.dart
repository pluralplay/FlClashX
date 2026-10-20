import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

typedef OutboundTone = ({Color color, Color foreground});

OutboundTone _neutralTone(BuildContext context) {
  final colorScheme = context.colorScheme;
  return (
    color: context.raisedSurfaceLevel.colorOf(colorScheme),
    foreground: colorScheme.onSurfaceVariant,
  );
}

/// Where the traffic ends up, told apart by colour: direct, blocked or a node.
OutboundTone outboundTone(BuildContext context, String name) {
  final colorScheme = context.colorScheme;
  final upper = name.toUpperCase();
  if (upper == 'DIRECT') {
    return (
      color: colorScheme.successContainer,
      foreground: colorScheme.onSuccessContainer,
    );
  }
  if (upper.startsWith('REJECT') || upper == 'BLOCK') {
    return (
      color: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
    );
  }
  if (upper == 'PASS' || upper == 'COMPATIBLE') {
    return _neutralTone(context);
  }
  return (
    color: colorScheme.primaryContainer,
    foreground: colorScheme.onPrimaryContainer,
  );
}

class OutboundChip extends StatelessWidget {
  final String label;
  final bool exit;
  final VoidCallback? onPressed;

  const OutboundChip({
    super.key,
    required this.label,
    this.exit = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tone = exit ? outboundTone(context, label) : _neutralTone(context);
    return TonalChip(
      label: label,
      color: tone.color,
      foregroundColor: tone.foreground,
      onPressed: onPressed,
    );
  }
}

class NetworkLabel extends StatelessWidget {
  final String network;

  const NetworkLabel(this.network, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final tone = switch (network.toLowerCase()) {
      'tcp' => (
        color: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
      ),
      'udp' => (
        color: colorScheme.tertiaryContainer,
        foreground: colorScheme.onTertiaryContainer,
      ),
      _ => _neutralTone(context),
    };
    return TonalChip(
      label: network.toUpperCase(),
      color: tone.color,
      foregroundColor: tone.foreground,
    );
  }
}

String? destinationCountryOf(TrackerInfo trackerInfo) {
  for (final code in trackerInfo.metadata.destinationGeoIP) {
    if (CountryFlag.has(code)) {
      return code.toLowerCase();
    }
  }
  return null;
}

class CountryMark extends StatelessWidget {
  final String countryCode;
  final double size;

  const CountryMark({super.key, required this.countryCode, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: AppRadius.all(size / 4),
      child: SizedBox.square(
        dimension: size,
        child: CountryFlag(countryCode: countryCode),
      ),
    );
  }
}

class LetterAvatar extends StatelessWidget {
  final String text;
  final double size;

  const LetterAvatar(this.text, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final trimmed = text.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.secondaryContainer,
        shape: AppShape.all(size / 4),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            letter,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}

/// The app's icon where the platform knows it, else the destination's flag,
/// else the first letter of the host.
class TrackerAvatar extends StatelessWidget {
  final TrackerInfo trackerInfo;
  final double size;
  final bool packageIcon;
  final VoidCallback? onTap;

  const TrackerAvatar({
    super.key,
    required this.trackerInfo,
    this.size = 28,
    this.packageIcon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final process = trackerInfo.metadata.process;
    final country = destinationCountryOf(trackerInfo);
    final Widget avatar;
    if (packageIcon && process.isNotEmpty) {
      avatar = ClipRSuperellipse(
        borderRadius: AppRadius.all(size / 4),
        child: PackageIcon(packageName: process, size: size),
      );
    } else if (country != null) {
      avatar = CountryMark(countryCode: country, size: size);
    } else {
      avatar = LetterAvatar(trackerInfo.title, size: size);
    }
    final onTap = this.onTap;
    if (onTap == null) {
      return avatar;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: avatar),
    );
  }
}

class RuleLabel extends StatelessWidget {
  final TrackerInfo trackerInfo;
  final VoidCallback? onPressed;

  const RuleLabel(this.trackerInfo, {super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tone = _neutralTone(context);
    final payload = trackerInfo.rulePayload;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        TonalChip(
          label: trackerInfo.rule,
          color: tone.color,
          foregroundColor: tone.foreground,
          onPressed: onPressed,
        ),
        if (payload.isNotEmpty)
          Flexible(
            child: Text(
              payload,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class SpeedText extends StatelessWidget {
  final int upload;
  final int download;

  const SpeedText({super.key, required this.upload, required this.download});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final muted = colorScheme.onSurfaceVariant;
    InlineSpan part(Glyph glyph, int amount, Color active) {
      final color = amount > 0 ? active : muted;
      return TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GlyphIcon(glyph, size: 12, color: color),
          ),
          TextSpan(
            text: ' ${amount.traffic.show}/s',
            style: TextStyle(color: color),
          ),
        ],
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          part(AppGlyphs.arrowUp, upload, colorScheme.tertiary),
          const TextSpan(text: '   '),
          part(AppGlyphs.arrowDown, download, colorScheme.primary),
        ],
      ),
    );
  }
}
