import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flclashx/common/common.dart';
import 'package:flclashx/providers/state.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart';

class TrayManager extends ConsumerStatefulWidget {
  const TrayManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager> with TrayListener {
  Timer? _menuMonitor;

  void _closeWindowsPopupMenu() {
    if (!Platform.isWindows) return;

    try {
      final className = '#32768'.toNativeUtf16();
      final hwnd = FindWindow(className, nullptr);

      if (hwnd != 0) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }

      calloc.free(className);
    } catch (e) {}

    _stopMenuMonitor();
  }

  void _startMenuMonitor() {
    if (!Platform.isWindows) return;

    _menuMonitor?.cancel();
    var themeApplied = false;
    var waitCycles = 0;

    _menuMonitor = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      try {
        final className = '#32768'.toNativeUtf16();
        final hwnd = FindWindow(className, nullptr);
        calloc.free(className);

        if (hwnd == 0) {
          _stopMenuMonitor();
          return;
        }

        if (IsWindowVisible(hwnd) == 0) {
          _stopMenuMonitor();
          return;
        }

        if (!themeApplied) {
          windows?.applyDarkModeToMenu(hwnd);
          themeApplied = true;
        }

        if (waitCycles < 3) {
          waitCycles++;
          return;
        }

        final leftButtonPressed = GetAsyncKeyState(VK_LBUTTON) & 0x8000;
        final rightButtonPressed = GetAsyncKeyState(VK_RBUTTON) & 0x8000;

        if (leftButtonPressed != 0 || rightButtonPressed != 0) {
          final point = calloc<POINT>();
          GetCursorPos(point);

          final rect = calloc<RECT>();
          GetWindowRect(hwnd, rect);

          final cursorX = point.ref.x;
          final cursorY = point.ref.y;
          final menuLeft = rect.ref.left;
          final menuTop = rect.ref.top;
          final menuRight = rect.ref.right;
          final menuBottom = rect.ref.bottom;

          calloc.free(point);
          calloc.free(rect);

          if (cursorX < menuLeft ||
              cursorX > menuRight ||
              cursorY < menuTop ||
              cursorY > menuBottom) {
            PostMessage(hwnd, WM_CLOSE, 0, 0);
            _stopMenuMonitor();
          }
        }
      } catch (e) {
        _stopMenuMonitor();
      }
    });
  }

  void _stopMenuMonitor() {
    _menuMonitor?.cancel();
    _menuMonitor = null;
  }

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    ref.listenManual(
      trayStateProvider,
      (prev, next) {
        if (prev != next) {
          globalState.appController.updateTray();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
    _startMenuMonitor();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    _closeWindowsPopupMenu();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayIconMouseDown() {
    _closeWindowsPopupMenu();
    if (!Platform.isLinux) {
      window?.show();
    }
  }

  @override
  void dispose() {
    _stopMenuMonitor();
    trayManager.removeListener(this);
    super.dispose();
  }
}
