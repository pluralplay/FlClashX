import 'dart:async';

import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flutter/foundation.dart';

class ClashMessage {

  ClashMessage._() {
    controller.stream.listen(
      (message) {
        if (message.isEmpty) {
          return;
        }
        final m = AppMessage.fromJson(message);
        for (final listener in _listeners) {
          switch (m.type) {
            case AppMessageType.log:
              listener.onLog(Log.fromJson(m.data));
              break;
            case AppMessageType.delay:
              listener.onDelay(Delay.fromJson(m.data));
              break;
            case AppMessageType.request:
              listener.onRequest(Connection.fromJson(m.data));
              break;
            case AppMessageType.loaded:
              listener.onLoaded(m.data);
              break;
          }
        }
      },
    );
  }
  final controller = StreamController<Map<String, Object?>>();

  static final ClashMessage instance = ClashMessage._();

  final ObserverList<AppMessageListener> _listeners =
      ObserverList<AppMessageListener>();

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(AppMessageListener listener) {
    _listeners.add(listener);
  }

  void removeListener(AppMessageListener listener) {
    _listeners.remove(listener);
  }
}

final clashMessage = ClashMessage.instance;
