import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/config.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window/window.dart';

class Window implements WindowPort {
  static const _tintOpacity = 0.5;
  static Window? _instance;
  bool _supportsPosition = false;
  bool _canPosition = false;
  bool _menuBarMode = false;
  WindowEffect? _blurEffect;
  late final WindowVisibilityController _visibility =
      WindowVisibilityController(
        showWindow: _showWindow,
        hideWindow: _hideWindow,
        isWindowVisible: _isWindowVisible,
        // The menu bar app stays out of the Dock whatever its popover does.
        setSkipTaskbar: (skip) =>
            desktopWindow.setSkipTaskbar(skip || _menuBarMode),
        dockSettleDuration: system.isMacOS
            ? const Duration(seconds: 1)
            : Duration.zero,
      );

  Window._internal();

  factory Window() {
    _instance ??= Window._internal();
    return _instance!;
  }

  Future<void> init(
    int version,
    WindowProps props, {
    bool menuBarMode = false,
  }) async {
    if (!safeModeBuild) {
      if (system.isWindows) {
        for (final scheme in protocolSchemes) {
          protocol.register(scheme);
        }
      }
      if (system.isLinux) {
        unawaited(protocol.registerLinux(protocolSchemes));
      }
    }
    await desktopWindow.ensureInitialized();
    if (!system.isMacOS || version > 10) {
      await desktopWindow.setTitleBarStyle(TitleBarStyle.hidden);
    }
    await placeWindow(props);
    await desktopWindow.setPreventClose(true);
    if (menuBarMode) {
      await setMenuBarMode(true);
    }
  }

  bool get isMenuBarMode => _menuBarMode;

  /// macOS only: the window becomes a popover under the status item.
  Future<void> setMenuBarMode(bool enabled) async {
    if (!system.isMacOS || enabled == _menuBarMode) {
      return;
    }
    _menuBarMode = enabled;
    await desktopWindow.setMenuBarMode(enabled);
    await desktopWindow.setSkipTaskbar(enabled);
  }

  /// A window goes back where it was left while its title bar is on a screen.
  /// Otherwise it opens at the top of the primary work area, no taller than it:
  /// centered, a window taller than a small screen put the bar it is dragged
  /// by above the screen, out of reach.
  @visibleForTesting
  Future<void> placeWindow(WindowProps props) async {
    _canPosition = !system.isLinux || await desktopWindow.isPositionSupported();
    _supportsPosition = _canPosition && !system.isMacOS;
    final Rect workArea;
    final List<Display> displays;
    try {
      displays = await screenRetriever.getAllDisplays();
      workArea = workAreaOf(await screenRetriever.getPrimaryDisplay());
    } catch (_) {
      await _resize(props.savedSize ?? defaultWindowSize);
      return;
    }
    final restored =
        _supportsPosition && props.left != null && props.top != null
        ? restoredWindowPosition(
            props,
            displays: displays,
            currentScale: system.isWindows ? _windowScale : null,
          )
        : null;
    if (restored != null) {
      await _resize(props.size);
      await desktopWindow.setPosition(restored);
      return;
    }
    final size = switch (props.savedSize) {
      final saved? => Size(
        math.min(saved.width, workArea.width),
        math.min(saved.height, workArea.height),
      ),
      null => fittedWindowSize(workArea.size),
    };
    await _resize(size);
    if (_canPosition) {
      await desktopWindow.setPosition(topOfWorkArea(size, workArea));
    }
  }

  /// Windows holds a resize to the minimum size, so on a work area smaller
  /// than that the minimum gives way to the size the window was fitted to.
  Future<void> _resize(Size size) async {
    await desktopWindow.setMinimumSize(
      Size(math.min(380, size.width), math.min(400, size.height)),
    );
    await desktopWindow.setSize(size);
  }

  double get _windowScale =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;

