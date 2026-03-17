import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class Window {
  Future<void> init(int version) async {
    final props = globalState.config.windowProps;
    final acquire = await singleInstanceLock.acquire();
    if (!acquire) {
      exit(0);
    }
    if (Platform.isWindows) {
      protocol.register("clashx");
      protocol.register("flclash");
      protocol.register("flclashx");
    }

    // On macOS, the app runs in status bar with popover - no window manager needed
    if (Platform.isMacOS) {
      return;
    }

    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: Size(props.width, props.height),
      minimumSize: const Size(380, 400),
    );
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    if (!Platform.isMacOS) {
      final left = props.left ?? 0;
      final top = props.top ?? 0;
      final right = left + props.width;
      final bottom = top + props.height;
      if (left == 0 && top == 0) {
        await windowManager.setAlignment(Alignment.center);
      } else {
        final displays = await screenRetriever.getAllDisplays();
        final isPositionValid = displays.any(
          (display) {
            final displayBounds = Rect.fromLTWH(
              display.visiblePosition!.dx,
              display.visiblePosition!.dy,
              display.size.width,
              display.size.height,
            );
            return displayBounds.contains(Offset(left, top)) ||
                displayBounds.contains(Offset(right, bottom));
          },
        );
        if (isPositionValid) {
          await windowManager.setPosition(
            Offset(
              left,
              top,
            ),
          );
        }
      }
    }
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
    });
  }

  Future<void> show() async {
    if (Platform.isMacOS) return;

    render?.resume();
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  }

  Future<bool> get isVisible async {
    if (Platform.isMacOS) return false;

    final value = await windowManager.isVisible();
    commonPrint.log("window visible check: $value");
    return value;
  }

  Future<void> close() async {
    exit(0);
  }

  Future<void> hide() async {
    if (Platform.isMacOS) return;

    render?.pause();
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }
}

final window = system.isDesktop ? Window() : null;
