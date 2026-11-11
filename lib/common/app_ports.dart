import 'dart:ui' show Brightness, Color;

import 'package:fl_clash/common/provider_reader.dart';
import 'package:fl_clash/models/models.dart';

abstract interface class WindowPort {
  Future<WindowProps?> captureNormalGeometry(WindowProps current);

  /// Returns the opacity the sidebar keeps its own color at over the backdrop
  /// now drawn behind the content, or null when none is drawn.
  Future<double?> setBlur({
    required bool enabled,
    required Brightness brightness,
    required Color tint,
  });

  Future<void> show();

  Future<void> hide();

  Future<void> toggle();

  Future<void> close();

  void forceExit();
}

abstract interface class TrayPort {
  Future<void> shutdown();

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  });
}

abstract interface class NotificationPort {
  /// False when the system will not show it, so the caller says it another way.
  Future<bool> show({
    required String title,
    required String body,
    required String channelName,
    String? url,
  });
}

abstract interface class NavigationPort {
  List<NavigationItem> getItems({bool openLogs, bool hasProxies});
}

WindowPort? windowPort;
TrayPort? trayPort;
NavigationPort? navigationPort;
NotificationPort? notificationPort;
