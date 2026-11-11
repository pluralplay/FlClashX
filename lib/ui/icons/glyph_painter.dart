import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent, lerpDouble;

import 'package:fl_clash/ui/icons/glyph.dart';
import 'package:material_ui/material_ui.dart';

const _grid = Rect.fromLTWH(0, 0, Glyph.size, Glyph.size);
const _fillStart = Glyph.strokeWidth / 2;

// Details thin away before this point and return as cutouts after it, so a
// detail never shows as a stroke and a cutout at once.
const _detailSwap = 0.5;

// Lines have nothing to fill, so they gain weight instead and hold their own
// beside filled bodies; a solid line, such as a dot, grows with them.
const _filledLineWidth = 2.2;

class GlyphPainter extends CustomPainter {
  const GlyphPainter({
    required this.glyph,
    required this.fill,
    required this.color,
  });

  final Glyph glyph;
  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final opaque = color.withValues(alpha: 1);
    final stroke = _stroke(opaque, Glyph.strokeWidth);
    final lineWidth = lerpDouble(
      Glyph.strokeWidth,
      _filledLineWidth,
      fill.clamp(0, 1),
    )!;
    final line = _stroke(opaque, lineWidth);
    final area = Paint()..color = opaque;
    Paint paintFor(GlyphShape shape) => shape.solid
        ? area
        : shape.role == GlyphRole.line
        ? line
        : stroke;

