import 'package:material_ui/material_ui.dart';

/// A null [badge] clears one set further up, for titles nested in a marked one.
class TitleBadge extends InheritedWidget {
  const TitleBadge({super.key, required this.badge, required super.child});

  final Widget? badge;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TitleBadge>()?.badge;

  static Widget wrap(BuildContext context, Widget title) {
    final badge = of(context);
    if (badge == null) {
      return title;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: title),
        const SizedBox(width: 6),
        badge,
      ],
    );
  }

  @override
  bool updateShouldNotify(TitleBadge oldWidget) => badge != oldWidget.badge;
}
