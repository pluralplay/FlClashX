import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_ports.dart';
import 'constant.dart';
import 'print.dart';
import 'system.dart';

const _channelId = 'subscription';
const _windowsGuid = 'd1075ef0-c7d2-42bc-8f5c-c79bdf4d2c24';

/// Notifications in the system tray or shade, with a link opened on tap.
class SystemNotifications implements NotificationPort {
  SystemNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void> Function(String url) openUrl = (url) =>
      launchUrl(Uri.parse(url));
  bool? _ready;
  int _nextId = 0;

  Future<bool> _prepare() async {
    if (_ready case final ready?) {
      return ready;
    }
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_service'),
          macOS: DarwinInitializationSettings(requestBadgePermission: false),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: appName,
            appUserModelId: 'com.follow.clashx',
            guid: _windowsGuid,
          ),
        ),
        onDidReceiveNotificationResponse: _onTap,
      );
      _ready = initialized ?? false;
      if (_ready == true && system.isAndroid) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        _ready = granted ?? true;
      }
    } catch (error) {
      commonPrint.log(
        'system notifications unavailable: $error',
        logLevel: LogLevel.warning,
      );
      _ready = false;
    }
    return _ready!;
  }

  void _onTap(NotificationResponse response) {
    final url = response.payload;
    if (url != null && url.isNotEmpty) {
      unawaited(openUrl(url));
    }
  }

  @override
  Future<bool> show({
    required String title,
    required String body,
    required String channelName,
    String? url,
  }) async {
    if (!await _prepare()) {
      return false;
    }
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        payload: url,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          macOS: const DarwinNotificationDetails(),
          linux: const LinuxNotificationDetails(),
          windows: const WindowsNotificationDetails(),
        ),
      );
      return true;
    } catch (error) {
      commonPrint.log(
        'system notification failed: $error',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }
}

final systemNotifications = SystemNotifications();
