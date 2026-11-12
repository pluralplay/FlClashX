import 'dart:async';

import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract interface class RisingVibration {
  void rise(Duration duration);

  void stop();
}

class _AppVibration implements RisingVibration {
  const _AppVibration();

  @override
  void rise(Duration duration) => unawaited(app?.riseVibration(duration));

  @override
  void stop() => unawaited(app?.stopVibration());
}

/// Runs [onHeld] once a press has lasted [holdFor], under a vibration that
/// grows until then; a tap still reaches [child].
class RisingHold extends StatefulWidget {
  const RisingHold({
    super.key,
    required this.enabled,
    required this.onHeld,
    this.holdFor = const Duration(seconds: 5),
    this.vibration = const _AppVibration(),
    required this.child,
  });

  final bool enabled;
  final VoidCallback onHeld;
  final Duration holdFor;
  final RisingVibration vibration;
  final Widget child;

  @override
  State<RisingHold> createState() => _RisingHoldState();
}

class _RisingHoldState extends State<RisingHold> {
  Timer? _hold;

  // The long press is recognized only after kLongPressTimeout of the hold.
  Duration get _rise => widget.holdFor - kLongPressTimeout;

  void _start(LongPressStartDetails _) {
    _hold?.cancel();
    _hold = Timer(_rise, _complete);
    widget.vibration.rise(_rise);
  }

  void _complete() {
    _hold = null;
    unawaited(HapticFeedback.heavyImpact());
    widget.onHeld();
  }

  void _release() {
    if (_hold == null) return;
    _hold!.cancel();
    _hold = null;
    widget.vibration.stop();
  }

  @override
  void didUpdateWidget(RisingHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _release();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      excludeFromSemantics: true,
      onLongPressStart: _start,
      onLongPressEnd: (_) => _release(),
      onLongPressCancel: _release,
      child: widget.child,
    );
  }
}
