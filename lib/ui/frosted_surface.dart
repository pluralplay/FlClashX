import 'package:fl_clash/ui/context.dart';
import 'package:fl_clash/ui/liquid_glass.dart';
import 'package:fl_clash/ui/outer_shadow.dart';
import 'package:fl_clash/ui/shape.dart';
import 'package:fl_clash/ui/surface.dart';
import 'package:material_ui/material_ui.dart';

/// With glass on, frosts what lies behind it (see [LiquidGlassStyle.frost]).
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.color,
    required this.radius,
    this.shadows = const [],
    this.clipBehavior = Clip.none,
    this.opacity,
    required this.child,
  });

  final Color color;
  final BorderRadius radius;
  final List<BoxShadow> shadows;
  final Clip clipBehavior;

  /// Denser than the frost's own for a surface read more than seen through.
  final double? opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlassScope.of(context)) {
      final opaque = color.a == 1;
      final surface = Container(
        clipBehavior: clipBehavior,
        decoration: ShapeDecoration(
          color: color,
          shape: RoundedSuperellipseBorder(borderRadius: radius),
          shadows: shadows.isEmpty || opaque ? null : shadows,
        ),
        child: child,
      );
      if (shadows.isEmpty || !opaque) {
        return surface;
      }
      return CustomPaint(
        painter: SurfaceShadowPainter(corners: radius, shadows: shadows),
        child: surface,
      );
    }
    final quality = LiquidGlassScope.qualityOf(context);
    final opacity = this.opacity ?? LiquidGlassStyle.frostOpacity(quality);
    return LiquidGlass(
      style: LiquidGlassStyle.frost(color, quality, opacity: opacity),
      borderRadius: radius,
      shadows: shadows,
      child: FrostScope(
        surface: color,
        opacity: opacity,
        child: clipBehavior == Clip.none
            ? child
            : ClipRSuperellipse(
                borderRadius: radius,
                clipBehavior: clipBehavior,
                child: child,
              ),
      ),
    );
  }
}

/// A sheet's surface: frosted with glass on, where the pages in it, which
/// paint the theme's scaffold color, are left clear over the frost.
class FrostedSheet extends StatelessWidget {
  const FrostedSheet({
    super.key,
    required this.color,
    this.radius = BorderRadius.zero,
    required this.child,
  });

  final Color color;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassScope.of(context);
    final clip = radius == BorderRadius.zero ? Clip.none : Clip.antiAlias;
    final material = Material(
      color: glass ? Colors.transparent : color,
      shape: RoundedSuperellipseBorder(borderRadius: radius),
      clipBehavior: glass ? Clip.none : clip,
      child: child,
    );
    if (!glass) {
      return material;
    }
    return FrostedSurface(
      color: color,
      radius: radius,
      clipBehavior: clip,
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: material,
      ),
    );
  }
}

/// Marks what lies on a frosted surface, which fills over it at the frost's
/// opacity rather than frosting again, and not at all in its very color.
class FrostScope extends InheritedWidget {
  const FrostScope({
    super.key,
    required this.surface,
    required this.opacity,
    required super.child,
  });

  final Color surface;
  final double opacity;

  static FrostScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FrostScope>();

  Color fillOf(Color color) => color == surface
      ? Colors.transparent
      : color.withValues(alpha: color.a * opacity);

  @override
  bool updateShouldNotify(FrostScope oldWidget) =>
      surface != oldWidget.surface || opacity != oldWidget.opacity;
}

/// One frost behind a group of rows, whose rows then fill nothing over it.
class FrostedGroup extends StatelessWidget {
  const FrostedGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlassScope.of(context)) {
      return child;
    }
    return FrostedSurface(
      color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
      radius: AppRadius.all(AppCorner.xl),
      child: child,
    );
  }
}
