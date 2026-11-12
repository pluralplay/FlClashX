import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// Casts [shadows] only outside [rect], as glass would show them through.
void paintOuterShadows(
  Canvas canvas,
  Rect rect,
  BorderRadius corners,
  List<BoxShadow> shadows,
) {
  if (shadows.isEmpty) {
    return;
  }
  final reach = shadows.fold(
    0.0,
    (reach, shadow) => math.max(
      reach,
      shadow.offset.distance +
          math.max(shadow.spreadRadius, 0) +
          shadow.blurSigma * 3,
    ),
  );
  canvas
    ..save()
    ..clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach))
        ..addRSuperellipse(corners.toRSuperellipse(rect)),
    );
  _paintShadows(canvas, rect, corners, shadows);
  canvas.restore();
}

/// Casts [shadows] under an opaque surface over [rect]. Impeller blurs a
/// superellipse per pixel it shades, so it skips those the surface hides;
/// without MSAA that clip would thin the shadow along the surface's edge.
void paintSurfaceShadows(
  Canvas canvas,
  Rect rect,
  BorderRadius corners,
  List<BoxShadow> shadows,
) {
  if (ui.ImageFilter.isShaderFilterSupported) {
    paintOuterShadows(canvas, rect, corners, shadows);
  } else {
    _paintShadows(canvas, rect, corners, shadows);
  }
}

void _paintShadows(
  Canvas canvas,
  Rect rect,
  BorderRadius corners,
  List<BoxShadow> shadows,
) {
  for (final shadow in shadows) {
    canvas.drawRSuperellipse(
      corners.toRSuperellipse(
        rect.shift(shadow.offset).inflate(shadow.spreadRadius),
      ),
      shadow.toPaint(),
    );
  }
}

class SurfaceShadowPainter extends CustomPainter {
  const SurfaceShadowPainter({required this.corners, required this.shadows});

  final BorderRadius corners;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSurfaceShadows(canvas, Offset.zero & size, corners, shadows);

  @override
  bool shouldRepaint(SurfaceShadowPainter oldDelegate) =>
      corners != oldDelegate.corners ||
      !listEquals(shadows, oldDelegate.shadows);
}
