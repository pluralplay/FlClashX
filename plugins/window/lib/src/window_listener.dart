import 'package:window/src/window_event.dart';

abstract mixin class WindowListener {
  void onWindowClose() {}

  void onWindowFocus() {}

  void onWindowBlur() {}

  void onWindowShow() {}

  void onWindowHide() {}

  void onWindowMaximize() {}

  void onWindowUnmaximize() {}

  void onWindowMinimize() {}

  void onWindowRestore() {}

  void onWindowGeometryChanged() {}

  void onWindowEnterFullScreen() {}

  void onWindowLeaveFullScreen() {}

  void onWindowShouldTerminate() {}

  void onWindowActivate() {}

  /// macOS: the zoom button was pressed; the window neither zooms nor goes
  /// full screen on its own.
  void onWindowZoom() {}

  void onWindowEvent(WindowEvent event) {}
}
