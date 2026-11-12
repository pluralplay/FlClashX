import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// Pinned to English so every locale reads K and M, never 万 or тыс.
final _compactFormat = NumberFormat.compact(locale: 'en');

extension NumExt on num {
  String get compact => _compactFormat.format(this);

  String fixed({int decimals = 2}) {
    String formatted = toStringAsFixed(decimals);
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0*$'), '');
      if (formatted.endsWith('.')) {
        formatted = formatted.substring(0, formatted.length - 1);
      }
    }
    return formatted;
  }

  TrafficShow get traffic {
    const units = TrafficUnit.values;
    var size = toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return TrafficShow(
      value: size.fixed(decimals: 1),
      unit: units[unitIndex].name,
    );
  }

  TrafficShow get shortTraffic {
    const units = TrafficUnit.values;
    var size = toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return TrafficShow(
      value: size.toStringAsFixed(0),
      unit: ' ${units[unitIndex].name}',
    );
  }
}