  @override
  Future<WindowProps?> captureNormalGeometry(WindowProps current) async {
    final states = await Future.wait<bool>([
      desktopWindow.isMaximized(),
      desktopWindow.isFullScreen(),
      desktopWindow.isMinimized(),
    ]);
    if (states.any((state) => state)) {
      return null;
    }

    final bounds = await desktopWindow.getBounds();
    if (!bounds.width.isFinite ||
        !bounds.height.isFinite ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }
    final hasValidPosition =
        bounds.left.isFinite && bounds.top.isFinite && _supportsPosition;
    return current.copyWith(
      width: bounds.width,
      height: bounds.height,
      left: hasValidPosition ? bounds.left : current.left,
      top: hasValidPosition ? bounds.top : current.top,
      scale: hasValidPosition && system.isWindows
          ? _windowScale
          : current.scale,
    );
  }

  /// A probe that finds no effect is not cached, so a failure at startup
  /// does not pin the toggle to off for the rest of the session.
  Future<WindowEffect> _resolveBlurEffect() async {
    final cached = _blurEffect;
    if (cached != null) {
      return cached;
    }
    final candidates = system.isMacOS
        ? const [WindowEffect.glass, WindowEffect.blur]
        : const [WindowEffect.mica, WindowEffect.acrylic, WindowEffect.blur];
    for (final effect in candidates) {
      if (await desktopWindow.isEffectSupported(effect)) {
        return _blurEffect = effect;
      }
    }
    return WindowEffect.none;
  }

  /// Only Windows 10's accent blur takes the tint natively; it draws nothing
  /// without one. Every material still keeps the sidebar's own color half over
  /// it, or the rail takes the hue of whatever lies behind the window while
  /// the content beside it keeps the theme's.
  @override
  Future<double?> setBlur({
    required bool enabled,
    required Brightness brightness,
    required Color tint,
  }) async {
    if (system.isLinux) {
      return null;
    }
    final effect = enabled ? await _resolveBlurEffect() : WindowEffect.none;
    await desktopWindow.setEffect(
      effect,
      tint: system.isWindows ? tint.withValues(alpha: _tintOpacity) : null,
      brightness: brightness,
    );
    return effect == WindowEffect.none ? null : _tintOpacity;
  }

  /// Every desktop runner leaves the window hidden until [init] reveals it, so
  /// a failure before that point would leave the error screen with no window.
  Future<void> showInitFailure({required AsyncCallback onExit}) async {
    await holdBeforeInit(onExit: onExit);
  }

  /// Returns the release, which hands closing back to [init].
  Future<VoidCallback> holdBeforeInit({required AsyncCallback onExit}) async {
    final listener = _InitFailureWindowListener(onExit);
    desktopWindow.addListener(listener);
    await showBeforeInit(preventClose: true);
    return () => desktopWindow.removeListener(listener);
  }

