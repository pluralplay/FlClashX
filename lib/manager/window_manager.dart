import 'dart:async';
import 'dart:io';

import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/providers/config.dart';
import 'package:flclashx/providers/app.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_ext/window_ext.dart';
import 'package:window_manager/window_manager.dart';

class WindowManager extends ConsumerStatefulWidget {

  const WindowManager({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  ConsumerState<WindowManager> createState() => _WindowContainerState();
}

class _WindowContainerState extends ConsumerState<WindowManager>
    with WindowListener, WindowExtListener {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      appSettingProvider.select((state) => state.autoLaunch),
      (prev, next) {
        if (prev != next) {
          debouncer.call(
            FunctionTag.autoLaunch,
            () {
              autoLaunch?.updateStatus(next);
            },
          );
        }
      },
    );
    // On macOS, we still need windowExtManager for quit handling, but not windowManager
    windowExtManager.addListener(this);
    if (!Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowClose() async {
    await globalState.appController.handleBackOrExit();
    super.onWindowClose();
  }

  @override
  void onWindowFocus() {
    super.onWindowFocus();
    commonPrint.log("focus");
    render?.resume();
  }

  @override
  Future<void> onShouldTerminate() async {
    await globalState.appController.handleExit();
    super.onShouldTerminate();
  }

  @override
  Future<void> onWindowMoved() async {
    super.onWindowMoved();
    final offset = await windowManager.getPosition();
    ref.read(windowSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            top: offset.dy,
            left: offset.dx,
          ),
        );
  }

  @override
  Future<void> onWindowResized() async {
    super.onWindowResized();
    final size = await windowManager.getSize();
    ref.read(windowSettingProvider.notifier).updateState(
          (state) => state.copyWith(
            width: size.width,
            height: size.height,
          ),
        );
  }

  @override
  void onWindowMinimize() async {
    globalState.appController.savePreferencesDebounce();
    commonPrint.log("minimize");
    render?.pause();
    super.onWindowMinimize();
  }

  @override
  void onWindowRestore() {
    commonPrint.log("restore");
    render?.resume();
    super.onWindowRestore();
  }

  @override
  Future<void> dispose() async {
    windowExtManager.removeListener(this);
    if (!Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }
}

class WindowHeaderContainer extends StatelessWidget {

  const WindowHeaderContainer({
    super.key,
    required this.child,
  });
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return child;
    }

    return Consumer(
      builder: (_, ref, child) => Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: kHeaderHeight,
                ),
                Expanded(
                  flex: 1,
                  child: child!,
                ),
              ],
            ),
            const WindowHeader(),
          ],
        ),
      child: child,
    );
  }
}

class WindowHeader extends StatefulWidget {
  const WindowHeader({super.key});

  @override
  State<WindowHeader> createState() => _WindowHeaderState();
}

class _WindowHeaderState extends State<WindowHeader> {
  final isMaximizedNotifier = ValueNotifier<bool>(false);
  final isPinNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    if (!Platform.isMacOS) {
      _initNotifier();
    }
  }

  Future<void> _initNotifier() async {
    isMaximizedNotifier.value = await windowManager.isMaximized();
    isPinNotifier.value = await windowManager.isAlwaysOnTop();
  }

  @override
  void dispose() {
    isMaximizedNotifier.dispose();
    isPinNotifier.dispose();
    super.dispose();
  }

  Future<void> _updateMaximized() async {
    final isMaximized = await windowManager.isMaximized();
    switch (isMaximized) {
      case true:
        await windowManager.unmaximize();
        break;
      case false:
        await windowManager.maximize();
        break;
    }
    isMaximizedNotifier.value = await windowManager.isMaximized();
  }

  Future<void> _updatePin() async {
    final isAlwaysOnTop = await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(!isAlwaysOnTop);
    isPinNotifier.value = await windowManager.isAlwaysOnTop();
  }

  // Windows 11 style window control button
  Widget _buildWindowButton({
    required Widget icon,
    required VoidCallback onPressed,
    Color? hoverColor,
    Color? hoverIconColor,
  }) {
    return _WindowControlButton(
      icon: icon,
      onPressed: onPressed,
      hoverColor: hoverColor,
      hoverIconColor: hoverIconColor,
    );
  }

  Widget _buildActions(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pin button
        _buildWindowButton(
          icon: ValueListenableBuilder(
            valueListenable: isPinNotifier,
            builder: (_, value, ___) => Icon(
              value ? Icons.push_pin : Icons.push_pin_outlined,
              size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          onPressed: _updatePin,
        ),
        // Minimize button
        _buildWindowButton(
          icon: Icon(
            Icons.remove,
            size: 18,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          onPressed: windowManager.minimize,
        ),
        // Maximize/Restore button
        _buildWindowButton(
          icon: ValueListenableBuilder(
            valueListenable: isMaximizedNotifier,
            builder: (_, value, ___) => Icon(
              value ? Icons.filter_none : Icons.crop_square,
              size: value ? 14 : 16,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          onPressed: _updateMaximized,
        ),
        // Close button - red hover
        _buildWindowButton(
          icon: Icon(
            Icons.close,
            size: 18,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          onPressed: () => globalState.appController.handleBackOrExit(),
          hoverColor: const Color.fromARGB(255, 238, 44, 60),
          hoverIconColor: Colors.white,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: Container(
        height: kHeaderHeight,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Stack(
          children: [
            // Draggable area
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _updateMaximized,
              ),
            ),
            // Content
            if (Platform.isMacOS)
              const Center(child: Text(appName))
            else
              Row(
                children: [
                  const SizedBox(width: 12),
                  // Connection status indicator
                  const _ConnectionStatusIndicator(),
                  const Spacer(),
                  // Window controls
                  _buildActions(context),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Windows 11 style control button with hover effect
class _WindowControlButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? hoverIconColor;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final defaultHoverColor = colorScheme.onSurface.withValues(alpha: 0.08);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: kHeaderHeight,
          decoration: BoxDecoration(
            color: _isHovered 
                ? (widget.hoverColor ?? defaultHoverColor)
                : Colors.transparent,
          ),
          child: Center(
            child: _isHovered && widget.hoverIconColor != null
                ? IconTheme(
                    data: IconThemeData(color: widget.hoverIconColor),
                    child: widget.icon,
                  )
                : widget.icon,
          ),
        ),
      ),
    );
  }
}

// Connection status indicator for title bar
class _ConnectionStatusIndicator extends ConsumerWidget {
  const _ConnectionStatusIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    
    // Watch VPN/TUN status via runTimeProvider
    final isStart = ref.watch(runTimeProvider.select((state) => state != null));
    
    final statusColor = isStart 
        ? const Color(0xFF4CAF50) // Green when connected
        : colorScheme.onSurface.withValues(alpha: 0.3); // Gray when disconnected
    
    final statusText = isStart 
        ? appLocalizations.running 
        : appLocalizations.stopped;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
            boxShadow: isStart
                ? [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: context.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key});

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(left: 8),
      child: const Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircleAvatar(
              foregroundImage: AssetImage("assets/images/icon.png"),
              backgroundColor: Colors.transparent,
            ),
          ),
          SizedBox(
            width: 8,
          ),
          Text(
            appName,
          ),
        ],
      ),
    );
}
