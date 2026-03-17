import 'package:flclashx/manager/message_manager.dart';
import 'package:flclashx/widgets/scaffold.dart';
import 'package:flutter/material.dart';

extension BuildContextExtension on BuildContext {
  CommonScaffoldState? get commonScaffoldState => findAncestorStateOfType<CommonScaffoldState>();

  Future<void>? showNotifier(String text) => findAncestorStateOfType<MessageManagerState>()?.message(text);

  void showSnackBar(
    String message, {
    SnackBarAction? action,
  }) {
    final width = viewWidth;
    EdgeInsets margin;
    if (width < 600) {
      margin = const EdgeInsets.only(
        bottom: 16,
        right: 16,
        left: 16,
      );
    } else {
      margin = EdgeInsets.only(
        bottom: 16,
        left: 16,
        right: width - 316,
      );
    }
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        action: action,
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: margin,
      ),
    );
  }

  Size get appSize => MediaQuery.of(this).size;

  double get viewWidth => appSize.width;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;

  T? findLastStateOfType<T extends State>() {
    T? state;

    void visitor(Element element) {
      if (!element.mounted) {
        return;
      }
      if (element is StatefulElement) {
        if (element.state is T) {
          state = element.state as T;
        }
      }
      element.visitChildren(visitor);
    }

    visitor(this as Element);
    return state;
  }
}