  /// Closing the window then quits the app, which [init] changes later.
  Future<void> showBeforeInit({bool preventClose = false}) async {
    try {
      await desktopWindow.ensureInitialized();
      if (preventClose) {
        await desktopWindow.setPreventClose(true);
      }
      await desktopWindow.setTitleBarStyle(TitleBarStyle.normal);
      if (await desktopWindow.isVisible()) {
        return;
      }
      await desktopWindow.setSize(const Size(680, 580));
      await desktopWindow.center();
      await desktopWindow.show();
      await desktopWindow.focus();
    } catch (e) {
      commonPrint.log(
        'show window before init failed ${e.toString()}',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  Future<void> show() => _visibility.show();

  @override
  Future<void> hide() => _visibility.hide();

  @override
  Future<void> toggle() => _visibility.toggle();

  Future<void> _showWindow() async {
    await desktopWindow.show();
    await desktopWindow.focus();
  }

  Future<void> _hideWindow() async {
    await desktopWindow.hide();
  }

  Future<bool> _isWindowVisible() async {
    return desktopWindow.isVisible();
  }

  @override
  Future<void> close() async {
    await desktopWindow.close();
  }

  @override
  void forceExit() {
    exit(0);
  }
}

/// What a display leaves windows, the menu bar, Dock and taskbar taken out.
@visibleForTesting
Rect workAreaOf(Display display) =>
    (display.visiblePosition ?? Offset.zero) &
    (display.visibleSize ?? display.size);

/// Centered across [workArea], against its top edge.
@visibleForTesting
Offset topOfWorkArea(Size window, Rect workArea) => Offset(
  workArea.left + math.max(0, workArea.width - window.width) / 2,
  workArea.top,
);

/// Keeps a margin of the work area around a first window on a small screen.
@visibleForTesting
Size fittedWindowSize(Size visible) => Size(
  math.min(defaultWindowSize.width, visible.width * 0.9),
  math.min(defaultWindowSize.height, visible.height * 0.9),
);

/// On Windows the plugin scales by the window's monitor and screen_retriever by
/// each display's own, so only physical pixels compare across mixed scales.
/// The window is dragged by its top, so that is what has to be on a screen.
@visibleForTesting
Offset? restoredWindowPosition(
  WindowProps props, {
  required List<Display> displays,
  double? currentScale,
}) {
  final savedScale = currentScale == null ? 1.0 : props.scale ?? currentScale;
  final topLeft = Offset(props.left!, props.top!) * savedScale;
  final titleBar =
      topLeft +
      Offset(props.size.width / 2, math.min(props.size.height, 32) / 2) *
          savedScale;
  final isVisible = displays.any((display) {
    if (display.visiblePosition == null) {
      return false;
    }
    final scale = currentScale == null
        ? 1.0
        : display.scaleFactor?.toDouble() ?? 1.0;
    final bounds = workAreaOf(display);
    final physical = Rect.fromLTRB(
      bounds.left * scale,
      bounds.top * scale,
      bounds.right * scale,
      bounds.bottom * scale,
    );
    return physical.contains(titleBar);
  });
  return isVisible ? topLeft / (currentScale ?? 1.0) : null;
}

class _InitFailureWindowListener with WindowListener {
  final AsyncCallback onExit;

  _InitFailureWindowListener(this.onExit);

  @override
  void onWindowClose() => unawaited(onExit());

  @override
  void onWindowShouldTerminate() => unawaited(onExit());
}

/// Serializes visibility requests so a burst of hotkey toggles lands in
/// order, and holds back the Dock-hiding activation policy switch while a
/// preceding regular switch settles: flipping regular → accessory → regular
/// within about a second leaves macOS with stray Dock icons.
class WindowVisibilityController {
  WindowVisibilityController({
    required Future<void> Function() showWindow,
    required Future<void> Function() hideWindow,
    required Future<bool> Function() isWindowVisible,
    required Future<void> Function(bool skip) setSkipTaskbar,
    required this.dockSettleDuration,
  }) : _showWindow = showWindow,
       _hideWindow = hideWindow,
       _isWindowVisible = isWindowVisible,
       _setSkipTaskbar = setSkipTaskbar;

  final Future<void> Function() _showWindow;
  final Future<void> Function() _hideWindow;
  final Future<bool> Function() _isWindowVisible;
  final Future<void> Function(bool skip) _setSkipTaskbar;
  final Duration dockSettleDuration;

  Future<void>? _queue;
  Timer? _dockSettleTimer;
  bool _dockHidePending = false;

  Future<void> show() => _enqueue(_show);

  Future<void> hide() => _enqueue(_hide);

  Future<void> toggle() => _enqueue(() async {
    if (await _isWindowVisible()) {
      await _hide();
    } else {
      await _show();
    }
  });

  Future<void> _enqueue(Future<void> Function() step) {
    final previous = _queue;
    final result = previous == null ? step() : previous.then((_) => step());
    final tail = result.catchError((_) {});
    _queue = tail;
    tail.whenComplete(() {
      if (identical(_queue, tail)) {
        _queue = null;
      }
    });
    return result;
  }

  Future<void> _show() async {
    _dockHidePending = false;
    await _showWindow();
    await _setSkipTaskbar(false);
    _dockSettleTimer?.cancel();
    _dockSettleTimer = dockSettleDuration == Duration.zero
        ? null
        : Timer(dockSettleDuration, _onDockSettled);
  }

  Future<void> _hide() async {
    await _hideWindow();
    if (_dockSettleTimer?.isActive ?? false) {
      _dockHidePending = true;
      return;
    }
    await _setSkipTaskbar(true);
  }

  void _onDockSettled() {
    _dockSettleTimer = null;
    if (!_dockHidePending) {
      return;
    }
    unawaited(
      _enqueue(() async {
        if (!_dockHidePending) {
          return;
        }
        _dockHidePending = false;
        await _setSkipTaskbar(true);
      }),
    );
  }
}

final window = system.isDesktop ? Window() : null;
