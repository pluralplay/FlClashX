import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoreStatusButton extends ConsumerStatefulWidget {
  const CoreStatusButton({super.key});

  @override
  ConsumerState<CoreStatusButton> createState() => _CoreStatusButtonState();
}

class _CoreStatusButtonState extends ConsumerState<CoreStatusButton> {
  static const _holdDuration = Duration(milliseconds: 600);

  Timer? _holdTimer;
  CoreStatus _status = CoreStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _status = ref.read(coreStatusProvider);
    ref.listenManual(coreStatusProvider, (_, next) {
      _onStatusChanged(next);
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onStatusChanged(CoreStatus next) {
    setState(() {
      _status = next;
      switch (next) {
        case CoreStatus.connecting:
          _holdTimer ??= Timer(_holdDuration, () {
            if (mounted) {
              setState(() {
                _holdTimer = null;
              });
            }
          });
          break;
        case CoreStatus.disconnected:
          _holdTimer?.cancel();
          _holdTimer = null;
          break;
        case CoreStatus.connected:
          break;
      }
    });
  }

  Future<void> _handleConnection() async {
    if (_holdTimer != null) {
      return;
    }
    final coreStatus = ref.read(coreStatusProvider);
    if (coreStatus == CoreStatus.connecting) {
      return;
    }
    final tip = coreStatus == CoreStatus.connected
        ? context.appLocalizations.forceRestartCoreTip
        : context.appLocalizations.restartCoreTip;
    final res = await dialogs.showMessage(message: TextSpan(text: tip));
    if (res != true || !mounted) {
      return;
    }
    try {
      await ref.read(coreActionProvider.notifier).restartCore();
    } catch (error) {
      dialogs.showNotifier(error.toString(), level: MessageLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coreStatus = _holdTimer != null ? CoreStatus.connecting : _status;
    final appLocalizations = context.appLocalizations;
    const style = ElasticPress.buttonStyle;
    final iconOnly =
        coreStatus == CoreStatus.connected || ViewScope.isMobileOf(context);
    final icon = CorePulse(status: coreStatus);
    return Tooltip(
      message: appLocalizations.coreStatus,
      child: FadeScaleBox(
        alignment: Alignment.centerRight,
        child: iconOnly
            ? IconButton.filled(
                key: ValueKey(iconOnly),
                style: style,
                onPressed: _handleConnection,
                icon: icon,
              )
            : FilledButton.icon(
                key: ValueKey(iconOnly),
                onPressed: _handleConnection,
                style: style,
                icon: SizedBox.square(
                  dimension: globalState.measure.textHeight(
                    AppTextStyle.subheadline,
                  ),
                  child: icon,
                ),
                label: Text(switch (coreStatus) {
                  CoreStatus.connecting => appLocalizations.connecting,
                  CoreStatus.connected => appLocalizations.connected,
                  CoreStatus.disconnected => appLocalizations.disconnected,
                }),
              ),
      ),
    );
  }
}

/// The waveform of each Core state, as seven points on the 24-unit glyph grid
/// so one morphs into the next.
const _beatWave = [
  Offset(2.5, 12),
  Offset(7, 12),
  Offset(9.2, 6.5),
  Offset(12.4, 17.5),
  Offset(14.8, 10),
  Offset(16.3, 12),
  Offset(21.5, 12),
];
const _searchWave = [
  Offset(2.5, 12),
  Offset(7, 12),
  Offset(9.2, 9),
  Offset(12.4, 15),
  Offset(14.8, 11),
  Offset(16.3, 12),
  Offset(21.5, 12),
];
// One last weak beat, then the line goes flat.
const _flatlineWave = [
  Offset(2.5, 12),
  Offset(6, 12),
  Offset(7.6, 9.4),
  Offset(9.2, 14.4),
  Offset(10.6, 12),
  Offset(16.3, 12),
  Offset(21.5, 12),
];
const _flatlineAliveTo = 4;

typedef _Wave = ({List<Offset> points, Color color});

/// A heartbeat line for the Core. While it is up a beat runs along the line
/// every few seconds; while it connects a light keeps sweeping small beats;
/// once it is down a last beat ends in a faded flat line. Each state morphs
/// into the next. Beats are spaced out because an endless animation in the bar
/// would repaint every frame.
class CorePulse extends StatefulWidget {
  const CorePulse({super.key, required this.status});

  final CoreStatus status;

  @override
  State<CorePulse> createState() => _CorePulseState();
}

class _CorePulseState extends State<CorePulse> with TickerProviderStateMixin {
  static const _morphDuration = Duration(milliseconds: 360);
  static const _beat = Duration(milliseconds: 1100);
  static const _beatEvery = Duration(seconds: 4);
  static const _sweep = Duration(milliseconds: 1000);

  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: _morphDuration,
    value: 1,
  );
  late final AnimationController _motion = AnimationController(vsync: this);
  Timer? _beats;
  _Wave? _from;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(CorePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _from = _shown(oldWidget.status);
      if (!context.disableAnimations) {
        _morph.forward(from: 0);
      }
      _animate();
    }
  }

  @override
  void dispose() {
    _beats?.cancel();
    _morph.dispose();
    _motion.dispose();
    super.dispose();
  }

  _Wave _waveOf(CoreStatus status) {
    final colorScheme = context.colorScheme;
    return switch (status) {
      CoreStatus.connected => (
        points: _beatWave,
        color: colorScheme.primary.withValues(alpha: 0.5),
      ),
      CoreStatus.connecting => (
        points: _searchWave,
        color: colorScheme.warning.withValues(alpha: 0.4),
      ),
      CoreStatus.disconnected => (
        points: _flatlineWave,
        color: colorScheme.error,
      ),
    };
  }

  /// What is on screen now, mid-morph included, so a change during one starts
  /// from there instead of jumping.
  _Wave _shown(CoreStatus status) {
    final to = _waveOf(status);
    final from = _from;
    if (from == null || _morph.isCompleted) {
      return to;
    }
    return _lerpWave(from, to, Curves.easeInOut.transform(_morph.value));
  }

  void _animate() {
    _beats?.cancel();
    _beats = null;
    _motion.stop();
    if (context.disableAnimations) {
      _morph.value = 1;
      _motion.value = 0;
      return;
    }
    switch (widget.status) {
      case CoreStatus.connected:
        _motion.duration = _beat;
        _motion.forward(from: 0);
        _beats = Timer.periodic(_beatEvery, (_) => _motion.forward(from: 0));
      case CoreStatus.connecting:
        _motion.duration = _sweep;
        _motion.repeat();
      case CoreStatus.disconnected:
        _motion.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final colorScheme = context.colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(iconTheme.size ?? Glyph.size),
        painter: _PulsePainter(
          status: widget.status,
          from: _from ?? _waveOf(widget.status),
          to: _waveOf(widget.status),
          morph: _morph,
          motion: _motion,
          beat: colorScheme.primary,
          sweep: colorScheme.warning,
          lineWidth: glyphLineWidth(iconTheme.fill ?? 0),
        ),
      ),
    );
  }
}

_Wave _lerpWave(_Wave a, _Wave b, double t) => (
  points: [
    for (var i = 0; i < a.points.length; i++)
      Offset.lerp(a.points[i], b.points[i], t)!,
  ],
  color: Color.lerp(a.color, b.color, t)!,
);

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.status,
    required this.from,
    required this.to,
    required this.morph,
    required this.motion,
    required this.beat,
    required this.sweep,
    required this.lineWidth,
  }) : super(repaint: Listenable.merge([morph, motion]));

  static const _traceLength = 9.0;

  final CoreStatus status;
  final _Wave from;
  final _Wave to;
  final Animation<double> morph;
  final Animation<double> motion;
  final Color beat;
  final Color sweep;
  final double lineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.shortestSide / Glyph.size);
    final morphed = Curves.easeInOut.transform(morph.value);
    final wave = _lerpWave(from, to, morphed);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..addPolygon(wave.points, false);
    final metric = path.computeMetrics().first;
    if (status == CoreStatus.disconnected) {
      final alive = _lengthTo(wave.points, _flatlineAliveTo);
      canvas.drawPath(path, line..color = wave.color.withValues(alpha: 0.35));
      canvas.drawPath(metric.extractPath(0, alive), line..color = wave.color);
    } else {
      canvas.drawPath(path, line..color = wave.color);
    }
    final running = motion.value > 0 && motion.value < 1;
    if (running && status != CoreStatus.disconnected) {
      final head = motion.value * (metric.length + _traceLength);
      final trace = metric.extractPath(
        math.max(0, head - _traceLength),
        math.min(metric.length, head),
      );
      final color = status == CoreStatus.connected ? beat : sweep;
      canvas.drawPath(
        trace,
        line..color = color.withValues(alpha: color.a * morphed),
      );
    }
    canvas.restore();
  }

  static double _lengthTo(List<Offset> points, int index) {
    var length = 0.0;
    for (var i = 1; i <= index; i++) {
      length += (points[i] - points[i - 1]).distance;
    }
    return length;
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.status != status ||
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.beat != beat ||
      oldDelegate.sweep != sweep ||
      oldDelegate.lineWidth != lineWidth;
}
