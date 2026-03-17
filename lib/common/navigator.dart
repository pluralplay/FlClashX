import 'package:flclashx/common/common.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/state.dart';
import 'package:flclashx/widgets/dialog.dart';
import 'package:flutter/material.dart';

class BaseNavigator {
  static Future<T?> push<T>(BuildContext context, Widget child) async {
    if (globalState.appState.viewMode != ViewMode.mobile) {
      return Navigator.of(context).push<T>(
        CommonDesktopRoute(
          builder: (context) => child,
        ),
      );
    }
    return Navigator.of(context).push<T>(
      CommonRoute(
        builder: (context) => child,
      ),
    );
  }

  static Future<T?> modal<T>(BuildContext context, Widget child) async {
    if (globalState.appState.viewMode != ViewMode.mobile) {
      return globalState.showCommonDialog<T>(
        child: CommonModal(
          child: child,
        ),
      );
    }
    return Navigator.of(context).push<T>(
      CommonRoute(
        builder: (context) => child,
      ),
    );
  }
}

class CommonDesktopRoute<T> extends PageRoute<T> {

  CommonDesktopRoute({
    required this.builder,
  });
  final Widget Function(BuildContext context) builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final result = builder(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: FadeTransition(
        opacity: animation,
        child: result,
      ),
    );
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);
}

class CommonRoute<T> extends MaterialPageRoute<T> {
  CommonRoute({
    required super.builder,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);
}

final Animatable<Offset> _kRightMiddleTween = Tween<Offset>(
  begin: const Offset(1.0, 0.0),
  end: Offset.zero,
);
final Animatable<Offset> _kMiddleLeftTween = Tween<Offset>(
  begin: Offset.zero,
  end: const Offset(-1.0 / 3.0, 0.0),
);

class CommonPageTransitionsBuilder extends PageTransitionsBuilder {
  const CommonPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CommonPageTransition(
      context: context,
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: false,
      child: child,
    );
}

class CommonPageTransition extends StatefulWidget {
  const CommonPageTransition({
    super.key,
    required this.context,
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.child,
    required this.linearTransition,
  });

  final Widget child;

  final Animation<double> primaryRouteAnimation;

  final Animation<double> secondaryRouteAnimation;

  final BuildContext context;

  final bool linearTransition;

  static Widget? delegatedTransition(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      bool allowSnapshotting,
      Widget? child) {
    final delegatedPositionAnimation = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.linearToEaseOut,
      reverseCurve: Curves.easeInToLinear,
    ).drive(_kMiddleLeftTween);

    assert(debugCheckHasDirectionality(context));
    final textDirection = Directionality.of(context);
    return SlideTransition(
      position: delegatedPositionAnimation,
      textDirection: textDirection,
      transformHitTests: false,
      child: child,
    );
  }

  @override
  State<CommonPageTransition> createState() => _CommonPageTransitionState();
}

class _CommonPageTransitionState extends State<CommonPageTransition> {
  late Animation<Offset> _primaryPositionAnimation;
  late Animation<Offset> _secondaryPositionAnimation;
  // ignore: unused_field - used for decoration animation setup
  late Animation<Decoration> _primaryShadowAnimation;
  CurvedAnimation? _primaryPositionCurve;
  CurvedAnimation? _secondaryPositionCurve;
  CurvedAnimation? _primaryShadowCurve;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(covariant CommonPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryRouteAnimation != widget.primaryRouteAnimation ||
        oldWidget.secondaryRouteAnimation != widget.secondaryRouteAnimation ||
        oldWidget.linearTransition != widget.linearTransition) {
      _disposeCurve();
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _disposeCurve();
    super.dispose();
  }

  void _disposeCurve() {
    _primaryPositionCurve?.dispose();
    _secondaryPositionCurve?.dispose();
    _primaryShadowCurve?.dispose();
    _primaryPositionCurve = null;
    _secondaryPositionCurve = null;
    _primaryShadowCurve = null;
  }

  void _setupAnimation() {
    if (!widget.linearTransition) {
      _primaryPositionCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: Curves.fastEaseInToSlowEaseOut,
        reverseCurve: Curves.fastEaseInToSlowEaseOut.flipped,
      );
      _secondaryPositionCurve = CurvedAnimation(
        parent: widget.secondaryRouteAnimation,
        curve: Curves.linearToEaseOut,
        reverseCurve: Curves.easeInToLinear,
      );
      _primaryShadowCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: Curves.linearToEaseOut,
      );
    }
    _primaryPositionAnimation =
        (_primaryPositionCurve ?? widget.primaryRouteAnimation)
            .drive(_kRightMiddleTween);
    _secondaryPositionAnimation =
        (_secondaryPositionCurve ?? widget.secondaryRouteAnimation)
            .drive(_kMiddleLeftTween);
    _primaryShadowAnimation =
        (_primaryShadowCurve ?? widget.primaryRouteAnimation).drive(
      DecorationTween(
        begin: const _CommonEdgeShadowDecoration(),
        end: _CommonEdgeShadowDecoration(
          <Color>[
            widget.context.colorScheme.inverseSurface.withValues(alpha: 0.02),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    final textDirection = Directionality.of(context);
    return SlideTransition(
      position: _secondaryPositionAnimation,
      textDirection: textDirection,
      transformHitTests: false,
      child: SlideTransition(
        position: _primaryPositionAnimation,
        textDirection: textDirection,
        child: widget.child,
      ),
    );
  }
}

class _CommonEdgeShadowDecoration extends Decoration {

  const _CommonEdgeShadowDecoration([this._colors]);
  final List<Color>? _colors;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _CommonEdgeShadowPainter(this, onChanged);
}

class _CommonEdgeShadowPainter extends BoxPainter {
  _CommonEdgeShadowPainter(
    this._decoration,
    super.onChanged,
  ) : assert(_decoration._colors == null || _decoration._colors.length > 1);

  final _CommonEdgeShadowDecoration _decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final colors = _decoration._colors;
    if (colors == null) {
      return;
    }

    final shadowWidth = 1 * configuration.size!.width;
    final shadowHeight = configuration.size!.height;
    final bandWidth = shadowWidth / (colors.length - 1);

    final textDirection = configuration.textDirection;
    assert(textDirection != null);
    final (double shadowDirection, double start) = switch (textDirection!) {
      TextDirection.rtl => (1, offset.dx + configuration.size!.width),
      TextDirection.ltr => (-1, offset.dx),
    };

    var bandColorIndex = 0;
    for (var dx = 0; dx < shadowWidth; dx += 1) {
      if (dx ~/ bandWidth != bandColorIndex) {
        bandColorIndex += 1;
      }
      final paint = Paint()
        ..color = Color.lerp(colors[bandColorIndex], colors[bandColorIndex + 1],
            (dx % bandWidth) / bandWidth)!;
      final x = start + shadowDirection * dx;
      canvas.drawRect(
          Rect.fromLTWH(x - 1.0, offset.dy, 1.0, shadowHeight), paint);
    }
  }
}
