import 'package:material_ui/material_ui.dart';

/// How much of a page backdrop shows through when the panel does not say.
const defaultBackdropVisibility = 8;

/// A picture behind every full page, dimmed by the page colour down to
/// [visibility] percent of it.
class PageBackdropScope extends InheritedWidget {
  const PageBackdropScope({
    super.key,
    required this.image,
    this.visibility = defaultBackdropVisibility,
    required super.child,
  });

  final ImageProvider? image;
  final int visibility;

  static PageBackdropScope? of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PageBackdropScope>();
    return scope?.image == null ? null : scope;
  }

  double get scrimAlpha => (1 - visibility.clamp(1, 100) / 100).toDouble();

  Color scrimOf(Color page) => page.withValues(alpha: scrimAlpha);

  @override
  bool updateShouldNotify(PageBackdropScope oldWidget) =>
      image != oldWidget.image || visibility != oldWidget.visibility;
}

class PageBackdrop extends StatelessWidget {
  const PageBackdrop({super.key, required this.scope, required this.page});

  final PageBackdropScope scope;
  final Color page;

  @override
  Widget build(BuildContext context) {
    final alpha = scope.scrimAlpha;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: scope.image!,
              fit: BoxFit.cover,
              onError: (_, _) {},
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  page.withValues(alpha: alpha),
                  page.withValues(alpha: (alpha - 0.04).clamp(0.0, 1.0)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
