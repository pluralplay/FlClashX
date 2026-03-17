import 'dart:math';

import 'package:flclashx/common/common.dart';
import 'package:flutter/material.dart';

@immutable
class DonutChartData {

  const DonutChartData({
    required double value,
    required this.color,
  }) : _value = value + 1;
  final double _value;
  final Color color;

  double get value => _value;

  @override
  String toString() => 'DonutChartData{_value: $_value}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DonutChartData &&
          runtimeType == other.runtimeType &&
          _value == other._value &&
          color == other.color;

  @override
  int get hashCode => _value.hashCode ^ color.hashCode;
}

class DonutChart extends StatefulWidget {

  const DonutChart({
    super.key,
    required this.data,
    this.duration = commonDuration,
  });
  final List<DonutChartData> data;
  final Duration duration;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<DonutChartData> _oldData;

  @override
  void initState() {
    super.initState();
    _oldData = widget.data;
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(DonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _oldData = oldWidget.data;
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) => CustomPaint(
          painter: DonutChartPainter(
            _oldData,
            widget.data,
            _animationController.value,
          ),
        ),
    );
}

class DonutChartPainter extends CustomPainter {

  DonutChartPainter(this.oldData, this.newData, this.progress);
  final List<DonutChartData> oldData;
  final List<DonutChartData> newData;
  final double progress;

  double _logTransform(double value) {
    const base = 10.0;
    const minValue = 0.1;
    if (value < minValue) return 0;
    return log(value) / log(base) + 1;
  }

  double _expTransform(double value) {
    const base = 10.0;
    if (value <= 0) return 0;
    return pow(base, value - 1).toDouble();
  }

  List<DonutChartData> get interpolatedData {
    if (oldData.length != newData.length) return newData;
    final interpolatedData = List.generate(newData.length, (index) {
      final oldValue = oldData[index].value;
      final newValue = newData[index].value;
      final logOldValue = _logTransform(oldValue);
      final logNewValue = _logTransform(newValue);
      final interpolatedLogValue =
          logOldValue + (logNewValue - logOldValue) * progress;

      final interpolatedValue = _expTransform(interpolatedLogValue);

      return DonutChartData(
        value: interpolatedValue,
        color: newData[index].color,
      );
    });

    return interpolatedData;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = 10.0.ap;
    final radius = min(size.width / 2, size.height / 2) - strokeWidth / 2;

    final gapAngle = 2 * asin(strokeWidth * 1 / (2 * radius)) * 1.2;

    final data = interpolatedData;
    final total = data.fold<double>(
      0,
      (sum, item) => sum + item.value,
    );

    if (total <= 0) return;

    final availableAngle = 2 * pi - (data.length * gapAngle);
    var startAngle = -pi / 2 + gapAngle / 2;

    for (final item in data) {
      final sweepAngle = availableAngle * (item.value / total);

      if (sweepAngle <= 0) continue;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = item.color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(DonutChartPainter oldDelegate) => oldDelegate.progress != progress ||
        oldDelegate.oldData != oldData ||
        oldDelegate.newData != newData;
}
