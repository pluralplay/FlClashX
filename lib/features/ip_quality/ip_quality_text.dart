import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'labels.dart';

class IpQualityText extends ConsumerWidget {
  const IpQualityText({super.key, required this.ip, this.style});

  final String ip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(ipQualityProvider(ip)).value;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    if (hideIp) {
      return const SizedBox.shrink();
    }
    final color = quality?.level.color(context);
    var style = this.style;
    if (color != null) {
      style = (style ?? const TextStyle()).copyWith(color: color);
    }
    return Tooltip(
      preferBelow: false,
      message: ip,
      child: Text(
        ip,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
