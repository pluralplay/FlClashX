import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class TileListener {
  void onStart() {}

  void onStop() {}

  void onDetached(){

  }
}

class Tile {

  Tile._() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  final MethodChannel _channel = const MethodChannel('tile');

  static final Tile instance = Tile._();

  final ObserverList<TileListener> _listeners = ObserverList<TileListener>();

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final listener in _listeners) {
      switch (call.method) {
        case "start":
          listener.onStart();
          break;
        case "stop":
          listener.onStop();
          break;
        case "detached":
          listener.onDetached();
          break;
      }
    }
  }

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(TileListener listener) {
    _listeners.add(listener);
  }

  void removeListener(TileListener listener) {
    _listeners.remove(listener);
  }
  
  Future<void> updateTile() async {
    try {
      await _channel.invokeMethod('updateTile');
    } catch (e) {
      // Ignore errors if tile service not available
    }
  }
  
  /// Signal to native side that Dart service is ready to receive commands.
  /// This should be called after _service entrypoint has finished initialization.
  Future<void> signalServiceReady() async {
    try {
      await _channel.invokeMethod('serviceReady');
    } catch (e) {
      // Ignore errors if tile service not available
    }
  }
}

final tile =  Platform.isAndroid ? Tile.instance : null;