    final cut = fill > _detailSwap;
    final detailScale = cut
        ? (fill - _detailSwap) / (1 - _detailSwap)
        : 1 - fill / _detailSwap;
    final cuts =
        cut &&
        detailScale > 0 &&
        glyph.shapes.any((shape) => shape.role == GlyphRole.detail);
    final cutBody = cuts && detailScale == 1 && color.a == 1
        ? _cutBodyOf(glyph)
        : null;
    final precut = cutBody != null;
    canvas.save();
    canvas.scale(size.shortestSide / Glyph.size);
    // Opaque strokes under one alpha keep a translucent color even on overlaps,
    // and cutouts clear only the glyph's own layer. A layer is an offscreen
    // pass every frame, so a glyph at rest takes its cutouts as geometry.
    if (color.a < 1 || (cuts && !precut)) {
      canvas.saveLayer(
        _grid,
        Paint()..color = Color.fromRGBO(0, 0, 0, color.a),
      );
    } else {
      canvas.save();
    }
    if (precut) {
      canvas.drawPath(cutBody, area);
    } else {
      for (final shape in glyph.shapes) {
        if (shape.role == GlyphRole.body) {
          _paintFill(canvas, shape.path, opaque);
        }
      }
    }
    if (detailScale > 0 && !precut) {
      for (final shape in glyph.shapes) {
        if (shape.role == GlyphRole.detail) {
          _paintDetail(canvas, shape, opaque, detailScale, cut: cut);
        }
      }
    }
    for (final shape in glyph.shapes) {
      if (shape.role == GlyphRole.line && shape.solid) {
        _drawScaled(canvas, shape.path, area, lineWidth / Glyph.strokeWidth);
      } else if (shape.role != GlyphRole.detail) {
        canvas.drawPath(shape.path, paintFor(shape));
      }
    }
    canvas.restore();
    canvas.restore();
  }

  void _paintFill(Canvas canvas, Path body, Color color) {
    if (fill <= 0) {
      return;
    }
    if (fill >= 1) {
      canvas.drawPath(body, Paint()..color = color);
      return;
    }
    final depth = body.getBounds().shortestSide / 2;
    final reach = _fillStart + (depth - _fillStart) * fill;
    canvas.save();
    canvas.clipPath(body);
    canvas.drawPath(body, _stroke(color, reach * 2));
    canvas.restore();
  }

  void _paintDetail(
    Canvas canvas,
    GlyphShape detail,
    Color color,
    double scale, {
    required bool cut,
  }) {
    final blendMode = cut ? BlendMode.clear : BlendMode.srcOver;
    if (!detail.solid) {
      canvas.drawPath(
        detail.path,
        _stroke(color, Glyph.strokeWidth * scale)..blendMode = blendMode,
      );
      return;
    }
    _drawScaled(
      canvas,
      detail.path,
      Paint()
        ..color = color
        ..blendMode = blendMode,
      scale,
    );
  }

  void _drawScaled(Canvas canvas, Path path, Paint paint, double scale) {
    final center = path.getBounds().center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      fill != oldDelegate.fill ||
      color != oldDelegate.color;
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

final _cutBodies = Expando<({Path? path})>();

/// The filled bodies of a full [glyph] less what its details clear from them,
/// or null where path operations fail on its shapes.
Path? _cutBodyOf(Glyph glyph) =>
    (_cutBodies[glyph] ??= (path: _cutBody(glyph))).path;

Path? _cutBody(Glyph glyph) {
  try {
    var body = Path();
    for (final shape in glyph.shapes) {
      if (shape.role == GlyphRole.body) {
        body = Path.combine(PathOperation.union, body, shape.path);
      }
    }
    for (final shape in glyph.shapes) {
      if (shape.role == GlyphRole.detail) {
        body = Path.combine(
          PathOperation.difference,
          body,
          shape.solid ? shape.path : _strokeArea(shape),
        );
      }
    }
    return body;
  } on StateError {
    return null;
  }
}

const _halfStroke = Glyph.strokeWidth / 2;

/// What a round-capped, round-joined stroke of [shape] covers.
Path _strokeArea(GlyphShape shape) {
  if (shape is GlyphCircle) {
    final rect = shape.path.getBounds();
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(rect.inflate(_halfStroke))
      ..addOval(rect.deflate(_halfStroke));
  }
  final area = Path();
  for (final metric in shape.path.computeMetrics()) {
    final points = _clean(_flatten(metric), metric.isClosed);
    if (points.length > 1) {
      _addOutline(area, points, metric.isClosed);
    }
  }
  return area;
}

// A chord stands in for a curve while it stays this close to it in position
// and its ends in direction; a tangent jump across a shorter span is a corner.
const _flatTolerance = 0.004;
const _flatTurn = 0.05;
const _cornerSpan = 0.02;
const _cornerTurn = 0.1;

List<Offset> _flatten(PathMetric metric) {
  final points = <Offset>[];
  void walk(double from, Tangent start, double to, Tangent end) {
    final span = to - from;
    if (span <= _cornerSpan) {
      if (_angle(start.vector, end.vector).abs() >= _cornerTurn) {
        points.add(_meet(start, end));
      }
      points.add(end.position);
      return;
    }
    final mid = metric.getTangentForOffset(from + span / 2)!;
    final chord = end.position - start.position;
    final fits =
        _distance(mid.position, start.position, end.position) <=
            _flatTolerance &&
        [
          start,
          mid,
          end,
        ].every((tangent) => _angle(tangent.vector, chord).abs() <= _flatTurn);
    if (fits) {
      points.add(end.position);
    } else {
      walk(from, start, from + span / 2, mid);
      walk(from + span / 2, mid, to, end);
    }
  }

  final start = metric.getTangentForOffset(0)!;
  points.add(start.position);
  walk(0, start, metric.length, metric.getTangentForOffset(metric.length)!);
  return points;
}

Offset _meet(Tangent start, Tangent end) {
  final along =
      _cross(end.position - start.position, end.vector) /
      _cross(start.vector, end.vector);
  return start.position + start.vector * along;
}

double _distance(Offset point, Offset from, Offset to) {
  final chord = to - from;
  if (chord.distance == 0) {
    return (point - from).distance;
  }
  return _cross(chord, point - from).abs() / chord.distance;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

double _angle(Offset from, Offset to) =>
    math.atan2(_cross(from, to), from.dx * to.dx + from.dy * to.dy);

List<Offset> _clean(List<Offset> points, bool closed) {
  final distinct = <Offset>[];
  for (final point in points) {
    if (distinct.isEmpty || (point - distinct.last).distance > 1e-6) {
      distinct.add(point);
    }
  }
  if (closed &&
      distinct.length > 1 &&
      (distinct.first - distinct.last).distance <= 1e-6) {
    distinct.removeLast();
  }
  final count = distinct.length;
  return [
    for (var index = 0; index < count; index++)
      if (!closed && (index == 0 || index == count - 1))
        distinct[index]
      else if (_angle(
            distinct[index] - distinct[(index - 1 + count) % count],
            distinct[(index + 1) % count] - distinct[index],
          ).abs() >
          1e-6)
        distinct[index],
  ];
}

/// The outline of a round-capped stroke along [points]: offset sides, an arc
/// around each outer corner and a chord across each inner one, which the
/// nonzero rule fills as the union of the capsules the segments span.
void _addOutline(Path area, List<Offset> points, bool closed) {
  final count = closed ? points.length : points.length - 1;
  final normals = [
    for (var index = 0; index < count; index++)
      _normal(points[index], points[(index + 1) % points.length]),
  ];
  Offset offset(int index, Offset normal) =>
      points[index] + normal * _halfStroke;
  void line(int index, Offset normal) {
    final point = offset(index, normal);
    area.lineTo(point.dx, point.dy);
  }

  void arc(int index, Offset from, double sweep) => area.arcTo(
    Rect.fromCircle(center: points[index], radius: _halfStroke),
    from.direction,
    sweep,
    false,
  );
  void join(int index, Offset from, Offset to) {
    final turn = _angle(from, to);
    if (turn < 0) {
      arc(index, from, turn);
    } else {
      line(index, to);
    }
  }

  if (closed) {
    final first = offset(0, normals.last);
    area.moveTo(first.dx, first.dy);
    for (var index = 0; index < count; index++) {
      join(index, normals[(index - 1 + count) % count], normals[index]);
      line((index + 1) % count, normals[index]);
    }
    area.close();
    final last = offset(0, -normals.first);
    area.moveTo(last.dx, last.dy);
    for (var step = 0; step < count; step++) {
      final index = (count - step) % count;
      final previous = (index - 1 + count) % count;
      join(index, -normals[index], -normals[previous]);
      line(previous, -normals[previous]);
    }
    area.close();
    return;
  }
  final first = offset(0, normals.first);
  area.moveTo(first.dx, first.dy);
  for (var index = 1; index < count; index++) {
    line(index, normals[index - 1]);
    join(index, normals[index - 1], normals[index]);
  }
  line(count, normals.last);
  arc(count, normals.last, -math.pi);
  for (var index = count - 1; index > 0; index--) {
    line(index, -normals[index]);
    join(index, -normals[index], -normals[index - 1]);
  }
  line(0, -normals.first);
  arc(0, -normals.first, -math.pi);
  area.close();
}

Offset _normal(Offset from, Offset to) {
  final along = (to - from) / (to - from).distance;
  return Offset(-along.dy, along.dx);
}
